`timescale 1ns/1ps
module tb_core;
  localparam XLEN = 32;
  localparam MEM_WORDS = 262144;  // 1 MiB

  reg clk = 1'b0;
  reg rst_n = 1'b0;
  always #5 clk = ~clk;

  reg [31:0] mem [0:MEM_WORDS-1];

  wire [XLEN-1:0]   imem_addr, dmem_addr, dmem_wdata, dmem_rdata;
  wire [31:0]       imem_rdata;
  wire              dmem_we;
  wire [XLEN/8-1:0] dmem_wmask;

  wire              rvfi_valid, rvfi_trap, rvfi_halt;
  wire [63:0]       rvfi_order;
  wire [31:0]       rvfi_insn;
  wire [XLEN-1:0]   rvfi_pc_rdata, rvfi_pc_wdata, rvfi_rd_wdata;
  wire [XLEN-1:0]   rvfi_mem_addr, rvfi_mem_rdata, rvfi_mem_wdata;
  wire [4:0]        rvfi_rd_addr;
  wire [XLEN/8-1:0] rvfi_mem_rmask, rvfi_mem_wmask;

  core #(.XLEN(XLEN)) dut (.*);

  // memory: async read of the aligned word, byte-strobe write
  assign imem_rdata = mem[imem_addr[19:2]];
  assign dmem_rdata = mem[dmem_addr[19:2]];

  always @(posedge clk) begin
    if (dmem_we) begin
      if (dmem_wmask[0]) mem[dmem_addr[19:2]][7:0]   <= dmem_wdata[7:0];
      if (dmem_wmask[1]) mem[dmem_addr[19:2]][15:8]  <= dmem_wdata[15:8];
      if (dmem_wmask[2]) mem[dmem_addr[19:2]][23:16] <= dmem_wdata[23:16];
      if (dmem_wmask[3]) mem[dmem_addr[19:2]][31:24] <= dmem_wdata[31:24];
    end
  end

  string  prog, tracefile;
  integer fd, i, max_cycles, cycles;

  initial begin
    for (i = 0; i < MEM_WORDS; i = i + 1) mem[i] = 32'h0;
    if (!$value$plusargs("prog=%s", prog)) begin
      $display("ERROR: need +prog=<file.hex>");
      $finish;
    end
    if (!$value$plusargs("trace=%s", tracefile)) tracefile = "trace_rtl.txt";
    if (!$value$plusargs("max=%d", max_cycles)) max_cycles = 100000;
    $readmemh(prog, mem);
    if ($test$plusargs("wave")) begin $dumpfile("wave.vcd"); $dumpvars(0, tb_core); end
    fd = $fopen(tracefile, "w");
    cycles = 0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
  end

  // print one trace line per retired instruction (same format as the ISS)
  always @(negedge clk) begin
    cycles = cycles + 1;
    if (rvfi_valid) begin
      $fwrite(fd, "%0d %08x %08x %02x %08x %08x %08x %0x %0x %08x %08x\n",
              rvfi_order, rvfi_pc_rdata, rvfi_insn, rvfi_rd_addr, rvfi_rd_wdata,
              rvfi_pc_wdata, rvfi_mem_addr, rvfi_mem_rmask, rvfi_mem_wmask,
              rvfi_mem_rdata, rvfi_mem_wdata);
      if (rvfi_halt) begin
        $fclose(fd);
        $display("cycles=%0d", cycles);
        $display("halted after %0d instructions%s", rvfi_order + 1, rvfi_trap ? " (TRAP)" : "");
        $display("x10=%08x", dut.u_rf.regs[10]);
        $finish;
      end
    end
    if (cycles >= max_cycles) begin
      $display("TIMEOUT");
      $fclose(fd);
      $finish;
    end
  end
endmodule
