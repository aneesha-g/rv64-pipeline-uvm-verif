.macro CHECK reg, val
    li   x31, \val
    bne  \reg, x31, fail
.endm
.section .text.init
.globl _start
_start:
    li   x1, -1
    li   x2, 1
    slt  x3, x1, x2        # -1 < 1  -> 1
    CHECK x3, 1
    sltu x4, x1, x2        # 0xFFFFFFFF < 1 -> 0
    CHECK x4, 0
    srai x5, x1, 4         # arithmetic: stays -1
    CHECK x5, -1
    srli x6, x1, 4         # logical: 0x0FFFFFFF
    CHECK x6, 0x0FFFFFFF
    slli x7, x2, 31        # 0x80000000
    CHECK x7, 0x80000000
    srai x8, x7, 31        # -1
    CHECK x8, -1
    lui  x9, 0xFFFFF       # 0xFFFFF000
    CHECK x9, -4096
    li   x12, 0x80001000
    li   x13, 0x80
    sb   x13, 0(x12)
    lb   x14, 0(x12)       # sign-extended: 0xFFFFFF80
    CHECK x14, -128
    lbu  x15, 0(x12)       # zero-extended: 0x80
    CHECK x15, 0x80
    li   x10, 0
    ecall
fail:
    li   x10, 1
    ecall
