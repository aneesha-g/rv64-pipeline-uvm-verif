module decode #(parameter XLEN = 32)(
  input  [31:0]      insn,
  output             is_lui, is_auipc, is_jal, is_jalr, is_branch,
  output             is_load, is_store, is_opimm, is_op, is_fence, is_halt,
  output             legal, writes_rd, uses_rs1, uses_rs2,
  output [XLEN-1:0]  imm_i, imm_s, imm_b, imm_u, imm_j
);
  wire [6:0] opcode = insn[6:0];
  wire [2:0] f3     = insn[14:12];
  wire [6:0] f7     = insn[31:25];

  assign is_lui    = (opcode == 7'h37);
  assign is_auipc  = (opcode == 7'h17);
  assign is_jal    = (opcode == 7'h6f);
  assign is_jalr   = (opcode == 7'h67);
  assign is_branch = (opcode == 7'h63);
  assign is_load   = (opcode == 7'h03);
  assign is_store  = (opcode == 7'h23);
  assign is_opimm  = (opcode == 7'h13);
  assign is_op     = (opcode == 7'h33);
  assign is_fence  = (opcode == 7'h0f);
  wire   is_system = (opcode == 7'h73);
  assign is_halt   = is_system && (insn == 32'h00000073 || insn == 32'h00100073);

  assign legal =
      is_lui | is_auipc | is_jal | is_fence | is_opimm | is_halt |
      (is_jalr   && f3 == 3'b000) |
      (is_branch && f3 != 3'b010 && f3 != 3'b011) |
      (is_load   && (f3 == 3'b000 || f3 == 3'b001 || f3 == 3'b010 ||
                     f3 == 3'b100 || f3 == 3'b101)) |
      (is_store  && (f3 == 3'b000 || f3 == 3'b001 || f3 == 3'b010)) |
      (is_op     && (f7 == 7'h00 || (f7 == 7'h20 && (f3 == 3'b000 || f3 == 3'b101))));

  assign writes_rd = is_lui | is_auipc | is_jal | is_jalr | is_load | is_opimm | is_op;
  assign uses_rs1  = is_jalr | is_branch | is_load | is_store | is_opimm | is_op;
  assign uses_rs2  = is_branch | is_store | is_op;

  assign imm_i = $signed(insn[31:20]);
  assign imm_s = $signed({insn[31:25], insn[11:7]});
  assign imm_b = $signed({insn[31], insn[7], insn[30:25], insn[11:8], 1'b0});
  assign imm_u = $signed({insn[31:12], 12'b0});
  assign imm_j = $signed({insn[31], insn[19:12], insn[20], insn[30:21], 1'b0});
endmodule
