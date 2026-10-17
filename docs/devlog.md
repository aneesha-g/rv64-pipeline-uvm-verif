# Devlog

## Phase 1: C++ ISS (RV32I)
- Built RV32I golden model with RVFI-style retire trace (one line per instruction).
- XLEN is a compile flag for the later RV64 step. Memory base 0x80000000, 1 MiB.
- Tests: t_basic, t_loop, t_alu (self-checking, x10=0 means pass).
- Bugs hit / how I debugged: (fill this in)
