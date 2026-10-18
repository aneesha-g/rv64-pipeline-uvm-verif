# Mutation testing results

Suite: 50 tests (directed + random + spread + long random). Detectors: live ISS-vs-RTL lockstep (functional) and cycle count vs the unmutated build (performance).

| # | Mutant | Bug injected | Expected | Result | First catch | Tests failing |
|---|---|---|---|---|---|---|
| 1 | `fwd_exmem_off` | EX/MEM -> EX forwarding disabled for operand A | functional | KILLED | r_10 | 50/50 |
| 2 | `fwd_priority_swap` | double hazard: older MEM/WB value wins over EX/MEM (operand B) | functional | KILLED | r_10 | 26/50 |
| 3 | `loaduse_no_stall` | load-use stall removed | functional | KILLED | r_10 | 43/50 |
| 4 | `flush_skipped` | wrong-path instruction in ID is not flushed after a mispredict | functional | KILLED | r_10 | 49/50 |
| 5 | `x0_forwarded` | instructions with rd=x0 are treated as writers (forwarded) | functional | KILLED | r_10 | 45/50 |
| 6 | `lb_no_signext` | LB zero-extends instead of sign-extending | functional | KILLED | r_11 | 30/50 |
| 7 | `imm_b_bit11` | branch immediate bit 11 forced to 0 (backward branches break) | functional | KILLED | r_10 | 46/50 |
| 8 | `icache_unaligned_fill` | line fill starts at the miss pc instead of the line start | functional | KILLED | r_11 | 28/50 |
| 9 | `btb_wrong_target` | BTB predicts target+4 (EX recovers, only speed changes) | perf | KILLED (perf) | cycles differ, e.g. r_10 | 46/50 |
| 10 | `btb_no_tag` | BTB tag compare dropped (aliasing; EX recovers, only speed changes) | perf | KILLED (perf) | cycles differ, e.g. r_10 | 43/50 |

**Mutation score: 10/10 killed.**
