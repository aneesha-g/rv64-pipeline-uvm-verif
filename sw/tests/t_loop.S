.section .text.init
.globl _start
_start:
    li   x1, 0             # sum
    li   x2, 1             # i
    li   x3, 11            # limit
loop:
    add  x1, x1, x2
    addi x2, x2, 1
    bne  x2, x3, loop
    li   x4, 55
    bne  x1, x4, fail
    li   x10, 0
    ecall
fail:
    li   x10, 1
    ecall
