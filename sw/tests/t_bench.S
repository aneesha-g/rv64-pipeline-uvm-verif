.section .text.init
.globl _start
_start:
    li   x1, 0              # sum
    li   x2, 0              # i (outer)
    li   x3, 20
outer:
    li   x4, 0              # j (inner)
    li   x5, 20
inner:
    add  x1, x1, x4
    andi x6, x4, 1
    beq  x6, x0, even       # alternates taken / not-taken
    addi x1, x1, 1          # odd j: +1
even:
    addi x4, x4, 1
    bne  x4, x5, inner
    addi x2, x2, 1
    bne  x2, x3, outer
    li   x7, 4000           # 20 * (190 + 10)
    bne  x1, x7, fail
    li   x10, 0
    ecall
fail:
    li   x10, 1
    ecall
