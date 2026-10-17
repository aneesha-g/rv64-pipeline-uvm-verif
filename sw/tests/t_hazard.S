.macro CHECK reg, val
    li   x31, \val
    bne  \reg, x31, fail
.endm
.section .text.init
.globl _start
_start:
    # ---- ALU forwarding: producer 1, 2, 3 instructions before consumer ----
    li   x1, 5
    add  x2, x1, x1         # d1: EX/MEM forward
    CHECK x2, 10
    li   x3, 7
    nop
    add  x4, x3, x3         # d2: MEM/WB forward
    CHECK x4, 14
    li   x5, 9
    nop
    nop
    add  x6, x5, x5         # d3: regfile write-through
    CHECK x6, 18

    # ---- double hazard: youngest producer must win ----
    li   x7, 1
    li   x7, 2
    add  x8, x7, x7
    CHECK x8, 4

    # ---- dependent chain ----
    li   x9, 1
    add  x9, x9, x9
    add  x9, x9, x9
    add  x9, x9, x9
    add  x9, x9, x9
    CHECK x9, 16

    # ---- x0 is never forwarded ----
    addi x0, x0, 5
    add  x11, x0, x0
    CHECK x11, 0
    li   x12, 3
    add  x13, x0, x12
    CHECK x13, 3

    # ---- load-use ----
    li   x14, 0x80001000
    li   x15, 0x55
    sw   x15, 0(x14)
    lw   x16, 0(x14)
    add  x17, x16, x16      # load-use, d1 (stall)
    CHECK x17, 0xAA
    lw   x18, 0(x14)
    nop
    add  x19, x18, x18      # load d2 (MEM/WB forward)
    CHECK x19, 0xAA
    lw   x20, 0(x14)
    sw   x20, 4(x14)        # store data comes from a load
    lw   x21, 4(x14)
    CHECK x21, 0x55
    sw   x14, 8(x14)
    lw   x22, 8(x14)
    lw   x23, 0(x22)        # load address comes from a load
    CHECK x23, 0x55

    # ---- store address forwarded; store then load same address ----
    addi x24, x14, 16
    sw   x15, 0(x24)
    lw   x25, 16(x14)
    CHECK x25, 0x55
    li   x26, 0x77
    sw   x26, 32(x14)
    lw   x27, 32(x14)
    CHECK x27, 0x77

    # ---- branches with dependent operands ----
    li   x1, 3
    li   x2, 3
    beq  x1, x2, bt1
    j    fail
bt1:
    addi x3, x1, 1
    bne  x3, x2, bt2
    j    fail
bt2:
    lw   x11, 0(x14)
    beq  x11, x15, bt3      # branch operand comes from a load
    j    fail
bt3:

    # ---- wrong-path instructions must be flushed ----
    li   x4, 0
    beq  x0, x0, fl1
    li   x4, 99
    li   x4, 98
fl1:
    CHECK x4, 0
    sw   x0, 40(x14)
    beq  x0, x0, fl2
    sw   x15, 40(x14)       # wrong-path store: must NOT happen
    sw   x15, 40(x14)
fl2:
    lw   x6, 40(x14)
    CHECK x6, 0

    # ---- jal / jalr flush; jalr target computed just before ----
    li   x7, 0
    jal  x1, jt1
    li   x7, 99
jt1:
    CHECK x7, 0
    la   x8, jt2
    jalr x9, 0(x8)
    li   x7, 98
jt2:
    CHECK x7, 0

    li   x10, 0
    ecall
fail:
    li   x10, 1
    ecall
