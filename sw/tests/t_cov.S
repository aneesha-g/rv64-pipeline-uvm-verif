# t_cov: directed test written to close the holes found by functional coverage
#   1. backward beq / blt / bge / bltu / bgeu, each taken twice and then not taken
#      (gen.py only makes forward branches; its loops always close with bne)
#   2. jalr with a wrong predicted target: one function called from three different sites,
#      so the BTB keeps predicting the previous return address
#   3. load-use stall while an icache line fill is still in flight: the loop's backward
#      branch is the last word of a cache line, so on the first (mispredicted) iteration IF
#      starts filling the cold line after it, then EX redirects back into the loop
.macro CHECK reg, val
    li   x31, \val
    bne  \reg, x31, fail
.endm
.section .text.init
.globl _start
_start:
    # ---- 1. backward branches ----
    li   x5, 0                  # beq: loop while x6 == 0 (x6 becomes 1 when x5 reaches 3)
1:  addi x5, x5, 1
    slti x6, x5, 3
    xori x6, x6, 1
    beq  x6, x0, 1b
    CHECK x5, 3

    li   x5, -3                 # blt (signed): -3 -> 0
2:  addi x5, x5, 1
    blt  x5, x0, 2b
    CHECK x5, 0

    li   x5, 2                  # bge (signed): 2 -> -1
3:  addi x5, x5, -1
    bge  x5, x0, 3b
    CHECK x5, -1

    li   x5, 0                  # bltu: 0 -> 3
    li   x7, 3
4:  addi x5, x5, 1
    bltu x5, x7, 4b
    CHECK x5, 3

    li   x5, 3                  # bgeu: 3 -> 0
    li   x7, 1
5:  addi x5, x5, -1
    bgeu x5, x7, 5b
    CHECK x5, 0

    # ---- 2. jalr wrong target ----
    li   x8, 0
    jal  x1, bump               # site A: first return is a plain miss (BTB empty)
    jal  x1, bump               # site B: BTB predicts a return to A+4 -> wrong target
    jal  x1, bump               # site C: BTB predicts B+4 -> wrong target again
    CHECK x8, 3

    # ---- 3. load-use stall during an icache fill ----
    lui  x30, 0x80001
    li   x9, 7
    sw   x9, 0(x30)
    li   x20, 3
    .balign 16
6:  lw   x21, 0(x30)            # these four instructions fill exactly one cache line
    addi x22, x21, 1            # uses x21 right away -> load-use stall
    addi x20, x20, -1
    bne  x20, x0, 6b            # last word of the line; the fall-through line is still cold
    CHECK x22, 8
    CHECK x20, 0

    li   x10, 0                 # pass
    ecall
fail:
    li   x10, 1
    ecall

bump:
    addi x8, x8, 1
    ret
