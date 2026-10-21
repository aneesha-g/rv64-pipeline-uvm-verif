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

  // white-box probes for functional coverage: read-only taps into the core,
  // driven from tb_uvm_top by hierarchical reference (the RTL is not changed)
  logic       p_ex_use_a;      // legal instruction in EX reads rs1 (rs1 != x0)
  logic       p_ex_use_b;      // ... reads rs2 (rs2 != x0)
  logic       p_fwd_a_exmem;   // rs1 matches the EX/MEM producer
  logic       p_fwd_a_memwb;   // rs1 matches the MEM/WB producer
  logic       p_fwd_b_exmem;
  logic       p_fwd_b_memwb;
  logic       p_wt;            // ID read uses the regfile write-through from WB
  logic       p_stall;         // load-use stall
  logic       p_redirect;      // EX found the IF guess wrong -> flush
  logic       p_ctrl;          // control-flow instruction in EX
  logic [1:0] p_ctrl_kind;     // 0 branch, 1 jal, 2 jalr
  logic       p_pred_taken;    // IF guessed taken for it
  logic       p_act_taken;     // it really was taken
  logic       p_ic_fill;       // icache line fill in progress
endinterface
