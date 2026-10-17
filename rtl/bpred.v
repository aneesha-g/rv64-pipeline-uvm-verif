// BTB + 2-bit saturating counters, direct-mapped, indexed by pc[IDXW+1:2].
// Lookup is combinational (IF). Update happens when a control-flow
// instruction executes (EX). The predictor only affects performance:
// EX checks every guess, so a wrong guess is just a flush.
module bpred #(
  parameter XLEN    = 32,
  parameter ENTRIES = 64,
  parameter BP_EN   = 1
)(
  input                clk,
  input                rst_n,
  // lookup (IF)
  input  [XLEN-1:0]    pc,
  output               pred_taken,
  output [XLEN-1:0]    pred_target,
  // update (EX)
  input                upd_en,       // a branch/jal/jalr is executing
  input  [XLEN-1:0]    upd_pc,
  input                upd_taken,
  input  [XLEN-1:0]    upd_target
);
  localparam IDXW = $clog2(ENTRIES);
  localparam TAGW = XLEN - 2 - IDXW;

  reg              btb_valid  [0:ENTRIES-1];
  reg [TAGW-1:0]   btb_tag    [0:ENTRIES-1];
  reg [XLEN-1:0]   btb_target [0:ENTRIES-1];
  reg [1:0]        btb_cnt    [0:ENTRIES-1];

  // ---- lookup (IF) ----
  wire [IDXW-1:0] idx = pc[IDXW+1:2];
  wire [TAGW-1:0] tag = pc[XLEN-1:IDXW+2];
  wire hit = btb_valid[idx] & (btb_tag[idx] == tag);
  assign pred_taken  = (BP_EN != 0) & hit & btb_cnt[idx][1];
  assign pred_target = btb_target[idx];

  // ---- update (EX) ----
  wire [IDXW-1:0] uidx = upd_pc[IDXW+1:2];
  wire [TAGW-1:0] utag = upd_pc[XLEN-1:IDXW+2];
  wire            uhit = btb_valid[uidx] & (btb_tag[uidx] == utag);

  integer i;
  always @(posedge clk) begin
    if (!rst_n) begin
      for (i = 0; i < ENTRIES; i = i + 1) btb_valid[i] <= 1'b0;
    end else if (upd_en && BP_EN != 0) begin
      if (uhit) begin
        if (upd_taken) begin
          btb_target[uidx] <= upd_target;
          if (btb_cnt[uidx] != 2'b11) btb_cnt[uidx] <= btb_cnt[uidx] + 2'd1;
        end else begin
          if (btb_cnt[uidx] != 2'b00) btb_cnt[uidx] <= btb_cnt[uidx] - 2'd1;
        end
      end else if (upd_taken) begin       // allocate only on taken
        btb_valid[uidx]  <= 1'b1;
        btb_tag[uidx]    <= utag;
        btb_target[uidx] <= upd_target;
        btb_cnt[uidx]    <= 2'b10;        // weakly taken
      end
    end
  end
endmodule
