# Pipeline hazards (Phase 3)

| Hazard | Where detected | Fix | Cost |
|---|---|---|---|
| RAW, producer 1 ahead | EX (rs matches EX/MEM rd) | forward EX/MEM result | 0 cycles |
| RAW, producer 2 ahead | EX (rs matches MEM/WB rd) | forward MEM/WB value | 0 cycles |
| RAW, producer 3 ahead | ID (rs matches WB rd) | regfile write-through | 0 cycles |
| Load-use | ID (load in EX, rs matches rd) | stall 1 cycle, bubble into EX | 1 cycle |
| Taken branch / jal / jalr | EX | flush IF/ID + ID/EX, redirect PC | 2 cycles |
| ecall / illegal | ID | stop fetch, drain, retire last | n/a |

Rules: youngest producer wins; x0 is never forwarded; operand use is
checked per instruction type (uses_rs1/uses_rs2).
