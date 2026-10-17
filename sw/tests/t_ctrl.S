.macro CHECK reg, val
    li   x31, \val
    bne  \reg, x31, fail
.endm
.section .text.init
.globl _start
_start:
    jal  x1, f1             # x1 = pc+4
    j    fail
f1:
    auipc x2, 0             # x2 = pc of this insn
    addi x3, x2, -4
    bne  x1, x3, fail       # x1 must equal x2-4
    la   x4, f2
    jalr x5, 0(x4)
    j    fail
f2:
    li   x6, -5
    li   x7, 3
    blt  x6, x7, b1
    j    fail
b1:
    bltu x6, x7, fail       # 0xFFFFFFFB is not < 3 unsigned
    bge  x7, x6, b2
    j    fail
b2:
    bgeu x6, x7, b3
    j    fail
b3:
    li   x12, 0x80001000
    li   x13, 0x1234ABCD
    sw   x13, 0(x12)
    sh   x13, 4(x12)
    sb   x13, 8(x12)
    lw   x14, 0(x12)
    CHECK x14, 0x1234ABCD
    lh   x15, 0(x12)
    CHECK x15, -21555       # 0xFFFFABCD
    lhu  x16, 0(x12)
    CHECK x16, 0xABCD
    lb   x17, 2(x12)
    CHECK x17, 0x34
    lb   x18, 3(x12)
    CHECK x18, 0x12
    lb   x19, 0(x12)
    CHECK x19, -51          # 0xFFFFFFCD
    lbu  x20, 0(x12)
    CHECK x20, 0xCD
    lh   x21, 4(x12)
    CHECK x21, -21555
    lw   x22, 8(x12)
    CHECK x22, 0xCD
    li   x10, 0
    ecall
fail:
    li   x10, 1
    ecall
