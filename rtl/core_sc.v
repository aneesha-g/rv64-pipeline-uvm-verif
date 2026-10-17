module core_sc #(
  parameter XLEN = 32,
  parameter [XLEN-1:0] RESET_PC = 'h80000000
)(
  input                    clk,
  input                    rst_n,
  // instruction memory (async read)
  output [XLEN-1:0]        imem_addr,
  input  [31:0]            imem_rdata,
  // data memory (async read, sync write, byte strobes)
  output [XLEN-1:0]        dmem_addr,
  output                   dmem_we,
  output [XLEN/8-1:0]      dmem_wmask,
  output [XLEN-1:0]        dmem_wdata,
  input  [XLEN-1:0]        dmem_rdata,
  // RVFI retire port
  output reg               rvfi_valid,
  output reg [63:0]        rvfi_order,
  output reg [31:0]        rvfi_insn,
  output reg               rvfi_trap,
  output reg               rvfi_halt,
  output reg [XLEN-1:0]    rvfi_pc_rdata,
  output reg [XLEN-1:0]    rvfi_pc_wdata,
  output reg [4:0]         rvfi_rd_addr,
  output reg [XLEN-1:0]    rvfi_rd_wdata,
  output reg [XLEN-1:0]    rvfi_mem_addr,
  output reg [XLEN/8-1:0]  rvfi_mem_rmask,
  output reg [XLEN/8-1:0]  rvfi_mem_wmask,
  output reg [XLEN-1:0]    rvfi_mem_rdata,
  output reg [XLEN-1:0]    rvfi_mem_wdata
);
  localparam BYTES = XLEN / 8;
  localparam OFFW  = (XLEN == 64) ? 3 : 2;

  reg [XLEN-1:0] pc;
  reg            halted;
  reg [63:0]     order;

  // ---------------- fetch ----------------
  assign imem_addr = pc;
  wire [31:0] insn = imem_rdata;

  // ---------------- decode ----------------
  wire [6:0] opcode = insn[6:0];
  wire [4:0] rd     = insn[11:7];
  wire [2:0] f3     = insn[14:12];
  wire [4:0] rs1    = insn[19:15];
  wire [4:0] rs2    = insn[24:20];
  wire [6:0] f7     = insn[31:25];

  // immediates, sign-extended to XLEN
  wire [XLEN-1:0] imm_i = $signed(insn[31:20]);
  wire [XLEN-1:0] imm_s = $signed({insn[31:25], insn[11:7]});
  wire [XLEN-1:0] imm_b = $signed({insn[31], insn[7], insn[30:25], insn[11:8], 1'b0});
  wire [XLEN-1:0] imm_u = $signed({insn[31:12], 12'b0});
  wire [XLEN-1:0] imm_j = $signed({insn[31], insn[19:12], insn[20], insn[30:21], 1'b0});

  wire is_lui    = (opcode == 7'h37);
  wire is_auipc  = (opcode == 7'h17);
  wire is_jal    = (opcode == 7'h6f);
  wire is_jalr   = (opcode == 7'h67);
  wire is_branch = (opcode == 7'h63);
  wire is_load   = (opcode == 7'h03);
  wire is_store  = (opcode == 7'h23);
  wire is_opimm  = (opcode == 7'h13);
  wire is_op     = (opcode == 7'h33);
  wire is_fence  = (opcode == 7'h0f);
  wire is_system = (opcode == 7'h73);

  wire is_halt = is_system && (insn == 32'h00000073 || insn == 32'h00100073);

  wire legal =
      is_lui | is_auipc | is_jal | is_fence | is_opimm | is_halt |
      (is_jalr   && f3 == 3'b000) |
      (is_branch && f3 != 3'b010 && f3 != 3'b011) |
      (is_load   && (f3 == 3'b000 || f3 == 3'b001 || f3 == 3'b010 ||
                     f3 == 3'b100 || f3 == 3'b101)) |
      (is_store  && (f3 == 3'b000 || f3 == 3'b001 || f3 == 3'b010)) |
      (is_op     && (f7 == 7'h00 || (f7 == 7'h20 && (f3 == 3'b000 || f3 == 3'b101))));
  wire trap = ~legal;

  // ---------------- register file ----------------
  wire [XLEN-1:0] rs1_data, rs2_data;
  wire            wb_en;
  reg  [XLEN-1:0] wb_val;

  regfile #(.XLEN(XLEN)) u_rf (
    .clk(clk), .rs1_addr(rs1), .rs2_addr(rs2),
    .rs1_data(rs1_data), .rs2_data(rs2_data),
    .we(wb_en), .rd_addr(rd), .rd_data(wb_val)
  );

  // ---------------- ALU ----------------
  wire [XLEN-1:0] alu_b  = is_op ? rs2_data : imm_i;
  wire [3:0]      alu_op = is_op ? {f7[5], f3} : {(f3 == 3'b101) & insn[30], f3};
  wire [XLEN-1:0] alu_y;
  alu #(.XLEN(XLEN)) u_alu (.a(rs1_data), .b(alu_b), .op(alu_op), .y(alu_y));

  // ---------------- branch ----------------
  reg taken;
  always @* begin
    case (f3)
      3'b000:  taken = (rs1_data == rs2_data);
      3'b001:  taken = (rs1_data != rs2_data);
      3'b100:  taken = ($signed(rs1_data) <  $signed(rs2_data));
      3'b101:  taken = ($signed(rs1_data) >= $signed(rs2_data));
      3'b110:  taken = (rs1_data <  rs2_data);
      3'b111:  taken = (rs1_data >= rs2_data);
      default: taken = 1'b0;
    endcase
  end

  // ---------------- memory ----------------
  wire [XLEN-1:0] ea   = rs1_data + (is_store ? imm_s : imm_i);
  wire [OFFW-1:0] lane = ea[OFFW-1:0];
  assign dmem_addr = ea;

  // access size from f3[1:0]: 00 byte, 01 half, 10 word
  wire [BYTES-1:0] acc_mask = (f3[1:0] == 2'b00) ? 'h1 :
                              (f3[1:0] == 2'b01) ? 'h3 : 'hF;

  // load: pick the right lane, then extend
  wire [XLEN-1:0] rsh = dmem_rdata >> {lane, 3'b000};
  reg  [XLEN-1:0] load_raw, load_val;
  always @* begin
    case (f3)
      3'b000:  begin load_raw = rsh[7:0];  load_val = $signed(rsh[7:0]);  end // LB
      3'b001:  begin load_raw = rsh[15:0]; load_val = $signed(rsh[15:0]); end // LH
      3'b010:  begin load_raw = rsh[31:0]; load_val = $signed(rsh[31:0]); end // LW
      3'b100:  begin load_raw = rsh[7:0];  load_val = rsh[7:0];           end // LBU
      3'b101:  begin load_raw = rsh[15:0]; load_val = rsh[15:0];          end // LHU
      default: begin load_raw = {XLEN{1'b0}}; load_val = {XLEN{1'b0}};    end
    endcase
  end

  // store: raw value and lane-shifted bus data
  wire [XLEN-1:0] st_data = (f3[1:0] == 2'b00) ? rs2_data[7:0]  :
                            (f3[1:0] == 2'b01) ? rs2_data[15:0] : rs2_data[31:0];

  wire active = rst_n & ~halted;
  assign dmem_we    = active & legal & is_store;
  assign dmem_wmask = acc_mask << lane;
  assign dmem_wdata = st_data << {lane, 3'b000};

  // ---------------- writeback ----------------
  always @* begin
    wb_val = alu_y;
    if      (is_lui)           wb_val = imm_u;
    else if (is_auipc)         wb_val = pc + imm_u;
    else if (is_jal | is_jalr) wb_val = pc + 4;
    else if (is_load)          wb_val = load_val;
  end
  wire writes_rd = is_lui | is_auipc | is_jal | is_jalr | is_load | is_opimm | is_op;
  assign wb_en = active & legal & writes_rd & (rd != 5'd0);

  // ---------------- next pc ----------------
  wire [XLEN-1:0] jalr_t = rs1_data + imm_i;
  reg  [XLEN-1:0] next_pc;
  always @* begin
    next_pc = pc + 4;
    if      (trap)               next_pc = pc;
    else if (is_jal)             next_pc = pc + imm_j;
    else if (is_jalr)            next_pc = {jalr_t[XLEN-1:1], 1'b0};
    else if (is_branch & taken)  next_pc = pc + imm_b;
  end

  // ---------------- state + RVFI ----------------
  always @(posedge clk) begin
    if (!rst_n) begin
      pc         <= RESET_PC;
      halted     <= 1'b0;
      order      <= 64'd0;
      rvfi_valid <= 1'b0;
      rvfi_halt  <= 1'b0;
    end else begin
      rvfi_valid <= ~halted;
      if (!halted) begin
        pc    <= next_pc;
        order <= order + 64'd1;
        if (is_halt | trap) halted <= 1'b1;

        rvfi_order     <= order;
        rvfi_insn      <= insn;
        rvfi_trap      <= trap;
        rvfi_halt      <= is_halt | trap;
        rvfi_pc_rdata  <= pc;
        rvfi_pc_wdata  <= next_pc;
        rvfi_rd_addr   <= wb_en ? rd : 5'd0;
        rvfi_rd_wdata  <= wb_en ? wb_val : {XLEN{1'b0}};
        rvfi_mem_addr  <= (legal & (is_load | is_store)) ? ea : {XLEN{1'b0}};
        rvfi_mem_rmask <= (legal & is_load)  ? acc_mask : {BYTES{1'b0}};
        rvfi_mem_wmask <= (legal & is_store) ? acc_mask : {BYTES{1'b0}};
        rvfi_mem_rdata <= (legal & is_load)  ? load_raw : {XLEN{1'b0}};
        rvfi_mem_wdata <= (legal & is_store) ? st_data  : {XLEN{1'b0}};
      end
    end
  end
endmodule
