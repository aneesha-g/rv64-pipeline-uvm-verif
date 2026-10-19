`timescale 1ns/1ps
`include "uvm_macros.svh"

module tb_uvm_top;
  import uvm_pkg::*;
  import rv_pkg::*;

  bit clk = 1'b0;
  always #5 clk = ~clk;

  rv_if rif (clk);

  core #(.XLEN(32), .BP_EN(1)) dut (
    .clk(clk), .rst_n(rif.rst_n),
    .imem_req(rif.imem_req), .imem_addr(rif.imem_addr),
    .imem_rvalid(rif.imem_rvalid), .imem_rdata(rif.imem_rdata),
    .dmem_addr(rif.dmem_addr), .dmem_we(rif.dmem_we), .dmem_wmask(rif.dmem_wmask),
    .dmem_wdata(rif.dmem_wdata), .dmem_rdata(rif.dmem_rdata),
    .rvfi_valid(rif.rvfi_valid), .rvfi_order(rif.rvfi_order), .rvfi_insn(rif.rvfi_insn),
    .rvfi_trap(rif.rvfi_trap), .rvfi_halt(rif.rvfi_halt),
    .rvfi_pc_rdata(rif.rvfi_pc_rdata), .rvfi_pc_wdata(rif.rvfi_pc_wdata),
    .rvfi_rd_addr(rif.rvfi_rd_addr), .rvfi_rd_wdata(rif.rvfi_rd_wdata),
    .rvfi_mem_addr(rif.rvfi_mem_addr), .rvfi_mem_rmask(rif.rvfi_mem_rmask),
    .rvfi_mem_wmask(rif.rvfi_mem_wmask), .rvfi_mem_rdata(rif.rvfi_mem_rdata),
    .rvfi_mem_wdata(rif.rvfi_mem_wdata)
  );

  // ----- data memory: fixed latency (the core has no dmem handshake) -----
  reg [31:0] dmem [0:262143];
  string     prog_name;
  string     hexfile;
  integer    k;

  initial begin
    for (k = 0; k < 262144; k = k + 1) dmem[k] = 32'h0;
    if ($value$plusargs("prog=%s", prog_name)) begin
      hexfile = {prog_name, ".hex"};
      $readmemh(hexfile, dmem);
    end
  end

  assign rif.dmem_rdata = dmem[rif.dmem_addr[19:2]];

  always @(posedge clk) begin
    if (rif.dmem_we) begin
      if (rif.dmem_wmask[0]) dmem[rif.dmem_addr[19:2]][7:0]   <= rif.dmem_wdata[7:0];
      if (rif.dmem_wmask[1]) dmem[rif.dmem_addr[19:2]][15:8]  <= rif.dmem_wdata[15:8];
      if (rif.dmem_wmask[2]) dmem[rif.dmem_addr[19:2]][23:16] <= rif.dmem_wdata[23:16];
      if (rif.dmem_wmask[3]) dmem[rif.dmem_addr[19:2]][31:24] <= rif.dmem_wdata[31:24];
    end
  end

  // ----- reset -----
  initial begin
    rif.rst_n = 1'b0;
    repeat (4) @(posedge clk);
    rif.rst_n <= 1'b1;
  end

  // ----- start UVM -----
  initial begin
    uvm_config_db #(virtual rv_if)::set(null, "*", "vif", rif);
    run_test("rv_base_test");
  end
endmodule
EOF;6;13
cat > tb/uvm/tb_uvm_top.sv << 'EOF'
`timescale 1ns/1ps
`include "uvm_macros.svh"

module tb_uvm_top;
  import uvm_pkg::*;
  import rv_pkg::*;

  bit clk = 1'b0;
  always #5 clk = ~clk;

  rv_if rif (clk);

  core #(.XLEN(32), .BP_EN(1)) dut (
    .clk(clk), .rst_n(rif.rst_n),
    .imem_req(rif.imem_req), .imem_addr(rif.imem_addr),
    .imem_rvalid(rif.imem_rvalid), .imem_rdata(rif.imem_rdata),
    .dmem_addr(rif.dmem_addr), .dmem_we(rif.dmem_we), .dmem_wmask(rif.dmem_wmask),
    .dmem_wdata(rif.dmem_wdata), .dmem_rdata(rif.dmem_rdata),
    .rvfi_valid(rif.rvfi_valid), .rvfi_order(rif.rvfi_order), .rvfi_insn(rif.rvfi_insn),
    .rvfi_trap(rif.rvfi_trap), .rvfi_halt(rif.rvfi_halt),
    .rvfi_pc_rdata(rif.rvfi_pc_rdata), .rvfi_pc_wdata(rif.rvfi_pc_wdata),
    .rvfi_rd_addr(rif.rvfi_rd_addr), .rvfi_rd_wdata(rif.rvfi_rd_wdata),
    .rvfi_mem_addr(rif.rvfi_mem_addr), .rvfi_mem_rmask(rif.rvfi_mem_rmask),
    .rvfi_mem_wmask(rif.rvfi_mem_wmask), .rvfi_mem_rdata(rif.rvfi_mem_rdata),
    .rvfi_mem_wdata(rif.rvfi_mem_wdata)
  );

  // ----- data memory: fixed latency (the core has no dmem handshake) -----
  reg [31:0] dmem [0:262143];
  string     prog_name;
  string     hexfile;
  integer    k;

  initial begin
    for (k = 0; k < 262144; k = k + 1) dmem[k] = 32'h0;
    if ($value$plusargs("prog=%s", prog_name)) begin
      hexfile = {prog_name, ".hex"};
      $readmemh(hexfile, dmem);
    end
  end

  assign rif.dmem_rdata = dmem[rif.dmem_addr[19:2]];

  always @(posedge clk) begin
    if (rif.dmem_we) begin
      if (rif.dmem_wmask[0]) dmem[rif.dmem_addr[19:2]][7:0]   <= rif.dmem_wdata[7:0];
      if (rif.dmem_wmask[1]) dmem[rif.dmem_addr[19:2]][15:8]  <= rif.dmem_wdata[15:8];
      if (rif.dmem_wmask[2]) dmem[rif.dmem_addr[19:2]][23:16] <= rif.dmem_wdata[23:16];
      if (rif.dmem_wmask[3]) dmem[rif.dmem_addr[19:2]][31:24] <= rif.dmem_wdata[31:24];
    end
  end

  // ----- reset -----
  initial begin
    rif.rst_n = 1'b0;
    repeat (4) @(posedge clk);
    rif.rst_n <= 1'b1;
  end

  // ----- start UVM -----
  initial begin
    uvm_config_db #(virtual rv_if)::set(null, "*", "vif", rif);
    run_test("rv_base_test");
  end
endmodule
