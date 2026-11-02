#!/usr/bin/env python3
"""Constrained-random WISC-S25 program generator.

Programs always terminate: branches only jump forward, except loop
back-edges that count a reserved register down to zero.

Register conventions inside a generated program:
    R1-R7, R11   free (random destinations)
    R8           data base + 0x400  (same cache set as R14, different tag)
    R9           data base + small even offset (aliases with R14)
    R10          scratch for BR targets
    R12          constant 1
    R13          loop counter
    R14          data base (around 0x4010)
    R15          data base + 0x800  (third tag in the same set -> evictions)

Usage: python3 gen_random.py SEED [-o prog.s]
"""

import argparse
import random

FREE = [1, 2, 3, 4, 5, 6, 7, 11]
BASES = [14, 9, 8, 15]
CONDS = ["NEQ", "EQ", "GT", "LT", "GTE", "LTE", "OVFL", "UNCOND"]


class Gen:
    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.lines = []
        self.label_id = 0
        self.recent = []            # recently written registers (to build RAW chains)

    def label(self):
        self.label_id += 1
        return f"L{self.label_id}"

    def emit(self, text):
        self.lines.append("    " + text)

    def place(self, lbl):
        self.lines.append(f"{lbl}:")

    def src(self):
        r = self.rng.random()
        if r < 0.45 and self.recent:
            return self.rng.choice(self.recent[-4:])
        if r < 0.55:
            return 0
        return self.rng.randrange(16)

    def dst(self, allow_r0=True):
        if allow_r0 and self.rng.random() < 0.07:
            return 0
        d = self.rng.choice(FREE)
        self.recent.append(d)
        return d

    # ---- instruction kinds ----
    def alu(self):
        op = self.rng.choice(["ADD", "SUB", "XOR", "RED", "PADDSB", "SLL", "SRA", "ROR",
                              "LLB", "LHB", "ADD", "SUB"])
        if op in ("SLL", "SRA", "ROR"):
            self.emit(f"{op} R{self.dst()}, R{self.src()}, {self.rng.randrange(16)}")
        elif op in ("LLB", "LHB"):
            self.emit(f"{op} R{self.dst()}, 0x{self.rng.randrange(256):02x}")
        else:
            self.emit(f"{op} R{self.dst()}, R{self.src()}, R{self.src()}")

    def mem(self):
        base = self.rng.choice(BASES)
        off = self.rng.randrange(-8, 8)
        if self.rng.random() < 0.5:
            self.emit(f"LW R{self.dst(allow_r0=False)}, R{base}, {off}")
        else:
            self.emit(f"SW R{self.src()}, R{base}, {off}")

    def fwd_pair(self):
        """Store then reload the same word, possibly through the aliasing base
        R9, with a little unrelated work in between (store-to-load forwarding)."""
        off = self.rng.randrange(-4, 4)
        self.emit(f"SW R{self.src()}, R14, {off}")
        for _ in range(self.rng.randrange(0, 3)):
            self.simple()
        off9 = off - self.r9_delta
        if self.rng.random() < 0.5 and -8 <= off9 <= 7:
            self.emit(f"LW R{self.dst(allow_r0=False)}, R9, {off9}")
        else:
            self.emit(f"LW R{self.dst(allow_r0=False)}, R14, {off}")

    def compare(self):
        a, b = self.src(), self.src()
        self.emit(f"SUB R0, R{a}, R{b}" if self.rng.random() < 0.7 else f"ADD R0, R{a}, R{b}")

    def simple(self):
        (self.mem if self.rng.random() < 0.35 else self.alu)()

    def fwd_branch(self):
        if self.rng.random() < 0.7:
            self.compare()
        skip = self.label()
        cond = self.rng.choice(CONDS[:7]) if self.rng.random() < 0.9 else "UNCOND"
        self.emit(f"B {cond}, {skip}")
        for _ in range(self.rng.randrange(1, 5)):
            self.simple()
        self.place(skip)

    def indirect(self):
        tgt = self.label()
        self.emit(f"LI R10, {tgt}")
        if self.rng.random() < 0.6:
            self.compare()
        cond = self.rng.choice(CONDS)
        self.emit(f"BR {cond}, R10")
        for _ in range(self.rng.randrange(0, 4)):
            self.simple()
        self.place(tgt)

    def loop(self):
        top = self.label()
        self.emit(f"LLB R13, {self.rng.randrange(1, 7)}")
        self.place(top)
        for _ in range(self.rng.randrange(2, 9)):
            if self.rng.random() < 0.2:
                self.fwd_branch()
            else:
                self.simple()
        self.emit("SUB R13, R13, R12")
        self.emit(f"B NEQ, {top}")

    def wrong_path_trap(self):
        """A branch that is always taken but starts out predicted not-taken;
        the fall-through holds a HLT or a store that must never commit."""
        r = self.rng.randrange(16)
        skip = self.label()
        self.emit(f"SUB R0, R{r}, R{r}")         # Z = 1
        self.emit(f"B EQ, {skip}")
        if self.rng.random() < 0.5:
            self.emit("HLT")
        else:
            self.emit(f"SW R{self.src()}, R14, {self.rng.randrange(-8, 8)}")
        self.place(skip)

    def program(self):
        rng = self.rng
        base = 0x4010 + 2 * rng.randrange(8)
        self.r9_delta = rng.randrange(-4, 5)        # R9 = R14 + 2 * r9_delta
        self.lines.append(f"# random program, data base 0x{base:04x}")
        self.emit("LLB R12, 1")
        self.emit(f"LI R14, 0x{base:04x}")
        self.emit(f"LI R9, 0x{base + 2 * self.r9_delta:04x}")
        self.emit(f"LI R8, 0x{base + 0x400:04x}")
        self.emit(f"LI R15, 0x{base + 0x800:04x}")
        for r in FREE:
            self.emit(f"LI R{r}, 0x{rng.randrange(65536):04x}")

        kinds = [(self.simple, 50), (self.fwd_branch, 14), (self.loop, 8),
                 (self.indirect, 5), (self.wrong_path_trap, 3), (self.compare, 6),
                 (self.fwd_pair, 8)]
        total = sum(w for _, w in kinds)
        for _ in range(rng.randrange(40, 120)):
            pick = rng.randrange(total)
            for fn, w in kinds:
                if pick < w:
                    fn()
                    break
                pick -= w
        self.emit("HLT")
        # Junk after HLT: must never be executed or committed.
        for _ in range(4):
            self.emit(f".word 0x{rng.randrange(65536):04x}")

        self.lines.append(".org 0x4000")
        self.lines.append(".word " + ", ".join(f"0x{rng.randrange(65536):04x}" for _ in range(32)))
        self.lines.append(f".org 0x{0x4000 + 0x400:04x}")
        self.lines.append(".word " + ", ".join(f"0x{rng.randrange(65536):04x}" for _ in range(32)))
        return "\n".join(self.lines) + "\n"


def generate(seed):
    return Gen(seed).program()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("seed", type=int)
    ap.add_argument("-o", "--out")
    a = ap.parse_args()
    text = generate(a.seed)
    if a.out:
        with open(a.out, "w") as f:
            f.write(text)
    else:
        print(text, end="")
