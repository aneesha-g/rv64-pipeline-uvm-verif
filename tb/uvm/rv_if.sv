// Signals between the core (DUT) and the UVM environment. XLEN = 32.
interface rv_if (input bit clk);
  logic        rst_n;

  // instruction memory refill port (driven by the imem agent)
  logic        imem_req;
  logic [31:0] imem_addr;
  logic        imem_rvalid = 1'b0;
  logic [31:0] imem_rdata  = 32'h0;

  // data memory (fixed-latency model in the top module)
  logic [31:0] dmem_addr;
  logic        dmem_we;
  logic [3:0]  dmem_wmask;
  logic [31:0] dmem_wdata;
  logic [31:0] dmem_rdata;

  // RVFI retire port (observed by the monitor)
  logic        rvfi_valid;
  logic [63:0] rvfi_order;
  logic [31:0] rvfi_insn;
  logic        rvfi_trap;
  logic        rvfi_halt;
  logic [31:0] rvfi_pc_rdata;
  logic [31:0] rvfi_pc_wdata;
  logic [4:0]  rvfi_rd_addr;
  logic [31:0] rvfi_rd_wdata;
  logic [31:0] rvfi_mem_addr;
  logic [3:0]  rvfi_mem_rmask;
  logic [3:0]  rvfi_mem_wmask;
  logic [31:0] rvfi_mem_rdata;
  logic [31:0] rvfi_mem_wdata;
endinterface
