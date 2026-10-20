# Devlog

## Phase 1: C++ ISS (RV32I)

* Built RV32I golden model with RVFI-style retire trace (one line per instruction).
* XLEN is a compile flag for the later RV64 step. Memory base 0x80000000, 1 MiB.
* Tests: t\_basic, t\_loop, t\_alu (self-checking, x10=0 means pass).
* Bugs hit / how I debugged: (fill this in)

## Phase 2: single-cycle RV32I core

* regfile, alu, core with registered RVFI retire port. Illegal-instruction rules match the ISS.
* tb\_core.sv prints retire trace in ISS format; lockstep.sh diffs ISS vs RTL.
* Added t\_ctrl (jal/jalr/auipc, all branches, sb/sh/sw and lb/lh/lbu/lhu).
* Bugs hit / how I debugged: (fill this in)

## Phase 3: 5-stage pipeline

* Split decode into decode.v; single-cycle core kept as core\_sc.v.
* Forwarding (EX/MEM, MEM/WB, regfile write-through), 1-cycle load-use stall,
2-cycle flush on taken branch/jump (predict not-taken). RVFI retires from WB.
* t\_hazard covers forwarding at d1/d2/d3, double hazard, x0, load-use, flushes.
* CPI numbers (cycles vs instructions) for t\_loop: (fill this in)
* Bugs hit / how I debugged: (fill this in)

## Phase 4: 2-bit predictor + 64-entry BTB

* bpred.v: direct-mapped BTB (index pc\[7:2], tag = upper pc), 2-bit saturating counters.
Allocate on taken, update on hit. BP\_EN=0 reproduces the Phase 3 core.
* EX compares the real next pc against the pc IF guessed (carried in ifid/idex\_pred\_pc).
* New tests: t\_bench (nested loops + alternating branch), t\_bp (BTB aliasing + wrong-path illegal fetch).
* CPI / redirects (paste scripts/cpi.sh output here): (fill this in)
* Observation: alternating branch defeats a 2-bit counter (mispredicts \~every time).
* Bugs hit / how I debugged: (fill this in)

## Phase 5: direct-mapped icache

* icache.v: 64 lines x 16 B, tag/index/word split, valid cleared during fill, FSM fills one word per request.
* imem port is now req/valid with variable latency (the UVM imem agent will drive this).
* t\_icache: straight-line code across lines + two functions 1 KiB apart that conflict on one set.
* Traces identical at imem\_lat = 1, 3, 10. CPI / fills table (paste cpi.sh output): (fill this in)
* Known limits: no fence.i / store coherence, in-flight fills aren't cancelled on redirect.
* Bugs hit / how I debugged: (fill this in)

## Phase 6: live ISS lockstep (DPI-C)

* iss/dpi.cpp exposes iss\_load/iss\_step; rvfi\_checker.sv steps the ISS on every RTL retire and compares all RVFI fields.
* First mismatch prints ISS vs RTL side by side and stops the sim ($fatal).
* Sanity: changed SUB to ADD in alu.v, the checker flagged retire #3 immediately. Reverted.
* This DPI wrapper + compare logic gets reused as the UVM scoreboard in Phase 7.
* Bugs hit / how I debugged: (fill this in)



## Phase 7: UVM environment (Vivado xsim, Windows)

\- Scoreboard steps the C++ ISS via DPI-C on every RTL retire and compares all 11 RVFI fields. NODPI build only counts retires (bring-up only).

\- Regression (tb\\uvm\\regress.bat, random imem timing): 12/12 PASS.

\- Sanity check: changed SUB to ADD in alu.v -> LOCKSTEP mismatch at retire #3 (sub x4,x2,x1), test FAILED. Reverted -> PASS.

\- Bug hit: DPI sim would not start on Windows (status -1073741511 = DLL entry point not found; also 5-min "Failed to communicate with child process" hangs).

&#x20; Cause: sim kernel loaded the wrong C++ runtime DLL. Fix: build.bat copies libstdc++-6.dll, libgcc\_s\_seh-1.dll and libwinpthread-1.dll

&#x20; from Vivado's MinGW 6.2.0 into xsim.dir\\rv\_sim. Passing static-link flags to xsc fails because xsc only archives; xelab does the linking.

## Phase 8: constrained-random program generator

* gen/gen.py: legal-by-construction RV32I programs (aligned/in-range memory, forward branches, bounded loops).
* Hazard-targeted: sources biased to recent destinations (RAW), load-use, store-then-load, branch on loaded
value, alternating branch inside loops, jal/jalr skips with stores on the skipped path (wrong-path stores).
* \--spread puts blocks 1 KiB apart and calls them repeatedly: icache conflict misses.
* scripts/randtest.sh runs N seeds through live ISS-vs-RTL lockstep; prints only failures.
* Seeds run (fill in): \_\_ default, \_\_ with --n 400, \_\_ with --spread, \_\_ at imem\_lat=7. Failures: \_\_
* Bugs found by random tests / how I debugged: (fill this in)

## Phase 11: mutation testing

* mutants/mutant\_defs.py: 10 injected bugs (forwarding, priority, load-use stall, flush, x0, sign-extension,
branch immediate, icache fill alignment, BTB target, BTB tag). scripts/mutate.py rebuilds a simulator per mutant
and runs the suite (directed + random + spread + long random) through ISS-vs-RTL lockstep.
* Functional bugs are caught by lockstep; BTB bugs only change speed (EX re-checks every guess), so they're
caught by a cycle-count comparison against the golden build.
* Result table: docs/mutation.md. Score: \_\_/10. Survivors and how I fixed them: (fill this in)

