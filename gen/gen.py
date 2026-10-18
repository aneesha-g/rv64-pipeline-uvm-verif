#!/usr/bin/env python3
"""Constrained-random RV32I program generator with hazard-targeted idioms.

Programs are legal by construction: aligned in-range memory accesses (x30 + small
offset), forward-only branches, bounded loops, and they end with ecall. They don't
self-check: correctness is judged by diffing the RTL against the ISS.
"""
import argparse
import random
import sys

SCRATCH, LOOPCNT, MAINCNT, LINK, BASE = 27, 28, 29, 26, 30   # reserved registers
RD_OK = [r for r in range(1, 32) if r not in (SCRATCH, LOOPCNT, MAINCNT, LINK, BASE)]
LSIZE = {"lb": 1, "lbu": 1, "lh": 2, "lhu": 2, "lw": 4}
SSIZE = {"sb": 1, "sh": 2, "sw": 4}
EDGE = [0, 1, 0xFFFFFFFF, 0x7FFFFFFF, 0x80000000, 0x0000FFFF, 0xFFFF0000, 0x000000FF]


def imm12(r):
    return r.choice([0, 1, -1, 2047, -2048, r.randint(-2048, 2047), r.randint(-16, 16)])


class Gen:
    def __init__(self, seed):
        self.r = random.Random(seed)
        self.lines = []
        self.recent = []          # last few written registers (to create RAW hazards)
        self.nlabel = 0

    # ---------- output helpers ----------
    def emit(self, s):
        self.lines.append("    " + s)

    def label(self, name):
        self.lines.append(name + ":")

    def newlabel(self, prefix="L"):
        self.nlabel += 1
        return f"{prefix}{self.nlabel}"

    # ---------- register choice ----------
    def rs(self):
        if self.recent and self.r.random() < 0.6:
            return self.r.choice(self.recent)
        return self.r.randrange(32)

    def rd(self):
        d = self.r.choice(RD_OK)
        self.recent = (self.recent + [d])[-4:]
        return d

    # ---------- single instructions ----------
    def alu_rr(self):
        op = self.r.choice(["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"])
        a, b = self.rs(), self.rs()
        self.emit(f"{op} x{self.rd()}, x{a}, x{b}")

    def alu_imm(self):
        a = self.rs()
        if self.r.random() < 0.25:
            op = self.r.choice(["slli", "srli", "srai"])
            self.emit(f"{op} x{self.rd()}, x{a}, {self.r.randint(0, 31)}")
        else:
            op = self.r.choice(["addi", "slti", "sltiu", "xori", "ori", "andi"])
            self.emit(f"{op} x{self.rd()}, x{a}, {imm12(self.r)}")

    def upper(self):
        op = self.r.choice(["lui", "auipc"])
        self.emit(f"{op} x{self.rd()}, {self.r.randint(0, 0xFFFFF)}")

    def load(self, kind=None, off=None):
        kind = kind or self.r.choice(list(LSIZE))
        if off is None:
            off = self.r.randrange(0, 256, LSIZE[kind])
        d = self.rd()
        self.emit(f"{kind} x{d}, {off}(x{BASE})")
        return d

    def store(self, src=None, kind=None, off=None):
        kind = kind or self.r.choice(list(SSIZE))
        if off is None:
            off = self.r.randrange(0, 256, SSIZE[kind])
        src = self.rs() if src is None else src
        self.emit(f"{kind} x{src}, {off}(x{BASE})")

    def fence(self):
        self.emit("fence")

    def simple(self):
        k = self.r.choices(["alu_rr", "alu_imm", "upper", "load", "store", "fence"],
                           weights=[30, 25, 5, 20, 15, 1])[0]
        getattr(self, k)()

    # ---------- hazard-targeted idioms ----------
    def idiom_raw(self):                       # dependent chain: forwarding at distance 1
        d = self.rd()
        self.emit(f"addi x{d}, x{self.rs()}, {imm12(self.r)}")
        for _ in range(self.r.randint(2, 4)):
            op = self.r.choice(["add", "sub", "xor", "or", "and", "slt"])
            b = self.rs()
            nd = d if self.r.random() < 0.5 else self.rd()
            self.emit(f"{op} x{nd}, x{d}, x{b}")
            d = nd

    def idiom_loaduse(self):                   # load, then use the result immediately
        d = self.load()
        op = self.r.choice(["add", "sub", "xor", "slt", "sltu", "and", "or"])
        b = self.rs()
        nd = self.rd()
        self.emit(f"{op} x{nd}, x{d}, x{b}")
        if self.r.random() < 0.3:              # ...and store the result (store data from a load)
            self.store(src=nd)

    def idiom_stld(self):                      # store, then load the same address
        sk = self.r.choice(list(SSIZE))
        off = self.r.randrange(0, 256, SSIZE[sk])
        self.store(kind=sk, off=off)
        lk = self.r.choice([k for k in LSIZE if LSIZE[k] <= SSIZE[sk]])
        self.load(kind=lk, off=off)

    def skip_body(self, n):                    # may contain stores: wrong-path stores must not happen
        for _ in range(n):
            self.simple()

    def idiom_bskip(self, srcs=None):          # forward conditional branch over 1-3 instructions
        lab = self.newlabel()
        op = self.r.choice(["beq", "bne", "blt", "bge", "bltu", "bgeu"])
        a, b = srcs if srcs else (self.rs(), self.rs())
        if srcs is None and self.r.random() < 0.3:
            b = a                              # same register: makes beq/bge taken, bne/blt not taken
        self.emit(f"{op} x{a}, x{b}, {lab}")
        self.skip_body(self.r.randint(1, 3))
        self.label(lab)

    def idiom_bload(self):                     # branch on a just-loaded value
        d = self.load()
        self.idiom_bskip(srcs=(d, self.rs()))

    def idiom_loop(self):                      # bounded loop (predictor food)
        top = self.newlabel("LP")
        self.emit(f"addi x{LOOPCNT}, x0, {self.r.randint(2, 6)}")
        self.label(top)
        for _ in range(self.r.randint(1, 3)):
            self.simple()
        if self.r.random() < 0.4:              # branch that alternates taken / not-taken
            skip = self.newlabel()
            self.emit(f"andi x{SCRATCH}, x{LOOPCNT}, 1")
            self.emit(f"beq x{SCRATCH}, x0, {skip}")
            self.simple()
            self.label(skip)
        self.emit(f"addi x{LOOPCNT}, x{LOOPCNT}, -1")
        self.emit(f"bnez x{LOOPCNT}, {top}")

    def idiom_jal(self):
        lab = self.newlabel()
        self.emit(f"jal x{self.r.choice([0] + RD_OK)}, {lab}")
        self.skip_body(self.r.randint(0, 2))
        self.label(lab)

    def idiom_jalr(self):                      # target computed just before the jalr
        lab = self.newlabel()
        self.emit(f"la x{SCRATCH}, {lab}")
        self.emit(f"jalr x{self.r.choice([0] + RD_OK)}, 0(x{SCRATCH})")
        self.skip_body(self.r.randint(0, 2))
        self.label(lab)

    def item(self):
        k = self.r.choices(
            ["simple", "raw", "loaduse", "stld", "bskip", "bload", "loop", "jal", "jalr"],
            weights=[30, 10, 10, 8, 10, 6, 7, 5, 5])[0]
        if k == "simple":
            for _ in range(self.r.randint(1, 3)):
                self.simple()
        else:
            getattr(self, "idiom_" + k)()

    def init(self):                            # data base + random/edge-case register values
        self.emit(f"lui x{BASE}, 0x80010")     # data region at 0x80010000
        for d in RD_OK:
            v = self.r.choice(EDGE) if self.r.random() < 0.3 else self.r.getrandbits(32)
            self.emit(f"li x{d}, {v:#x}")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--n", type=int, default=150, help="number of code items")
    ap.add_argument("--block", type=int, default=12, help="items per block")
    ap.add_argument("--spread", action="store_true",
                    help="blocks 1 KiB apart, called repeatedly: icache conflict misses")
    ap.add_argument("--rounds", type=int, default=3, help="--spread: times every block is called")
    ap.add_argument("--out", default="-")
    a = ap.parse_args()

    g = Gen(a.seed)
    nblocks = max(1, -(-a.n // a.block))
    if a.spread and (nblocks + 1) * 0x400 > 0x10000:
        sys.exit("--spread: too many blocks (code would reach the data area); lower --n")

    g.lines += [f"    # gen.py seed={a.seed} n={a.n} block={a.block} spread={a.spread}",
                ".section .text.init", ".globl _start"]
    g.label("_start")
    g.init()
    left = a.n
    if a.spread:
        g.emit(f"li x{MAINCNT}, {a.rounds}")
        g.label("MAIN")
        for b in range(nblocks):
            g.emit(f"jal x{LINK}, B{b}")
        g.emit(f"addi x{MAINCNT}, x{MAINCNT}, -1")
        g.emit(f"bnez x{MAINCNT}, MAIN")
        g.emit("li x10, 0")
        g.emit("ecall")
        for b in range(nblocks):
            g.lines.append(f"    .org {(b + 1) * 0x400:#x}")
            g.label(f"B{b}")
            for _ in range(min(a.block, left)):
                g.item()
            left -= a.block
            g.emit(f"jr x{LINK}")
    else:
        for b in range(nblocks):
            g.label(f"B{b}")
            for _ in range(min(a.block, left)):
                g.item()
            left -= a.block
            if b < nblocks - 1:
                g.emit(f"j B{b + 1}")
        g.emit("li x10, 0")
        g.emit("ecall")

    text = "\n".join(g.lines) + "\n"
    if a.out == "-":
        sys.stdout.write(text)
    else:
        with open(a.out, "w") as f:
            f.write(text)


if __name__ == "__main__":
    main()
