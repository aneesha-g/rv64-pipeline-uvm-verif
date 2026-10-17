// 5-stage pipeline: IF -> ID -> EX -> MEM -> WB
//  - forwarding: EX/MEM and MEM/WB -> EX, plus regfile write-through (WB -> ID)
//  - load-use: 1-cycle stall (bubble into EX)
//  - [P4] IF guesses the next pc with a BTB + 2-bit counters (bpred.v)
//  - [P4] EX compares the guess with the real next pc; mismatch flushes IF/ID + ID/EX
//  - ecall/illegal: stop fetching; retires last, then the TB ends the run
module core #(
  parameter XLEN = 32,
  parameter [XLEN-1:0] RESET_PC = 'h80000000,
  parameter BP_EN = 1,              // [P4] 1 = predictor on, 0 = always predict not-taken
  parameter BTB_ENTRIES = 64,       // [P4]
  parameter IC_LINES = 64           // [P5] icache lines, 16 bytes each
)(
  input                    clk,
  input                    rst_n,
  output                   imem_req,       // [P5] icache line-fill port
  output [XLEN-1:0]        imem_addr,
  input                    imem_rvalid,
  input  [31:0]            imem_rdata,
  output [XLEN-1:0]        dmem_addr,
  output                   dmem_we,
  output [XLEN/8-1:0]      dmem_wmask,
  output [XLEN-1:0]        dmem_wdata,
  input  [XLEN-1:0]        dmem_rdata,
  output                   rvfi_valid,
  output [63:0]            rvfi_order,
  output [31:0]            rvfi_insn,
  output                   rvfi_trap,
  output                   rvfi_halt,
  output [XLEN-1:0]        rvfi_pc_rdata,
  output [XLEN-1:0]        rvfi_pc_wdata,
  output [4:0]             rvfi_rd_addr,
  output [XLEN-1:0]        rvfi_rd_wdata,
  output [XLEN-1:0]        rvfi_mem_addr,
  output [XLEN/8-1:0]      rvfi_mem_rmask,
  output [XLEN/8-1:0]      rvfi_mem_wmask,
  output [XLEN-1:0]        rvfi_mem_rdata,
  output [XLEN-1:0]        rvfi_mem_wdata
);
  localparam BYTES = XLEN / 8;
  localparam OFFW  = (XLEN == 64) ? 3 : 2;

  // ================= pipeline registers =================
  reg             halting;                 // set once ecall/illegal is past ID
  reg [XLEN-1:0]  pc;                      // IF

  reg             ifid_valid;              // IF/ID
  reg [XLEN-1:0]  ifid_pc;
  reg [XLEN-1:0]  ifid_pred_pc;            // [P4] pc that IF fetched after this insn
  reg [31:0]      ifid_insn;

  reg             idex_valid;              // ID/EX
  reg [XLEN-1:0]  idex_pc;
  reg [XLEN-1:0]  idex_pred_pc;            // [P4]
  reg [31:0]      idex_insn;
  reg [XLEN-1:0]  idex_rs1_val, idex_rs2_val;

  reg             exmem_valid;             // EX/MEM
  reg [XLEN-1:0]  exmem_pc, exmem_next_pc, exmem_result, exmem_sdata;
  reg [31:0]      exmem_insn;
  reg [4:0]       exmem_rd;
  reg             exmem_wen, exmem_is_load, exmem_is_store, exmem_trap, exmem_halt;

  reg             memwb_valid;             // MEM/WB
  reg [XLEN-1:0]  memwb_pc, memwb_next_pc, memwb_val;
  reg [XLEN-1:0]  memwb_mem_addr, memwb_mem_rdata, memwb_mem_wdata;
  reg [BYTES-1:0] memwb_mem_rmask, memwb_mem_wmask;
  reg [31:0]      memwb_insn;
  reg [4:0]       memwb_rd;
  reg             memwb_wen, memwb_trap, memwb_halt;

  reg [63:0]      order;

  // ================= IF =================
  // [P5] instruction cache: direct-mapped, 16-byte lines, refilled over the imem port
  wire        ic_hit;
  wire [31:0] ic_rdata;
  icache #(.XLEN(XLEN), .LINES(IC_LINES)) u_ic (
    .clk(clk), .rst_n(rst_n),
    .req(~halting), .pc(pc), .hit(ic_hit), .rdata(ic_rdata),
    .mem_req(imem_req), .mem_addr(imem_addr),
    .mem_rvalid(imem_rvalid), .mem_rdata(imem_rdata)
  );

  // ================= ID =================
  wire [4:0] id_rs1 = ifid_insn[19:15];
  wire [4:0] id_rs2 = ifid_insn[24:20];
  wire d_is_halt, d_legal, d_uses_rs1, d_uses_rs2;
  decode #(.XLEN(XLEN)) u_dec_id (
    .insn(ifid_insn), .is_halt(d_is_halt), .legal(d_legal),
    .uses_rs1(d_uses_rs1), .uses_rs2(d_uses_rs2)
  );

  wire [XLEN-1:0] rf_rs1, rf_rs2;
  regfile #(.XLEN(XLEN)) u_rf (
    .clk(clk), .rs1_addr(id_rs1), .rs2_addr(id_rs2),
    .rs1_data(rf_rs1), .rs2_data(rf_rs2),
    .we(memwb_wen), .rd_addr(memwb_rd), .rd_data(memwb_val)
  );
  // write-through: instruction in WB writes the value that ID is reading
  wire [XLEN-1:0] id_rs1_val = (memwb_wen & (memwb_rd == id_rs1)) ? memwb_val : rf_rs1;
  wire [XLEN-1:0] id_rs2_val = (memwb_wen & (memwb_rd == id_rs2)) ? memwb_val : rf_rs2;

  // ================= EX =================
  wire e_is_lui, e_is_auipc, e_is_jal, e_is_jalr, e_is_branch, e_is_load, e_is_store;
  wire e_is_opimm, e_is_op, e_is_fence, e_is_halt, e_legal, e_writes_rd, e_uses_rs1, e_uses_rs2;
  wire [XLEN-1:0] e_imm_i, e_imm_s, e_imm_b, e_imm_u, e_imm_j;
  decode #(.XLEN(XLEN)) u_dec_ex (
    .insn(idex_insn),
    .is_lui(e_is_lui), .is_auipc(e_is_auipc), .is_jal(e_is_jal), .is_jalr(e_is_jalr),
    .is_branch(e_is_branch), .is_load(e_is_load), .is_store(e_is_store),
    .is_opimm(e_is_opimm), .is_op(e_is_op), .is_fence(e_is_fence), .is_halt(e_is_halt),
    .legal(e_legal), .writes_rd(e_writes_rd), .uses_rs1(e_uses_rs1), .uses_rs2(e_uses_rs2),
    .imm_i(e_imm_i), .imm_s(e_imm_s), .imm_b(e_imm_b), .imm_u(e_imm_u), .imm_j(e_imm_j)
  );

  wire [4:0] ex_rs1 = idex_insn[19:15];
  wire [4:0] ex_rs2 = idex_insn[24:20];
  wire [4:0] ex_rd  = idex_insn[11:7];
  wire [2:0] ex_f3  = idex_insn[14:12];

  // forwarding: youngest producer wins (EX/MEM before MEM/WB)
  wire [XLEN-1:0] ex_a =
      (exmem_wen & (exmem_rd == ex_rs1)) ? exmem_result :
      (memwb_wen & (memwb_rd == ex_rs1)) ? memwb_val    : idex_rs1_val;
  wire [XLEN-1:0] ex_b =
      (exmem_wen & (exmem_rd == ex_rs2)) ? exmem_result :
      (memwb_wen & (memwb_rd == ex_rs2)) ? memwb_val    : idex_rs2_val;

  // load-use hazard: load in EX, instruction in ID needs its result
  wire ex_load_v  = idex_valid & e_legal & e_is_load;
  wire load_use   = ex_load_v & (ex_rd != 5'd0) &
                    ((d_uses_rs1 & (id_rs1 == ex_rd)) | (d_uses_rs2 & (id_rs2 == ex_rd)));
  wire stall      = ifid_valid & load_use;

  // ALU
  wire [XLEN-1:0] alu_b  = e_is_op ? ex_b : e_imm_i;
  wire [3:0]      alu_op = e_is_op ? {idex_insn[30], ex_f3}
                                   : {(ex_f3 == 3'b101) & idex_insn[30], ex_f3};
  wire [XLEN-1:0] alu_y;
  alu #(.XLEN(XLEN)) u_alu (.a(ex_a), .b(alu_b), .op(alu_op), .y(alu_y));

  // effective address
  wire [XLEN-1:0] ex_ea = ex_a + (e_is_store ? e_imm_s : e_imm_i);

  // result carried down the pipe
  reg [XLEN-1:0] ex_result;
  always @* begin
    ex_result = alu_y;
    if      (e_is_lui)              ex_result = e_imm_u;
    else if (e_is_auipc)            ex_result = idex_pc + e_imm_u;
    else if (e_is_jal | e_is_jalr)  ex_result = idex_pc + 4;
    else if (e_is_load | e_is_store) ex_result = ex_ea;
  end

  // branch decision
  reg ex_taken;
  always @* begin
    case (ex_f3)
      3'b000:  ex_taken = (ex_a == ex_b);
      3'b001:  ex_taken = (ex_a != ex_b);
      3'b100:  ex_taken = ($signed(ex_a) <  $signed(ex_b));
      3'b101:  ex_taken = ($signed(ex_a) >= $signed(ex_b));
      3'b110:  ex_taken = (ex_a <  ex_b);
      3'b111:  ex_taken = (ex_a >= ex_b);
      default: ex_taken = 1'b0;
    endcase
  end

  wire [XLEN-1:0] jalr_t = ex_a + e_imm_i;
  reg  [XLEN-1:0] ex_next_pc;                // the REAL next pc
  always @* begin
    ex_next_pc = idex_pc + 4;
    if      (~e_legal)               ex_next_pc = idex_pc;
    else if (e_is_jal)               ex_next_pc = idex_pc + e_imm_j;
    else if (e_is_jalr)              ex_next_pc = {jalr_t[XLEN-1:1], 1'b0};
    else if (e_is_branch & ex_taken) ex_next_pc = idex_pc + e_imm_b;
  end

  // ================= [P4] branch predictor: lookup in IF, update from EX =================
  wire            if_pred_taken;
  wire [XLEN-1:0] if_pred_target;
  wire bp_upd_en    = idex_valid & e_legal & (e_is_branch | e_is_jal | e_is_jalr);
  wire bp_upd_taken = e_is_jal | e_is_jalr | (e_is_branch & ex_taken);

  bpred #(.XLEN(XLEN), .ENTRIES(BTB_ENTRIES), .BP_EN(BP_EN)) u_bp (
    .clk(clk), .rst_n(rst_n),
    .pc(pc), .pred_taken(if_pred_taken), .pred_target(if_pred_target),
    .upd_en(bp_upd_en), .upd_pc(idex_pc), .upd_taken(bp_upd_taken),
    .upd_target(ex_next_pc)
  );
  wire [XLEN-1:0] if_next_pc = if_pred_taken ? if_pred_target : pc + 4;

  // [P4] redirect whenever the guess differs from reality (covers all cases:
  // predicted-taken-but-not, not-predicted-but-taken, wrong target)
  wire ex_redirect = idex_valid & e_legal & (ex_next_pc != idex_pred_pc);

  // [P4] perf counters (the testbench prints them)
  reg [63:0] perf_ctrl, perf_redirect;
  always @(posedge clk) begin
    if (!rst_n) begin
      perf_ctrl     <= 64'd0;
      perf_redirect <= 64'd0;
    end else begin
      if (bp_upd_en)   perf_ctrl     <= perf_ctrl + 64'd1;
      if (ex_redirect) perf_redirect <= perf_redirect + 64'd1;
    end
  end

  // ================= MEM =================
  wire [2:0]       m_f3   = exmem_insn[14:12];
  wire [OFFW-1:0]  m_lane = exmem_result[OFFW-1:0];
  wire [BYTES-1:0] m_acc  = (m_f3[1:0] == 2'b00) ? 'h1 :
                            (m_f3[1:0] == 2'b01) ? 'h3 : 'hF;

  assign dmem_addr  = exmem_result;
  assign dmem_we    = exmem_is_store;
  assign dmem_wmask = m_acc << m_lane;

  wire [XLEN-1:0] m_st = (m_f3[1:0] == 2'b00) ? exmem_sdata[7:0]  :
                         (m_f3[1:0] == 2'b01) ? exmem_sdata[15:0] : exmem_sdata[31:0];
  assign dmem_wdata = m_st << {m_lane, 3'b000};

  wire [XLEN-1:0] m_rsh = dmem_rdata >> {m_lane, 3'b000};
  reg  [XLEN-1:0] m_load_raw, m_load_val;
  always @* begin
    case (m_f3)
      3'b000:  begin m_load_raw = m_rsh[7:0];  m_load_val = $signed(m_rsh[7:0]);  end // LB
      3'b001:  begin m_load_raw = m_rsh[15:0]; m_load_val = $signed(m_rsh[15:0]); end // LH
      3'b010:  begin m_load_raw = m_rsh[31:0]; m_load_val = $signed(m_rsh[31:0]); end // LW
      3'b100:  begin m_load_raw = m_rsh[7:0];  m_load_val = m_rsh[7:0];           end // LBU
      3'b101:  begin m_load_raw = m_rsh[15:0]; m_load_val = m_rsh[15:0];          end // LHU
      default: begin m_load_raw = {XLEN{1'b0}}; m_load_val = {XLEN{1'b0}};        end
    endcase
  end
  wire [XLEN-1:0] m_val = exmem_is_load ? m_load_val : exmem_result;

  // ================= control: stop fetch on ecall / illegal =================
  wire d_stop = ifid_valid & (d_is_halt | ~d_legal);

  // [P5] cycles IF is blocked waiting for an icache fill (the testbench prints this)
  wire if_miss_stall = ~ex_redirect & ~stall & ~(halting | d_stop) & ~ic_hit;
  reg [63:0] perf_ic_stall;
  always @(posedge clk) begin
    if (!rst_n)             perf_ic_stall <= 64'd0;
    else if (if_miss_stall) perf_ic_stall <= perf_ic_stall + 64'd1;
  end

  // ================= pipeline register updates =================
  always @(posedge clk) begin
    if (!rst_n) begin
      pc <= RESET_PC;
      halting <= 1'b0;
      ifid_valid <= 1'b0;
      idex_valid <= 1'b0;
      exmem_valid <= 1'b0; exmem_wen <= 1'b0; exmem_is_load <= 1'b0; exmem_is_store <= 1'b0;
      exmem_trap <= 1'b0;  exmem_halt <= 1'b0;
      memwb_valid <= 1'b0; memwb_wen <= 1'b0; memwb_trap <= 1'b0; memwb_halt <= 1'b0;
      order <= 64'd0;
    end else begin
      // ---- WB: count retired instructions ----
      if (memwb_valid) order <= order + 64'd1;

      // ---- MEM -> MEM/WB ----
      memwb_valid     <= exmem_valid;
      memwb_pc        <= exmem_pc;
      memwb_next_pc   <= exmem_next_pc;
      memwb_insn      <= exmem_insn;
      memwb_rd        <= exmem_rd;
      memwb_wen       <= exmem_wen;
      memwb_trap      <= exmem_trap;
      memwb_halt      <= exmem_halt;
      memwb_val       <= m_val;
      memwb_mem_addr  <= (exmem_is_load | exmem_is_store) ? exmem_result : {XLEN{1'b0}};
      memwb_mem_rmask <= exmem_is_load  ? m_acc      : {BYTES{1'b0}};
      memwb_mem_wmask <= exmem_is_store ? m_acc      : {BYTES{1'b0}};
      memwb_mem_rdata <= exmem_is_load  ? m_load_raw : {XLEN{1'b0}};
      memwb_mem_wdata <= exmem_is_store ? m_st       : {XLEN{1'b0}};

      // ---- EX -> EX/MEM ----
      exmem_valid    <= idex_valid;
      exmem_pc       <= idex_pc;
      exmem_next_pc  <= ex_next_pc;
      exmem_insn     <= idex_insn;
      exmem_rd       <= ex_rd;
      exmem_result   <= ex_result;
      exmem_sdata    <= ex_b;
      exmem_wen      <= idex_valid & e_legal & e_writes_rd & (ex_rd != 5'd0);
      exmem_is_load  <= idex_valid & e_legal & e_is_load;
      exmem_is_store <= idex_valid & e_legal & e_is_store;
      exmem_trap     <= idex_valid & ~e_legal;
      exmem_halt     <= idex_valid & (e_is_halt | ~e_legal);

      // ---- ID -> ID/EX ----
      if (ex_redirect | stall) begin
        idex_valid <= 1'b0;                      // bubble
      end else begin
        idex_valid   <= ifid_valid;
        idex_pc      <= ifid_pc;
        idex_pred_pc <= ifid_pred_pc;            // [P4]
        idex_insn    <= ifid_insn;
        idex_rs1_val <= id_rs1_val;
        idex_rs2_val <= id_rs2_val;
      end

      // ---- IF -> IF/ID (and PC) ----
      if (ex_redirect) begin
        pc         <= ex_next_pc;                // guess was wrong: refetch from the real pc
        ifid_valid <= 1'b0;                      // flush the wrong-path instruction
      end else if (stall) begin
        // hold pc and IF/ID
      end else if (halting | d_stop) begin
        ifid_valid <= 1'b0;                      // stop fetching after ecall/illegal
        halting    <= 1'b1;
      end else if (!ic_hit) begin
        ifid_valid <= 1'b0;                      // [P5] icache miss: bubble, hold pc, wait for the fill
      end else begin
        ifid_valid   <= 1'b1;
        ifid_pc      <= pc;
        ifid_insn    <= ic_rdata;                // [P5]
        ifid_pred_pc <= if_next_pc;              // [P4] remember the guess
        pc           <= if_next_pc;              // [P4] follow the guess
      end
    end
  end

  // ================= RVFI retire port (from WB) =================
  assign rvfi_valid     = memwb_valid;
  assign rvfi_order     = order;
  assign rvfi_insn      = memwb_insn;
  assign rvfi_trap      = memwb_trap;
  assign rvfi_halt      = memwb_halt;
  assign rvfi_pc_rdata  = memwb_pc;
  assign rvfi_pc_wdata  = memwb_next_pc;
  assign rvfi_rd_addr   = memwb_wen ? memwb_rd  : 5'd0;
  assign rvfi_rd_wdata  = memwb_wen ? memwb_val : {XLEN{1'b0}};
  assign rvfi_mem_addr  = memwb_mem_addr;
  assign rvfi_mem_rmask = memwb_mem_rmask;
  assign rvfi_mem_wmask = memwb_mem_wmask;
  assign rvfi_mem_rdata = memwb_mem_rdata;
  assign rvfi_mem_wdata = memwb_mem_wdata;
endmodule
