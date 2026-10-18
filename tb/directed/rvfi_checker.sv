// Live lockstep checker: one ISS step per RTL retire, compare every field.
module rvfi_checker #(parameter XLEN = 32)(
  input                  clk,
  input                  rst_n,
  input                  rvfi_valid,
  input  [63:0]          rvfi_order,
  input  [31:0]          rvfi_insn,
  input                  rvfi_trap,
  input                  rvfi_halt,
  input  [XLEN-1:0]      rvfi_pc_rdata,
  input  [XLEN-1:0]      rvfi_pc_wdata,
  input  [4:0]           rvfi_rd_addr,
  input  [XLEN-1:0]      rvfi_rd_wdata,
  input  [XLEN-1:0]      rvfi_mem_addr,
  input  [XLEN/8-1:0]    rvfi_mem_rmask,
  input  [XLEN/8-1:0]    rvfi_mem_wmask,
  input  [XLEN-1:0]      rvfi_mem_rdata,
  input  [XLEN-1:0]      rvfi_mem_wdata
);
  import "DPI-C" function void iss_load(input string path);
  import "DPI-C" function int  iss_step(
    output longint unsigned order, output longint unsigned pc, output int unsigned insn,
    output int unsigned rd, output longint unsigned rd_wdata, output longint unsigned pc_wdata,
    output longint unsigned mem_addr, output int unsigned rmask, output int unsigned wmask,
    output longint unsigned mem_rdata, output longint unsigned mem_wdata);

  string           bin;
  bit              enabled;
  int              r;
  bit              bad;
  longint unsigned n_checked = 0;

  longint unsigned e_order, e_pc, e_rdw, e_pcw, e_ma, e_mrd, e_mwd;
  int unsigned     e_insn, e_rd, e_rm, e_wm;

  initial begin
    enabled = $value$plusargs("bin=%s", bin);
    if (enabled) iss_load(bin);
  end

  function automatic void show(input string name, input longint unsigned a, input longint unsigned b);
    if (a != b) $display("  %-9s ISS=%016h  RTL=%016h   <-- DIFF", name, a, b);
    else        $display("  %-9s ISS=%016h  RTL=%016h", name, a, b);
  endfunction

  always @(negedge clk) begin
    if (enabled && rst_n && rvfi_valid) begin
      r = iss_step(e_order, e_pc, e_insn, e_rd, e_rdw, e_pcw, e_ma, e_rm, e_wm, e_mrd, e_mwd);
      if (r == 0) begin
        $display("LOCKSTEP MISMATCH: RTL retired #%0d but the ISS had already halted", rvfi_order);
        $fatal(1, "lockstep");
      end
      bad = (e_order != rvfi_order)          | (e_pc  != 64'(rvfi_pc_rdata))  |
            (e_insn  != rvfi_insn)           | (e_rd  != 32'(rvfi_rd_addr))   |
            (e_rdw   != 64'(rvfi_rd_wdata))  | (e_pcw != 64'(rvfi_pc_wdata))  |
            (e_ma    != 64'(rvfi_mem_addr))  | (e_rm  != 32'(rvfi_mem_rmask)) |
            (e_wm    != 32'(rvfi_mem_wmask)) | (e_mrd != 64'(rvfi_mem_rdata))  |
            (e_mwd   != 64'(rvfi_mem_wdata));
      if (bad) begin
        $display("LOCKSTEP MISMATCH at retire #%0d (pc=%h insn=%h)", rvfi_order, rvfi_pc_rdata, rvfi_insn);
        show("order",     e_order, rvfi_order);
        show("pc",        e_pc,    64'(rvfi_pc_rdata));
        show("insn",      64'(e_insn), 64'(rvfi_insn));
        show("rd",        64'(e_rd),   64'(rvfi_rd_addr));
        show("rd_wdata",  e_rdw,   64'(rvfi_rd_wdata));
        show("pc_wdata",  e_pcw,   64'(rvfi_pc_wdata));
        show("mem_addr",  e_ma,    64'(rvfi_mem_addr));
        show("mem_rmask", 64'(e_rm), 64'(rvfi_mem_rmask));
        show("mem_wmask", 64'(e_wm), 64'(rvfi_mem_wmask));
        show("mem_rdata", e_mrd,   64'(rvfi_mem_rdata));
        show("mem_wdata", e_mwd,   64'(rvfi_mem_wdata));
        $fatal(1, "lockstep");
      end
      n_checked = n_checked + 1;
    end
  end

  final if (enabled)
    $display("lockstep: %0d instructions checked against the ISS, 0 mismatches", n_checked);
endmodule
