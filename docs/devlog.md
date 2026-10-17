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

## Phase 4: 2-bit predictor + 64-entry BTB
- bpred.v: direct-mapped BTB (index pc[7:2], tag = upper pc), 2-bit saturating counters.
  Allocate on taken, update on hit. BP_EN=0 reproduces the Phase 3 core.
- EX compares the real next pc against the pc IF guessed (carried in ifid/idex_pred_pc).
- New tests: t_bench (nested loops + alternating branch), t_bp (BTB aliasing + wrong-path illegal fetch).
- CPI / redirects (paste scripts/cpi.sh output here): (fill this in)
- Observation: alternating branch defeats a 2-bit counter (mispredicts ~every time).
- Bugs hit / how I debugged: (fill this in)

## Phase 5: direct-mapped icache
- icache.v: 64 lines x 16 B, tag/index/word split, valid cleared during fill, FSM fills one word per request.
- imem port is now req/valid with variable latency (the UVM imem agent will drive this).
- t_icache: straight-line code across lines + two functions 1 KiB apart that conflict on one set.
- Traces identical at imem_lat = 1, 3, 10. CPI / fills table (paste cpi.sh output): (fill this in)
- Known limits: no fence.i / store coherence, in-flight fills aren't cancelled on redirect.
- Bugs hit / how I debugged: (fill this in)
