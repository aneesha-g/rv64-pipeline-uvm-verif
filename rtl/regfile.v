module regfile #(parameter XLEN = 32)(
  input                 clk,
  input  [4:0]          rs1_addr,
  input  [4:0]          rs2_addr,
  output [XLEN-1:0]     rs1_data,
  output [XLEN-1:0]     rs2_data,
  input                 we,
  input  [4:0]          rd_addr,
  input  [XLEN-1:0]     rd_data
);
  reg [XLEN-1:0] regs [0:31];
  integer i;
  initial for (i = 0; i < 32; i = i + 1) regs[i] = {XLEN{1'b0}};

  assign rs1_data = (rs1_addr == 5'd0) ? {XLEN{1'b0}} : regs[rs1_addr];
  assign rs2_data = (rs2_addr == 5'd0) ? {XLEN{1'b0}} : regs[rs2_addr];

  always @(posedge clk)
    if (we && rd_addr != 5'd0) regs[rd_addr] <= rd_data;
endmodule
