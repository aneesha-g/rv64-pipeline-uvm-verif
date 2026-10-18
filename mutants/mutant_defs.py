# One injected bug per entry. `pattern` must match exactly once in rtl/<file>.
MUTANTS = [
    dict(name="fwd_exmem_off", file="core.v", kind="functional",
         desc="EX/MEM -> EX forwarding disabled for operand A",
         pattern=r"\(exmem_wen & \(exmem_rd == ex_rs1\)\)",
         replace="(1'b0 & (exmem_rd == ex_rs1))"),

    dict(name="fwd_priority_swap", file="core.v", kind="functional",
         desc="double hazard: older MEM/WB value wins over EX/MEM (operand B)",
         pattern=r"\(exmem_wen & \(exmem_rd == ex_rs2\)\)",
         replace="(exmem_wen & (exmem_rd == ex_rs2) & ~(memwb_wen & (memwb_rd == ex_rs2)))"),

    dict(name="loaduse_no_stall", file="core.v", kind="functional",
         desc="load-use stall removed",
         pattern=r"wire stall\s*=\s*ifid_valid & load_use;",
         replace="wire stall = 1'b0;"),

    dict(name="flush_skipped", file="core.v", kind="functional",
         desc="wrong-path instruction in ID is not flushed after a mispredict",
         pattern=r"if \(ex_redirect \| stall\) begin",
         replace="if (stall) begin"),

    dict(name="x0_forwarded", file="core.v", kind="functional",
         desc="instructions with rd=x0 are treated as writers (forwarded)",
         pattern=r"e_writes_rd & \(ex_rd != 5'd0\)",
         replace="e_writes_rd"),

    dict(name="lb_no_signext", file="core.v", kind="functional",
         desc="LB zero-extends instead of sign-extending",
         pattern=r"m_load_val = \$signed\(m_rsh\[7:0\]\);",
         replace="m_load_val = m_rsh[7:0];"),

    dict(name="imm_b_bit11", file="decode.v", kind="functional",
         desc="branch immediate bit 11 forced to 0 (backward branches break)",
         pattern=r"insn\[31\], insn\[7\], insn\[30:25\]",
         replace="insn[31], 1'b0, insn[30:25]"),

    dict(name="icache_unaligned_fill", file="icache.v", kind="functional",
         desc="line fill starts at the miss pc instead of the line start",
         pattern=r"fill_base\s*<= \{pc\[XLEN-1:LSB\], \{LSB\{1'b0\}\}\};",
         replace="fill_base <= pc;"),

    dict(name="btb_wrong_target", file="bpred.v", kind="perf",
         desc="BTB predicts target+4 (EX recovers, only speed changes)",
         pattern=r"assign pred_target = btb_target\[idx\];",
         replace="assign pred_target = btb_target[idx] + 4;"),

    dict(name="btb_no_tag", file="bpred.v", kind="perf",
         desc="BTB tag compare dropped (aliasing; EX recovers, only speed changes)",
         pattern=r"wire hit = btb_valid\[idx\] & \(btb_tag\[idx\] == tag\);",
         replace="wire hit = btb_valid[idx];"),
]
