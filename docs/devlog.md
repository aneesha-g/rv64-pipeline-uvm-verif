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
