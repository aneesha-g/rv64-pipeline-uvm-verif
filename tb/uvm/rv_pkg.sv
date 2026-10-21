`include "uvm_macros.svh"

package rv_pkg;
  import uvm_pkg::*;

`ifndef NO_DPI
  import "DPI-C" function void iss_load(input string path);
  import "DPI-C" function int iss_step(
    output longint unsigned order,    output longint unsigned pc,
    output int unsigned     insn,     output int unsigned     rd,
    output longint unsigned rd_wdata, output longint unsigned pc_wdata,
    output longint unsigned mem_addr, output int unsigned     rmask,
    output int unsigned     wmask,    output longint unsigned mem_rdata,
    output longint unsigned mem_wdata);
`endif

  // ------------------------------------------------------------------
  // Instruction-side memory image (1 MiB at 0x80000000), loaded from a .hex file
  // ------------------------------------------------------------------
  bit [31:0] mem_words [0:262143];

  function void mem_load_hex(string path);
    int fd;
    int n;
    bit [31:0] w;
    for (int i = 0; i < 262144; i++) mem_words[i] = 32'h0;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "mem_load_hex: cannot open %s", path);
    n = 0;
    while ($fscanf(fd, "%h", w) == 1) begin
      mem_words[n] = w;
      n++;
    end
    $fclose(fd);
    $display("mem_load_hex: %0d words from %s", n, path);
  endfunction

  function bit [31:0] mem_read(bit [31:0] addr);
    return mem_words[addr[19:2]];
  endfunction

  // ------------------------------------------------------------------
  // Items
  // ------------------------------------------------------------------
  // how many extra cycles the memory waits before answering one word
  class timing_item extends uvm_sequence_item;
    `uvm_object_utils(timing_item)
    rand int unsigned lat;
    constraint c_lat { lat <= 64; }
    function new(string name = "timing_item");
      super.new(name);
    endfunction
  endclass

  // one retired instruction (RVFI)
  class rvfi_item extends uvm_sequence_item;
    `uvm_object_utils(rvfi_item)
    bit [63:0] order, pc, pc_wdata, rd_wdata, mem_addr, mem_rdata, mem_wdata;
    bit [31:0] insn;
    bit [4:0]  rd;
    bit [7:0]  rmask, wmask;
    bit        trap, halt;
    function new(string name = "rvfi_item");
      super.new(name);
    endfunction
    function string convert2string();
      return $sformatf("#%0d pc=%h insn=%h rd=x%0d wdata=%h",
                       order, pc[31:0], insn, rd, rd_wdata[31:0]);
    endfunction
  endclass

  // ------------------------------------------------------------------
  // Sequence: endless stream of random memory latencies within [min_lat:max_lat]
  // ------------------------------------------------------------------
  class timing_seq extends uvm_sequence #(timing_item);
    `uvm_object_utils(timing_seq)
    int unsigned min_lat = 0;
    int unsigned max_lat = 6;
    function new(string name = "timing_seq");
      super.new(name);
    endfunction
    task body();
      forever begin
        req = timing_item::type_id::create("req");
        start_item(req);
        if (!req.randomize() with { lat >= min_lat; lat <= max_lat; }) begin
          `uvm_fatal("RAND", "timing_item randomize failed")
        end
        finish_item(req);
      end
    endtask
  endclass

  // ------------------------------------------------------------------
  // imem agent: reactive memory. Sees imem_req, waits the random latency, answers one word.
  // ------------------------------------------------------------------
  class imem_driver extends uvm_driver #(timing_item);
    `uvm_component_utils(imem_driver)
    virtual rv_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(virtual rv_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal("NOVIF", "virtual interface not set for imem_driver")
      end
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        @(posedge vif.clk);
        if (vif.rst_n === 1'b1 && vif.imem_req === 1'b1 && vif.imem_rvalid === 1'b0) begin
          seq_item_port.get_next_item(req);
          repeat (req.lat) @(posedge vif.clk);
          vif.imem_rdata  <= mem_read(vif.imem_addr);
          vif.imem_rvalid <= 1'b1;
          seq_item_port.item_done();
          @(posedge vif.clk);
          vif.imem_rvalid <= 1'b0;
        end
      end
    endtask
  endclass

  class imem_agent extends uvm_agent;
    `uvm_component_utils(imem_agent)
    uvm_sequencer #(timing_item) sqr;
    imem_driver                  drv;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sqr = uvm_sequencer #(timing_item)::type_id::create("sqr", this);
      drv = imem_driver::type_id::create("drv", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  // ------------------------------------------------------------------
  // RVFI monitor: one rvfi_item per retired instruction
  // ------------------------------------------------------------------
  class rvfi_monitor extends uvm_monitor;
    `uvm_component_utils(rvfi_monitor)
    virtual rv_if vif;
    uvm_analysis_port #(rvfi_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);
      if (!uvm_config_db #(virtual rv_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal("NOVIF", "virtual interface not set for rvfi_monitor")
      end
    endfunction

    task run_phase(uvm_phase phase);
      rvfi_item it;
      forever begin
        @(posedge vif.clk);
        if (vif.rst_n === 1'b1 && vif.rvfi_valid === 1'b1) begin
          it = rvfi_item::type_id::create("it");
          it.order     = vif.rvfi_order;
          it.pc        = vif.rvfi_pc_rdata;
          it.insn      = vif.rvfi_insn;
          it.rd        = vif.rvfi_rd_addr;
          it.rd_wdata  = vif.rvfi_rd_wdata;
          it.pc_wdata  = vif.rvfi_pc_wdata;
          it.mem_addr  = vif.rvfi_mem_addr;
          it.rmask     = vif.rvfi_mem_rmask;
          it.wmask     = vif.rvfi_mem_wmask;
          it.mem_rdata = vif.rvfi_mem_rdata;
          it.mem_wdata = vif.rvfi_mem_wdata;
          it.trap      = vif.rvfi_trap;
          it.halt      = vif.rvfi_halt;
          ap.write(it);
        end
      end
    endtask
  endclass

  // ------------------------------------------------------------------
  // Scoreboard: step the C++ ISS (DPI-C) once per retire and compare every field.
  // With +define NO_DPI it only counts retires (used to bring the env up first).
  // ------------------------------------------------------------------
  class rv_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(rv_scoreboard)
    uvm_analysis_imp #(rvfi_item, rv_scoreboard) imp;
    bit          halted;
    bit          failed;
    int unsigned n_checked;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      string prog;
      super.build_phase(phase);
      imp = new("imp", this);
`ifndef NO_DPI
      if (!$value$plusargs("prog=%s", prog)) begin
        `uvm_fatal("NOPROG", "pass +prog=<dir/name> without extension")
      end
      iss_load({prog, ".bin"});
`endif
    endfunction

    function string row(string name, longint unsigned a, longint unsigned b);
      string tag;
      if (a != b) tag = "   <-- DIFF";
      else        tag = "";
      return $sformatf("  %-9s ISS=%016h  RTL=%016h%s\n", name, a, b, tag);
    endfunction

`ifndef NO_DPI
    function void write(rvfi_item t);
      longint unsigned e_order, e_pc, e_rdw, e_pcw, e_ma, e_mrd, e_mwd;
      int unsigned     e_insn, e_rd, e_rm, e_wm;
      int              ok;
      bit              bad;
      string           msg;
      if (t.halt) halted = 1;
      if (failed) return;
      ok = iss_step(e_order, e_pc, e_insn, e_rd, e_rdw, e_pcw, e_ma, e_rm, e_wm, e_mrd, e_mwd);
      if (!ok) begin
        failed = 1;
        `uvm_error("LOCKSTEP", $sformatf("RTL retired #%0d but the ISS had already halted", t.order))
        return;
      end
      bad = (e_order != t.order)     | (e_pc  != t.pc)        | (e_insn != t.insn)       |
            (e_rd    != t.rd)        | (e_rdw != t.rd_wdata)  | (e_pcw  != t.pc_wdata)   |
            (e_ma    != t.mem_addr)  | (e_rm  != t.rmask)     | (e_wm   != t.wmask)      |
            (e_mrd   != t.mem_rdata) | (e_mwd != t.mem_wdata);
      if (bad) begin
        failed = 1;
        msg = $sformatf("lockstep mismatch at retire #%0d (pc=%h insn=%h)\n", t.order, t.pc[31:0], t.insn);
        msg = {msg, row("order",     e_order,   t.order)};
        msg = {msg, row("pc",        e_pc,      t.pc)};
        msg = {msg, row("insn",      e_insn,    t.insn)};
        msg = {msg, row("rd",        e_rd,      t.rd)};
        msg = {msg, row("rd_wdata",  e_rdw,     t.rd_wdata)};
        msg = {msg, row("pc_wdata",  e_pcw,     t.pc_wdata)};
        msg = {msg, row("mem_addr",  e_ma,      t.mem_addr)};
        msg = {msg, row("mem_rmask", e_rm,      t.rmask)};
        msg = {msg, row("mem_wmask", e_wm,      t.wmask)};
        msg = {msg, row("mem_rdata", e_mrd,     t.mem_rdata)};
        msg = {msg, row("mem_wdata", e_mwd,     t.mem_wdata)};
        `uvm_error("LOCKSTEP", msg)
        return;
      end
      n_checked++;
    endfunction
`else
    function void write(rvfi_item t);
      if (t.halt) halted = 1;
      if (n_checked < 40) begin
        `uvm_info("RETIRE", t.convert2string(), UVM_MEDIUM)
      end
      n_checked++;
    endfunction
`endif

    function void report_phase(uvm_phase phase);
      if (failed) begin
        `uvm_error("SB", "lockstep FAILED")
      end else if (!halted) begin
        `uvm_error("SB", "program never halted (timeout?)")
      end else begin
        `uvm_info("SB", $sformatf("TEST PASSED: %0d instructions checked", n_checked), UVM_NONE)
      end
    endfunction
  endclass

  // ------------------------------------------------------------------
  // Functional coverage collector
  //   cg_retire: architectural scenarios, sampled once per retired instruction (RVFI monitor)
  //   cg_pipe  : micro-architectural events, sampled every clock from the white-box probes
  // ------------------------------------------------------------------
  typedef enum int {
    I_LUI, I_AUIPC, I_JAL, I_JALR,
    I_BEQ, I_BNE, I_BLT, I_BGE, I_BLTU, I_BGEU,
    I_LB, I_LH, I_LW, I_LBU, I_LHU,
    I_SB, I_SH, I_SW,
    I_ADDI, I_SLTI, I_SLTIU, I_XORI, I_ORI, I_ANDI, I_SLLI, I_SRLI, I_SRAI,
    I_ADD, I_SUB, I_SLL, I_SLT, I_SLTU, I_XOR, I_SRL, I_SRA, I_OR, I_AND,
    I_FENCE, I_ECALL, I_OTHER
  } insn_e;

  function automatic insn_e decode_insn(bit [31:0] i);
    bit [2:0] f3;
    bit       alt;
    f3  = i[14:12];
    alt = i[30];
    case (i[6:0])
      7'h37: return I_LUI;
      7'h17: return I_AUIPC;
      7'h6f: return I_JAL;
      7'h67: return (f3 == 3'b000) ? I_JALR : I_OTHER;
      7'h63: case (f3)
               3'b000: return I_BEQ;
               3'b001: return I_BNE;
               3'b100: return I_BLT;
               3'b101: return I_BGE;
               3'b110: return I_BLTU;
               3'b111: return I_BGEU;
               default: return I_OTHER;
             endcase
      7'h03: case (f3)
               3'b000: return I_LB;
               3'b001: return I_LH;
               3'b010: return I_LW;
               3'b100: return I_LBU;
               3'b101: return I_LHU;
               default: return I_OTHER;
             endcase
      7'h23: case (f3)
               3'b000: return I_SB;
               3'b001: return I_SH;
               3'b010: return I_SW;
               default: return I_OTHER;
             endcase
      7'h13: case (f3)
               3'b000: return I_ADDI;
               3'b010: return I_SLTI;
               3'b011: return I_SLTIU;
               3'b100: return I_XORI;
               3'b110: return I_ORI;
               3'b111: return I_ANDI;
               3'b001: return I_SLLI;
               default: return alt ? I_SRAI : I_SRLI;
             endcase
      7'h33: case (f3)
               3'b000: return alt ? I_SUB : I_ADD;
               3'b001: return I_SLL;
               3'b010: return I_SLT;
               3'b011: return I_SLTU;
               3'b100: return I_XOR;
               3'b101: return alt ? I_SRA : I_SRL;
               3'b110: return I_OR;
               default: return I_AND;
             endcase
      7'h0f: return I_FENCE;
      7'h73: return (i == 32'h00000073) ? I_ECALL : I_OTHER;
      default: return I_OTHER;
    endcase
  endfunction

  class rv_coverage extends uvm_subscriber #(rvfi_item);
    `uvm_component_utils(rv_coverage)
    virtual rv_if vif;

    // ---- values sampled by cg_retire ----
    insn_e m_insn;
    bit    m_use1, m_use2;        // instruction reads rs1 / rs2 (and it is not x0)
    int    m_raw1, m_raw2;        // 0 no producer in the last 3 retires; 1..3 ALU producer at distance d;
                                  // 4..6 load producer at distance d (4 = load-use)
    bit    m_is_branch, m_taken, m_back;
    int    m_br;                  // 0 beq .. 5 bgeu
    bit    m_is_mem;
    int    m_mem;                 // access kind * 4 + byte lane
    bit    m_is_subld;
    int    m_ld_sign;             // sub-word load: kind * 2 + top bit of the loaded byte/half
    bit    m_is_load;
    int    m_st_ld;               // load reads the word a store wrote 1..3 retires earlier (0 = none)
    bit    m_wr_x0, m_rd_x0;
    bit    m_is_jump;
    int    m_jump;                // 0 jal x0, 1 jal link, 2 jalr x0, 3 jalr link

    // ---- history of the last 3 retired instructions (index 0 = most recent) ----
    bit [4:0]  h_rd   [3];        // register written (0 = none)
    bit        h_load [3];
    bit        h_st   [3];
    bit [29:0] h_st_w [3];        // word address of a store

    // ---- values sampled by cg_pipe ----
    bit q_use_a, q_use_b, q_wt, q_stall, q_ctrl;
    int q_fwd_a, q_fwd_b;         // 0 regfile, 1 EX/MEM, 2 MEM/WB, 3 both match (youngest must win)
    int q_ctrl_case;              // kind * 8 + outcome
    int q_events;                 // {icache fill, redirect, load-use stall}

    covergroup cg_retire;
      option.per_instance = 1;
      // one named bin per instruction (xsim does not give an enum one automatic bin per value)
      cp_insn : coverpoint m_insn {
        bins LUI    = {I_LUI};
        bins AUIPC  = {I_AUIPC};
        bins JAL    = {I_JAL};
        bins JALR   = {I_JALR};
        bins BEQ    = {I_BEQ};
        bins BNE    = {I_BNE};
        bins BLT    = {I_BLT};
        bins BGE    = {I_BGE};
        bins BLTU   = {I_BLTU};
        bins BGEU   = {I_BGEU};
        bins LB     = {I_LB};
        bins LH     = {I_LH};
        bins LW     = {I_LW};
        bins LBU    = {I_LBU};
        bins LHU    = {I_LHU};
        bins SB     = {I_SB};
        bins SH     = {I_SH};
        bins SW     = {I_SW};
        bins ADDI   = {I_ADDI};
        bins SLTI   = {I_SLTI};
        bins SLTIU  = {I_SLTIU};
        bins XORI   = {I_XORI};
        bins ORI    = {I_ORI};
        bins ANDI   = {I_ANDI};
        bins SLLI   = {I_SLLI};
        bins SRLI   = {I_SRLI};
        bins SRAI   = {I_SRAI};
        bins ADD    = {I_ADD};
        bins SUB    = {I_SUB};
        bins SLL    = {I_SLL};
        bins SLT    = {I_SLT};
        bins SLTU   = {I_SLTU};
        bins XOR    = {I_XOR};
        bins SRL    = {I_SRL};
        bins SRA    = {I_SRA};
        bins OR     = {I_OR};
        bins AND    = {I_AND};
        bins FENCE  = {I_FENCE};
        bins ECALL  = {I_ECALL};
      }
      cp_raw_rs1 : coverpoint m_raw1 iff (m_use1) {
        bins no_dep   = {0};
        bins alu_d1   = {1};
        bins alu_d2   = {2};
        bins alu_d3   = {3};
        bins load_use = {4};
        bins load_d2  = {5};
        bins load_d3  = {6};
      }
      cp_raw_rs2 : coverpoint m_raw2 iff (m_use2) {
        bins no_dep   = {0};
        bins alu_d1   = {1};
        bins alu_d2   = {2};
        bins alu_d3   = {3};
        bins load_use = {4};
        bins load_d2  = {5};
        bins load_d3  = {6};
      }
      cp_br_type : coverpoint m_br iff (m_is_branch) {
        bins beq  = {0};
        bins bne  = {1};
        bins blt  = {2};
        bins bge  = {3};
        bins bltu = {4};
        bins bgeu = {5};
      }
      cp_br_taken : coverpoint m_taken iff (m_is_branch) {
        bins not_taken = {0};
        bins taken     = {1};
      }
      cp_br_dir : coverpoint m_back iff (m_is_branch) {
        bins forward  = {0};
        bins backward = {1};
      }
      x_branch : cross cp_br_type, cp_br_taken, cp_br_dir;
      cp_mem_lane : coverpoint m_mem iff (m_is_mem) {
        bins lb[]  = {0, 1, 2, 3};
        bins lbu[] = {4, 5, 6, 7};
        bins sb[]  = {8, 9, 10, 11};
        bins lh[]  = {12, 14};
        bins lhu[] = {16, 18};
        bins sh[]  = {20, 22};
        bins lw    = {24};
        bins sw    = {28};
      }
      cp_load_sign : coverpoint m_ld_sign iff (m_is_subld) {
        bins lb_pos  = {0};
        bins lb_neg  = {1};
        bins lbu_lo  = {2};
        bins lbu_hi  = {3};
        bins lh_pos  = {4};
        bins lh_neg  = {5};
        bins lhu_lo  = {6};
        bins lhu_hi  = {7};
      }
      cp_store_load : coverpoint m_st_ld iff (m_is_load) {
        bins no_recent_store = {0};
        bins store_d1        = {1};
        bins store_d2        = {2};
        bins store_d3        = {3};
      }
      cp_write_x0 : coverpoint m_wr_x0 {
        bins write_discarded = {1};
      }
      cp_read_x0 : coverpoint m_rd_x0 {
        bins x0_as_source = {1};
      }
      cp_jump : coverpoint m_jump iff (m_is_jump) {
        bins jal_plain  = {0};
        bins jal_link   = {1};
        bins jalr_plain = {2};
        bins jalr_link  = {3};
      }
    endgroup

    covergroup cg_pipe;
      option.per_instance = 1;
      cp_fwd_a : coverpoint q_fwd_a iff (q_use_a) {
        bins from_regfile = {0};
        bins ex_mem       = {1};
        bins mem_wb       = {2};
        bins both_match   = {3};
      }
      cp_fwd_b : coverpoint q_fwd_b iff (q_use_b) {
        bins from_regfile = {0};
        bins ex_mem       = {1};
        bins mem_wb       = {2};
        bins both_match   = {3};
      }
      cp_write_through : coverpoint q_wt {
        bins wb_to_id = {1};
      }
      cp_load_use_stall : coverpoint q_stall {
        bins stall = {1};
      }
      // outcome: 0 correct not-taken, 1 correct taken, 2 missed taken, 3 false taken, 4 wrong target
      cp_predict : coverpoint q_ctrl_case iff (q_ctrl) {
        bins br_correct_nt  = {0};
        bins br_correct_t   = {1};
        bins br_missed      = {2};
        bins br_false_taken = {3};
        bins jal_correct    = {9};
        bins jal_missed     = {10};
        bins jalr_correct   = {17};
        bins jalr_missed    = {18};
        bins jalr_wrong_tgt = {20};
      }
      // events in the same cycle: {icache fill, redirect, load-use stall}
      cp_events : coverpoint q_events {
        bins stall_only           = {1};
        bins redirect_only        = {2};
        bins fill_only            = {4};
        bins stall_during_fill    = {5};
        bins redirect_during_fill = {6};
      }
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg_retire = new();
      cg_pipe   = new();
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(virtual rv_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal("NOVIF", "virtual interface not set for rv_coverage")
      end
      for (int d = 0; d < 3; d++) begin
        h_rd[d] = 5'd0; h_load[d] = 1'b0; h_st[d] = 1'b0; h_st_w[d] = 30'd0;
      end
    endfunction

    // nearest producer of register r among the last 3 retired instructions
    function int raw_kind(bit [4:0] r);
      for (int d = 0; d < 3; d++) begin
        if (h_rd[d] == r) return (h_load[d] ? 4 : 1) + d;
      end
      return 0;
    endfunction

    // called by the RVFI monitor for every retired instruction
    function void write(rvfi_item t);
      bit [4:0] rs1, rs2, rd;
      bit       writes, uses1, uses2, is_store;
      insn_e    k;
      if (t.trap) return;
      k   = decode_insn(t.insn);
      if (k == I_OTHER) return;
      rs1 = t.insn[19:15];
      rs2 = t.insn[24:20];
      rd  = t.insn[11:7];

      writes   = (k inside {I_LUI, I_AUIPC, I_JAL, I_JALR, [I_LB:I_LHU], [I_ADDI:I_AND]});
      uses1    = (k inside {I_JALR, [I_BEQ:I_BGEU], [I_LB:I_SW], [I_ADDI:I_AND]});
      uses2    = (k inside {[I_BEQ:I_BGEU], [I_SB:I_SW], [I_ADD:I_AND]});
      is_store = (k inside {[I_SB:I_SW]});

      m_insn = k;
      m_use1 = uses1 && (rs1 != 5'd0);
      m_use2 = uses2 && (rs2 != 5'd0);
      m_raw1 = m_use1 ? raw_kind(rs1) : 0;
      m_raw2 = m_use2 ? raw_kind(rs2) : 0;

      m_is_branch = (k inside {[I_BEQ:I_BGEU]});
      m_br        = m_is_branch ? (k - I_BEQ) : 0;
      m_taken     = (t.pc_wdata[31:0] != t.pc[31:0] + 32'd4);
      m_back      = t.insn[31];

      m_is_mem = (k inside {[I_LB:I_SW]});
      case (k)
        I_LB:    m_mem = 0  + t.mem_addr[1:0];
        I_LBU:   m_mem = 4  + t.mem_addr[1:0];
        I_SB:    m_mem = 8  + t.mem_addr[1:0];
        I_LH:    m_mem = 12 + t.mem_addr[1:0];
        I_LHU:   m_mem = 16 + t.mem_addr[1:0];
        I_SH:    m_mem = 20 + t.mem_addr[1:0];
        I_LW:    m_mem = 24 + t.mem_addr[1:0];
        I_SW:    m_mem = 28 + t.mem_addr[1:0];
        default: m_mem = 0;
      endcase

      m_is_subld = (k inside {I_LB, I_LBU, I_LH, I_LHU});
      case (k)
        I_LB:    m_ld_sign = 0 + t.mem_rdata[7];
        I_LBU:   m_ld_sign = 2 + t.mem_rdata[7];
        I_LH:    m_ld_sign = 4 + t.mem_rdata[15];
        I_LHU:   m_ld_sign = 6 + t.mem_rdata[15];
        default: m_ld_sign = 0;
      endcase

      m_is_load = (k inside {[I_LB:I_LHU]});
      m_st_ld   = 0;
      if (m_is_load) begin
        for (int d = 2; d >= 0; d--) begin
          if (h_st[d] && h_st_w[d] == t.mem_addr[31:2]) m_st_ld = d + 1;
        end
      end

      m_wr_x0 = writes && !(k inside {I_JAL, I_JALR}) && (rd == 5'd0);
      m_rd_x0 = (uses1 && rs1 == 5'd0) || (uses2 && rs2 == 5'd0);

      m_is_jump = (k inside {I_JAL, I_JALR});
      m_jump    = ((k == I_JALR) ? 2 : 0) + ((rd != 5'd0) ? 1 : 0);

      cg_retire.sample();

      // shift the history
      for (int d = 2; d > 0; d--) begin
        h_rd[d]   = h_rd[d-1];
        h_load[d] = h_load[d-1];
        h_st[d]   = h_st[d-1];
        h_st_w[d] = h_st_w[d-1];
      end
      h_rd[0]   = writes ? rd : 5'd0;
      h_load[0] = m_is_load;
      h_st[0]   = is_store;
      h_st_w[0] = t.mem_addr[31:2];
    endfunction

    task run_phase(uvm_phase phase);
      int outcome;
      forever begin
        @(posedge vif.clk);
        if (vif.rst_n === 1'b1) begin
          q_use_a = (vif.p_ex_use_a === 1'b1);
          q_use_b = (vif.p_ex_use_b === 1'b1);
          q_fwd_a = (vif.p_fwd_a_exmem ? 1 : 0) + (vif.p_fwd_a_memwb ? 2 : 0);
          q_fwd_b = (vif.p_fwd_b_exmem ? 1 : 0) + (vif.p_fwd_b_memwb ? 2 : 0);
          q_wt    = (vif.p_wt === 1'b1);
          q_stall = (vif.p_stall === 1'b1);
          q_ctrl  = (vif.p_ctrl === 1'b1);
          if (!vif.p_pred_taken && !vif.p_act_taken)     outcome = 0;
          else if (!vif.p_pred_taken && vif.p_act_taken) outcome = 2;
          else if (vif.p_pred_taken && !vif.p_act_taken) outcome = 3;
          else if (vif.p_redirect)                       outcome = 4;
          else                                           outcome = 1;
          q_ctrl_case = vif.p_ctrl_kind * 8 + outcome;
          q_events    = (vif.p_ic_fill ? 4 : 0) + (vif.p_redirect ? 2 : 0) + (vif.p_stall ? 1 : 0);
          cg_pipe.sample();
        end
      end
    endtask

    function void report_phase(uvm_phase phase);
      `uvm_info("COV", $sformatf("FUNC COVERAGE (this test): instructions/scenarios %0.1f%%, pipeline events %0.1f%%",
                                 cg_retire.get_inst_coverage(), cg_pipe.get_inst_coverage()), UVM_NONE)
    endfunction
  endclass

  // ------------------------------------------------------------------
  // Env + test
  // ------------------------------------------------------------------
  class rv_env extends uvm_env;
    `uvm_component_utils(rv_env)
    imem_agent    imem_agt;
    rvfi_monitor  rvfi_mon;
    rv_scoreboard sb;
    rv_coverage   cov;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      imem_agt = imem_agent::type_id::create("imem_agt", this);
      rvfi_mon = rvfi_monitor::type_id::create("rvfi_mon", this);
      sb       = rv_scoreboard::type_id::create("sb", this);
      cov      = rv_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      rvfi_mon.ap.connect(sb.imp);
      rvfi_mon.ap.connect(cov.analysis_export);
    endfunction
  endclass

  class rv_base_test extends uvm_test;
    `uvm_component_utils(rv_base_test)
    rv_env        env;
    virtual rv_if vif;
    string        prog;
    string        timing;
    int unsigned  max_cycles;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = rv_env::type_id::create("env", this);
      if (!uvm_config_db #(virtual rv_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal("NOVIF", "virtual interface not set for the test")
      end
      if (!$value$plusargs("prog=%s", prog)) begin
        `uvm_fatal("NOPROG", "pass +prog=<dir/name> without extension")
      end
      if (!$value$plusargs("timing=%s", timing)) timing = "rand";
      if (!$value$plusargs("max_cycles=%d", max_cycles)) max_cycles = 200000;
      mem_load_hex({prog, ".hex"});
    endfunction

    task run_phase(uvm_phase phase);
      timing_seq   seq;
      int unsigned cyc;
      phase.raise_objection(this, "running program");
      seq = timing_seq::type_id::create("seq");
      case (timing)
        "fast":  begin seq.min_lat = 0; seq.max_lat = 0;  end
        "slow":  begin seq.min_lat = 8; seq.max_lat = 20; end
        default: begin seq.min_lat = 0; seq.max_lat = 6;  end
      endcase
      `uvm_info("TEST", $sformatf("prog=%s timing=%s latency=[%0d:%0d]",
                                  prog, timing, seq.min_lat, seq.max_lat), UVM_NONE)
      fork
        seq.start(env.imem_agt.sqr);
      join_none
      cyc = 0;
      while (!env.sb.halted && cyc < max_cycles) begin
        @(posedge vif.clk);
        cyc++;
      end
      if (!env.sb.halted) begin
        `uvm_error("TIMEOUT", $sformatf("program did not halt within %0d cycles", max_cycles))
      end
      repeat (5) @(posedge vif.clk);
      phase.drop_objection(this, "done");
    endtask
  endclass

endpackage
