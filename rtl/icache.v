// Direct-mapped instruction cache. Hit = combinational. Miss = FSM refills one
// line, one word per memory request, then the line becomes valid.
// No coherence with stores (no fence.i): code is assumed not to be modified.
module icache #(
  parameter XLEN       = 32,
  parameter LINES      = 64,
  parameter LINE_WORDS = 4
)(
  input                clk,
  input                rst_n,
  // core side (IF)
  input                req,          // 1 = fills may start (0 after ecall)
  input  [XLEN-1:0]    pc,
  output               hit,
  output [31:0]        rdata,
  // memory side (line fill, one word per request)
  output               mem_req,
  output [XLEN-1:0]    mem_addr,
  input                mem_rvalid,
  input  [31:0]        mem_rdata
);
  localparam OFFW = $clog2(LINE_WORDS);      // word-offset bits
  localparam IDXW = $clog2(LINES);           // index bits
  localparam LSB  = OFFW + 2;                // byte-offset bits within a line
  localparam TAGW = XLEN - IDXW - LSB;

  reg              v_arr [0:LINES-1];
  reg [TAGW-1:0]   t_arr [0:LINES-1];
  reg [31:0]       d_arr [0:LINES*LINE_WORDS-1];

  // ---- lookup ----
  wire [IDXW-1:0] idx  = pc[LSB+IDXW-1:LSB];
  wire [OFFW-1:0] woff = pc[LSB-1:2];
  wire [TAGW-1:0] ptag = pc[XLEN-1:LSB+IDXW];

  assign hit   = v_arr[idx] & (t_arr[idx] == ptag);
  assign rdata = d_arr[{idx, woff}];

  // ---- refill FSM ----
  reg              filling;
  reg [XLEN-1:0]   fill_base;                // line-aligned address being filled
  reg [OFFW-1:0]   fill_cnt;
  reg [63:0]       perf_fills;

  wire [IDXW-1:0] fidx = fill_base[LSB+IDXW-1:LSB];
  wire [TAGW-1:0] ftag = fill_base[XLEN-1:LSB+IDXW];

  assign mem_req  = filling;
  assign mem_addr = fill_base + {fill_cnt, 2'b00};

  integer i;
  always @(posedge clk) begin
    if (!rst_n) begin
      filling    <= 1'b0;
      fill_cnt   <= {OFFW{1'b0}};
      perf_fills <= 64'd0;
      for (i = 0; i < LINES; i = i + 1) v_arr[i] <= 1'b0;
    end else if (!filling) begin
      if (req && !hit) begin                 // miss: start a fill
        filling     <= 1'b1;
        fill_base   <= {pc[XLEN-1:LSB], {LSB{1'b0}}};
        fill_cnt    <= {OFFW{1'b0}};
        v_arr[idx]  <= 1'b0;                 // invalid while being filled
        perf_fills  <= perf_fills + 64'd1;
      end
    end else if (mem_rvalid) begin           // word arrived
      d_arr[{fidx, fill_cnt}] <= mem_rdata;
      if (fill_cnt == LINE_WORDS-1) begin
        filling     <= 1'b0;
        v_arr[fidx] <= 1'b1;
        t_arr[fidx] <= ftag;
      end else begin
        fill_cnt <= fill_cnt + 1'b1;
      end
    end
  end
endmodule
