.section .text.init
.globl _start
_start:
    li   x1, 5
    li   x2, 7
    add  x3, x1, x2        # 12
    sub  x4, x2, x1        # 2
    slli x5, x3, 2         # 48
    li   x6, 0x80001000    # data address
    sw   x5, 0(x6)
    lw   x7, 0(x6)         # 48
    beq  x7, x5, ok
    li   x10, 1
    ecall
ok:
    li   x10, 0
    ecall
