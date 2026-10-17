.section .text.init
.globl _start
_start:
    li   x1, 0
    .rept 40
    addi x1, x1, 1          # straight-line code across many cache lines
    .endr
    li   x31, 40
    bne  x1, x31, fail

    li   x2, 0              # sum
    li   x3, 5              # rounds
round:
    jal  x5, funcA
    jal  x5, funcB
    addi x3, x3, -1
    bnez x3, round
    li   x31, 55            # 5 * (1 + 10)
    bne  x2, x31, fail
    li   x10, 0
    ecall
fail:
    li   x10, 1
    ecall

    .org 0x200
funcA:                      # index 32
    addi x2, x2, 1
    jr   x5
    .org 0x600
funcB:                      # also index 32: evicts funcA, and vice versa
    addi x2, x2, 10
    jr   x5
