.section .text.init
.globl _start
_start:
    li   x1, 0              # 0x00  sum
    li   x2, 3              # 0x04  rounds
round:
    li   x3, 0              # 0x08
    li   x4, 4              # 0x0c
loopA:
    addi x1, x1, 1          # 0x10
    addi x3, x3, 1          # 0x14
    bne  x3, x4, loopA      # 0x18  branch A
    j    toB                # 0x1c
    .org 0x108
toB:
    li   x5, 0              # 0x108
    li   x6, 4              # 0x10c
loopB:
    addi x1, x1, 10         # 0x110
    addi x5, x5, 1          # 0x114
    bne  x5, x6, loopB      # 0x118  branch B: same pc[7:2] as branch A
    addi x2, x2, -1
    bnez x2, round
    li   x31, 132           # 3 * (4*1 + 4*10)
    bne  x1, x31, fail
    li   x10, 0
    ecall
fail:
    li   x10, 1
    ecall
