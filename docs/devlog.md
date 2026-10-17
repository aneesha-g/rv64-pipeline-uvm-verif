# Devlog

## Phase 1: C++ ISS (RV32I)
- Built RV32I golden model with RVFI-style retire trace (one line per instruction).
- XLEN is a compile flag for the later RV64 step. Memory base 0x80000000, 1 MiB.
- Tests: t_basic, t_loop, t_alu (self-checking, x10=0 means pass).
- Bugs hit / how I debugged: (fill this in)

## Phase 2: single-cycle RV32I core
- regfile, alu, core with registered RVFI retire port. Illegal-instruction rules match the ISS.
- tb_core.sv prints retire trace in ISS format; lockstep.sh diffs ISS vs RTL.
- Added t_ctrl (jal/jalr/auipc, all branches, sb/sh/sw and lb/lh/lbu/lhu).
- Bugs hit / how I debugged: (fill this in)

## Phase 3: 5-stage pipeline
- Split decode into decode.v; single-cycle core kept as core_sc.v.
- Forwarding (EX/MEM, MEM/WB, regfile write-through), 1-cycle load-use stall,
  2-cycle flush on taken branch/jump (predict not-taken). RVFI retires from WB.
- t_hazard covers forwarding at d1/d2/d3, double hazard, x0, load-use, flushes.
- CPI numbers (cycles vs instructions) for t_loop: (fill this in)
- Bugs hit / how I debugged: (fill this in)
