module alu #(parameter XLEN = 32)(
  input      [XLEN-1:0] a,
  input      [XLEN-1:0] b,
  input      [3:0]      op,      // {alt, funct3}
  output reg [XLEN-1:0] y
);
  localparam SHW = (XLEN == 64) ? 6 : 5;
  wire [SHW-1:0] sh = b[SHW-1:0];

  always @* begin
    case (op)
      4'b0000: y = a + b;                                   // ADD
      4'b1000: y = a - b;                                   // SUB
      4'b0001: y = a << sh;                                 // SLL
      4'b0010: y = ($signed(a) < $signed(b)) ? 1 : 0;       // SLT
      4'b0011: y = (a < b) ? 1 : 0;                         // SLTU
      4'b0100: y = a ^ b;                                   // XOR
      4'b0101: y = a >> sh;                                 // SRL
      4'b1101: y = $signed(a) >>> sh;                       // SRA
      4'b0110: y = a | b;                                   // OR
      4'b0111: y = a & b;                                   // AND
      default: y = {XLEN{1'b0}};
    endcase
  end
endmodule
