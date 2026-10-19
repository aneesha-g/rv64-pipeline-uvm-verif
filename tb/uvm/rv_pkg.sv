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
  // Env + test
  // ------------------------------------------------------------------
  class rv_env extends uvm_env;
    `uvm_component_utils(rv_env)
    imem_agent    imem_agt;
    rvfi_monitor  rvfi_mon;
    rv_scoreboard sb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      imem_agt = imem_agent::type_id::create("imem_agt", this);
      rvfi_mon = rvfi_monitor::type_id::create("rvfi_mon", this);
      sb       = rv_scoreboard::type_id::create("sb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      rvfi_mon.ap.connect(sb.imp);
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
