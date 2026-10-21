// SVA checker for the 5-stage core. Attached to every `core` instance with `bind` (see tb_uvm_top.sv),
// so the RTL is not modified. Each property states a pipeline rule from docs/hazards.md or an
// RVFI/interface rule. A failure prints an Error line and is counted in n_fail; the UVM scoreboard
// reads the count and fails the test.
module core_sva #(parameter XLEN = 32) (
  input              clk,
  input              rst_n,
  // fetch / decode
  input [XLEN-1:0]   pc,
  input              ifid_valid,
  input [XLEN-1:0]   ifid_pc,
  input [31:0]       ifid_insn,
  input              idex_valid,
  // hazard control
  input              stall,
  input              ex_redirect,
  input [XLEN-1:0]   ex_next_pc,
  // EX operands and the producers in EX/MEM and MEM/WB
  input              e_legal,
  input              e_uses_rs1,
  input              e_uses_rs2,
  input [4:0]        ex_rs1,
  input [4:0]        ex_rs2,
  input [XLEN-1:0]   ex_a,
  input [XLEN-1:0]   ex_b,
  input              exmem_wen,
  input              exmem_is_load,
  input [4:0]        exmem_rd,
  input [XLEN-1:0]   exmem_result,
  input              memwb_wen,
  input [4:0]        memwb_rd,
  // icache refill port
  input              imem_req,
  input              imem_rvalid,
  input [XLEN-1:0]   imem_addr,
  // RVFI retire port
  input              rvfi_valid,
  input              rvfi_halt,
  input [63:0]       rvfi_order,
  input [XLEN-1:0]   rvfi_pc_rdata,
  input [XLEN-1:0]   rvfi_pc_wdata,
  input [4:0]        rvfi_rd_addr,
  input [XLEN-1:0]   rvfi_rd_wdata,
  input [XLEN/8-1:0] rvfi_mem_rmask,
  input [XLEN/8-1:0] rvfi_mem_wmask
);
  int unsigned n_fail = 0;

  function automatic void fail(string name);
    n_fail++;
    $error("SVA %s failed at %0t", name, $time);
  endfunction

  // the instruction in EX really reads rs1 / rs2 (x0 is never a dependency)
  wire use_a = idex_valid & e_legal & e_uses_rs1 & (ex_rs1 != 5'd0);
  wire use_b = idex_valid & e_legal & e_uses_rs2 & (ex_rs2 != 5'd0);

  // ---------------- register file ----------------
  // x0 is never written back
  a_x0_never_written: assert property (@(posedge clk) disable iff (!rst_n)
    memwb_wen |-> memwb_rd != 5'd0) else fail("a_x0_never_written");

  // RVFI reports no write data when no register is written
  a_rvfi_no_x0_data: assert property (@(posedge clk) disable iff (!rst_n)
    rvfi_valid && rvfi_rd_addr == 5'd0 |-> rvfi_rd_wdata == '0) else fail("a_rvfi_no_x0_data");

  // ---------------- forwarding ----------------
  // a load's data is never forwarded out of EX/MEM (it is not there yet): the load-use stall
  // must have kept the dependent instruction out of EX for one cycle
  a_no_load_forward: assert property (@(posedge clk) disable iff (!rst_n)
    !(exmem_wen && exmem_is_load &&
      ((use_a && ex_rs1 == exmem_rd) || (use_b && ex_rs2 == exmem_rd))))
    else fail("a_no_load_forward");

  // double hazard: when EX/MEM and MEM/WB both write the register EX reads, the younger (EX/MEM) wins
  a_fwd_youngest_a: assert property (@(posedge clk) disable iff (!rst_n)
    use_a && exmem_wen && !exmem_is_load && exmem_rd == ex_rs1 |-> ex_a == exmem_result)
    else fail("a_fwd_youngest_a");
  a_fwd_youngest_b: assert property (@(posedge clk) disable iff (!rst_n)
    use_b && exmem_wen && !exmem_is_load && exmem_rd == ex_rs2 |-> ex_b == exmem_result)
    else fail("a_fwd_youngest_b");

  // ---------------- stall and flush ----------------
  // load-use stall: a bubble goes into EX
  a_stall_bubble: assert property (@(posedge clk) disable iff (!rst_n)
    stall |=> !idex_valid) else fail("a_stall_bubble");

  // load-use stall (with no redirect): fetch holds the pc and the instruction in IF/ID
  a_stall_holds_fetch: assert property (@(posedge clk) disable iff (!rst_n)
    stall && !ex_redirect |=> ifid_valid && $stable(pc) && $stable(ifid_pc) && $stable(ifid_insn))
    else fail("a_stall_holds_fetch");

  // misprediction: both younger stages are flushed and fetch restarts at the real next pc
  a_redirect_flush: assert property (@(posedge clk) disable iff (!rst_n)
    ex_redirect |=> !ifid_valid && !idex_valid && pc == $past(ex_next_pc))
    else fail("a_redirect_flush");

  // ---------------- icache refill port ----------------
  // a refill request stays up, with the same address, until the word arrives
  a_imem_req_held: assert property (@(posedge clk) disable iff (!rst_n)
    imem_req && !imem_rvalid |=> imem_req && $stable(imem_addr))
    else fail("a_imem_req_held");

  // a refill starts at the beginning of a 16-byte line and walks it one word at a time
  a_fill_starts_aligned: assert property (@(posedge clk) disable iff (!rst_n)
    $rose(imem_req) |-> imem_addr[3:0] == 4'h0) else fail("a_fill_starts_aligned");
  a_fill_next_word: assert property (@(posedge clk) disable iff (!rst_n)
    imem_req && imem_rvalid |=> !imem_req || imem_addr == $past(imem_addr) + 4)
    else fail("a_fill_next_word");

  // environment rule (would be an assume in formal): memory only answers an open request
  a_imem_valid_needs_req: assert property (@(posedge clk) disable iff (!rst_n)
    imem_rvalid |-> imem_req) else fail("a_imem_valid_needs_req");

  // ---------------- retire stream ----------------
  // the retire counter goes up by exactly one per retired instruction
  a_order_step: assert property (@(posedge clk) disable iff (!rst_n)
    rvfi_valid |=> rvfi_order == $past(rvfi_order) + 64'd1) else fail("a_order_step");
  a_order_hold: assert property (@(posedge clk) disable iff (!rst_n)
    !rvfi_valid |=> rvfi_order == $past(rvfi_order)) else fail("a_order_hold");

  // a retire is a load, a store or neither, with a byte / half / word mask
  a_mem_mask_legal: assert property (@(posedge clk) disable iff (!rst_n)
    rvfi_valid |-> (rvfi_mem_rmask == '0 || rvfi_mem_wmask == '0) &&
                   (rvfi_mem_rmask inside {4'h0, 4'h1, 4'h3, 4'hF}) &&
                   (rvfi_mem_wmask inside {4'h0, 4'h1, 4'h3, 4'hF}))
    else fail("a_mem_mask_legal");

  // no instruction is lost or repeated: each retire starts where the previous one said it would go,
  // and nothing retires after the halting instruction
  logic            seen, halted;
  logic [XLEN-1:0] next_pc;
  always @(posedge clk) begin
    if (!rst_n) begin
      seen   <= 1'b0;
      halted <= 1'b0;
    end else if (rvfi_valid) begin
      seen    <= 1'b1;
      next_pc <= rvfi_pc_wdata;
      if (rvfi_halt) halted <= 1'b1;
    end
  end

  a_pc_chain: assert property (@(posedge clk) disable iff (!rst_n)
    rvfi_valid && seen |-> rvfi_pc_rdata == next_pc) else fail("a_pc_chain");

  a_no_retire_after_halt: assert property (@(posedge clk) disable iff (!rst_n)
    halted |-> !rvfi_valid) else fail("a_no_retire_after_halt");
endmodule
