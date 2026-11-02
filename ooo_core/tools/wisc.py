#!/usr/bin/env python3
"""WISC-S25 toolchain: assembler, disassembler and golden ISA simulator.

Usage:
    python3 wisc.py asm  prog.s  -o prog.img
    python3 wisc.py dis  prog.img
    python3 wisc.py sim  prog.img [--trace golden.trace] [--max-steps N]

The golden simulator executes one instruction at a time in program order and
writes a commit trace. The RTL testbench writes the same format from the ROB
commit port, so the two files can be compared line by line.

Trace line format (one per committed instruction):
    <pc> <instr> -              no architectural register/memory write
    <pc> <instr> R<n>=<val>     register write (R0 writes are never listed)
    <pc> <instr> M[<a>]=<val>   store to byte address a
All numbers are 4-digit lowercase hex.
"""

import argparse
import re
import sys

OPCODES = {
    "ADD": 0x0, "SUB": 0x1, "XOR": 0x2, "RED": 0x3,
    "SLL": 0x4, "SRA": 0x5, "ROR": 0x6, "PADDSB": 0x7,
    "LW": 0x8, "SW": 0x9, "LLB": 0xA, "LHB": 0xB,
    "B": 0xC, "BR": 0xD, "PCS": 0xE, "HLT": 0xF,
}
OPNAMES = {v: k for k, v in OPCODES.items()}

CONDS = {
    "NEQ": 0, "NE": 0, "EQ": 1, "GT": 2, "LT": 3,
    "GTE": 4, "GE": 4, "LTE": 5, "LE": 5,
    "OVFL": 6, "OV": 6, "UNCOND": 7, "UN": 7,
}
CONDNAMES = ["NEQ", "EQ", "GT", "LT", "GTE", "LTE", "OVFL", "UNCOND"]


# --------------------------------------------------------------------------
# Assembler
# --------------------------------------------------------------------------

class AsmError(Exception):
    pass


def _strip_comment(line):
    for marker in ("//", "#", ";"):
        idx = line.find(marker)
        if idx >= 0:
            line = line[:idx]
    return line.strip()


def _parse_reg(tok):
    m = re.fullmatch(r"[Rr$](\d+)", tok.strip())
    if not m or not 0 <= int(m.group(1)) <= 15:
        raise AsmError(f"bad register '{tok}'")
    return int(m.group(1))


def _parse_int(tok, labels=None):
    tok = tok.strip()
    if labels is not None and tok in labels:
        return labels[tok]
    try:
        return int(tok, 0)
    except ValueError:
        raise AsmError(f"bad number or unknown label '{tok}'")


def _expand_pseudo(mnem, ops):
    """Return a list of (mnemonic, operands) real instructions."""
    if mnem == "NOP":
        return [("PADDSB", ["R0", "R0", "R0"])]
    if mnem == "MOV":          # MOV rd, rs  (PADDSB with R0 does not touch flags)
        return [("PADDSB", [ops[0], ops[1], "R0"])]
    if mnem == "CMP":          # CMP rs, rt  -> SUB R0, rs, rt (sets N Z V)
        return [("SUB", ["R0", ops[0], ops[1]])]
    if mnem == "LI":           # LI rd, imm16 -> LLB + LHB
        return [("LLB", [ops[0], f"%lo({ops[1]})"]),
                ("LHB", [ops[0], f"%hi({ops[1]})"])]
    return [(mnem, ops)]


def _split_ops(rest):
    return [o.strip() for o in rest.split(",")] if rest.strip() else []


def assemble(text):
    """Assemble source text. Returns dict {word_address: value}."""
    # Pass 1: collect labels and the item list with locations.
    items = []          # (byte_addr, kind, payload, lineno)
    labels = {}
    loc = 0
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = _strip_comment(raw)
        while True:
            m = re.match(r"^([A-Za-z_]\w*)\s*:\s*(.*)$", line)
            if not m:
                break
            if m.group(1) in labels:
                raise AsmError(f"line {lineno}: duplicate label {m.group(1)}")
            labels[m.group(1)] = loc
            line = m.group(2).strip()
        if not line:
            continue
        parts = line.split(None, 1)
        mnem = parts[0].upper()
        rest = parts[1] if len(parts) > 1 else ""
        if mnem == ".ORG":
            loc = _parse_int(rest)
            if loc & 1:
                raise AsmError(f"line {lineno}: .org must be even")
            continue
        if mnem == ".WORD":
            for tok in _split_ops(rest):
                items.append((loc, "word", tok, lineno))
                loc += 2
            continue
        if mnem == ".FILL":
            ops = _split_ops(rest)
            count = _parse_int(ops[0])
            val = ops[1] if len(ops) > 1 else "0"
            for _ in range(count):
                items.append((loc, "word", val, lineno))
                loc += 2
            continue
        if mnem not in OPCODES and mnem not in ("NOP", "MOV", "CMP", "LI"):
            raise AsmError(f"line {lineno}: unknown mnemonic {mnem}")
        for real_mnem, real_ops in _expand_pseudo(mnem, _split_ops(rest)):
            items.append((loc, "insn", (real_mnem, real_ops), lineno))
            loc += 2

    # Pass 2: encode.
    mem = {}

    def imm_value(tok):
        m = re.fullmatch(r"%(lo|hi)\((.*)\)", tok.strip())
        if m:
            v = _parse_int(m.group(2), labels) & 0xFFFF
            return (v & 0xFF) if m.group(1) == "lo" else (v >> 8)
        return _parse_int(tok, labels)

    for addr, kind, payload, lineno in items:
        try:
            if kind == "word":
                word = imm_value(payload) & 0xFFFF
            else:
                word = _encode(addr, payload[0], payload[1], labels, imm_value)
        except AsmError as e:
            raise AsmError(f"line {lineno}: {e}")
        if addr // 2 in mem:
            raise AsmError(f"line {lineno}: address 0x{addr:04x} written twice")
        mem[addr // 2] = word
    return mem


def _encode(pc, mnem, ops, labels, imm_value):
    op = OPCODES[mnem]

    def need(n):
        if len(ops) != n:
            raise AsmError(f"{mnem} expects {n} operands, got {len(ops)}")

    if mnem in ("ADD", "SUB", "XOR", "RED", "PADDSB"):
        need(3)
        return (op << 12) | (_parse_reg(ops[0]) << 8) | (_parse_reg(ops[1]) << 4) | _parse_reg(ops[2])
    if mnem in ("SLL", "SRA", "ROR"):
        need(3)
        imm = imm_value(ops[2])
        if not 0 <= imm <= 15:
            raise AsmError(f"shift amount {imm} out of range 0..15")
        return (op << 12) | (_parse_reg(ops[0]) << 8) | (_parse_reg(ops[1]) << 4) | imm
    if mnem in ("LW", "SW"):
        need(3)
        off = imm_value(ops[2])
        if not -8 <= off <= 7:
            raise AsmError(f"offset {off} out of range -8..7 (offset is in words)")
        return (op << 12) | (_parse_reg(ops[0]) << 8) | (_parse_reg(ops[1]) << 4) | (off & 0xF)
    if mnem in ("LLB", "LHB"):
        need(2)
        imm = imm_value(ops[1])
        if not -128 <= imm <= 255:
            raise AsmError(f"byte immediate {imm} out of range")
        return (op << 12) | (_parse_reg(ops[0]) << 8) | (imm & 0xFF)
    if mnem == "B":
        need(2)
        cond = CONDS.get(ops[0].upper())
        if cond is None:
            raise AsmError(f"bad condition '{ops[0]}'")
        tgt = ops[1]
        if tgt in labels:
            diff = labels[tgt] - (pc + 2)
            if diff & 1:
                raise AsmError("odd branch distance")
            off = diff >> 1
        else:
            off = _parse_int(tgt)
        if not -256 <= off <= 255:
            raise AsmError(f"branch offset {off} out of range")
        return (op << 12) | (cond << 9) | (off & 0x1FF)
    if mnem == "BR":
        need(2)
        cond = CONDS.get(ops[0].upper())
        if cond is None:
            raise AsmError(f"bad condition '{ops[0]}'")
        return (op << 12) | (cond << 9) | (_parse_reg(ops[1]) << 4)
    if mnem == "PCS":
        need(1)
        return (op << 12) | (_parse_reg(ops[0]) << 8)
    if mnem == "HLT":
        return 0xF000
    raise AsmError(f"cannot encode {mnem}")


def write_image(mem, path):
    """Write a $readmemh image (word addresses, '@' marks gaps)."""
    lines = []
    expected = None
    for waddr in sorted(mem):
        if waddr != expected:
            lines.append(f"@{waddr:x}")
        lines.append(f"{mem[waddr]:04x}")
        expected = waddr + 1
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def read_image(path):
    """Read a $readmemh image into {word_address: value}."""
    mem = {}
    waddr = 0
    with open(path) as f:
        for raw in f:
            line = _strip_comment(raw.replace("//", "#"))
            for tok in line.split():
                if tok.startswith("@"):
                    waddr = int(tok[1:], 16)
                else:
                    mem[waddr] = int(tok, 16) & 0xFFFF
                    waddr += 1
    return mem


# --------------------------------------------------------------------------
# Disassembler
# --------------------------------------------------------------------------

def sext(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def disassemble(word, pc=None):
    op = word >> 12
    rd, rs, rt = (word >> 8) & 0xF, (word >> 4) & 0xF, word & 0xF
    name = OPNAMES[op]
    if op in (0x0, 0x1, 0x2, 0x3, 0x7):
        return f"{name} R{rd}, R{rs}, R{rt}"
    if op in (0x4, 0x5, 0x6):
        return f"{name} R{rd}, R{rs}, {rt}"
    if op in (0x8, 0x9):
        return f"{name} R{rd}, R{rs}, {sext(rt, 4)}"
    if op in (0xA, 0xB):
        return f"{name} R{rd}, 0x{word & 0xFF:02x}"
    if op == 0xC:
        off = sext(word, 9)
        tgt = f" -> 0x{(pc + 2 + (off << 1)) & 0xFFFF:04x}" if pc is not None else ""
        return f"B {CONDNAMES[(word >> 9) & 7]}, {off}{tgt}"
    if op == 0xD:
        return f"BR {CONDNAMES[(word >> 9) & 7]}, R{rs}"
    if op == 0xE:
        return f"PCS R{rd}"
    return "HLT"


# --------------------------------------------------------------------------
# Golden ISA simulator
# --------------------------------------------------------------------------

def _sat16(v):
    return max(-32768, min(32767, v))


def alu(op, a, b):
    """Return (result, z, n, v, writes_z, writes_nv) for compute opcodes 0..7."""
    sa, sb = sext(a, 16), sext(b, 16)
    if op in (0x0, 0x1):
        exact = sa + sb if op == 0x0 else sa - sb
        res = _sat16(exact) & 0xFFFF
        return res, res == 0, bool(res & 0x8000), exact != _sat16(exact), True, True
    if op == 0x2:
        res = a ^ b
        return res, res == 0, False, False, True, False
    if op == 0x3:
        # RED as built by the reused RED.v tree: each nibble pair is added as
        # unsigned 4-bit (carry becomes bit 4), that 5-bit value is then
        # treated as signed, the four are summed and sign-extended to 16 bits.
        total = 0
        for i in range(4):
            s = ((a >> (4 * i)) & 0xF) + ((b >> (4 * i)) & 0xF)
            total += sext(s, 5)
        return total & 0xFFFF, False, False, False, False, False
    if op == 0x7:
        res = 0
        for i in range(4):
            s = sext(a >> (4 * i), 4) + sext(b >> (4 * i), 4)
            s = max(-8, min(7, s))
            res |= (s & 0xF) << (4 * i)
        return res, False, False, False, False, False
    sh = b & 0xF
    if op == 0x4:
        res = (a << sh) & 0xFFFF
    elif op == 0x5:
        res = (sa >> sh) & 0xFFFF
    else:
        res = ((a >> sh) | (a << (16 - sh))) & 0xFFFF if sh else a
    return res, res == 0, False, False, True, False


def cond_true(cond, z, n, v):
    return [not z, z, (not z) and (not n), n, z or (not n), n or z, v, True][cond]


class GoldenSim:
    def __init__(self, mem):
        self.mem = dict(mem)
        self.regs = [0] * 16
        self.z = self.n = self.v = False
        self.pc = 0
        self.halted = False
        self.uninit_reads = []

    def read(self, byte_addr):
        waddr = (byte_addr & 0xFFFF) >> 1
        if waddr not in self.mem:
            self.uninit_reads.append(byte_addr & 0xFFFE)
        return self.mem.get(waddr, 0)

    def step(self):
        """Execute one instruction. Returns a trace line (without newline)."""
        pc = self.pc
        word = self.read(pc)
        op = word >> 12
        rd, rs, rt = (word >> 8) & 0xF, (word >> 4) & 0xF, word & 0xF
        regs = self.regs
        effect = "-"
        next_pc = (pc + 2) & 0xFFFF
        wr = None

        if op <= 0x7:
            b = rt if op in (0x4, 0x5, 0x6) else regs[rt]
            res, z, n, v, wz, wnv = alu(op, regs[rs], b)
            if wz:
                self.z = z
            if wnv:
                self.n, self.v = n, v
            wr = (rd, res)
        elif op in (0x8, 0x9):
            addr = ((regs[rs] & 0xFFFE) + (sext(rt, 4) << 1)) & 0xFFFF
            if op == 0x8:
                wr = (rd, self.read(addr))
            else:
                self.mem[addr >> 1] = regs[rd]
                effect = f"M[{addr:04x}]={regs[rd]:04x}"
        elif op == 0xA:
            wr = (rd, (regs[rd] & 0xFF00) | (word & 0xFF))
        elif op == 0xB:
            wr = (rd, (regs[rd] & 0x00FF) | ((word & 0xFF) << 8))
        elif op == 0xC:
            if cond_true((word >> 9) & 7, self.z, self.n, self.v):
                next_pc = (pc + 2 + (sext(word, 9) << 1)) & 0xFFFF
        elif op == 0xD:
            if cond_true((word >> 9) & 7, self.z, self.n, self.v):
                next_pc = regs[rs]
        elif op == 0xE:
            wr = (rd, (pc + 2) & 0xFFFF)
        else:
            self.halted = True
            next_pc = pc

        if wr is not None and wr[0] != 0:
            regs[wr[0]] = wr[1] & 0xFFFF
            effect = f"R{wr[0]}={wr[1] & 0xFFFF:04x}"
        self.pc = next_pc
        return f"{pc:04x} {word:04x} {effect}"

    def run(self, max_steps=200000):
        trace = []
        while not self.halted:
            if len(trace) >= max_steps:
                raise RuntimeError(f"no HLT after {max_steps} instructions")
            trace.append(self.step())
        return trace


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("asm", help="assemble a .s file into a $readmemh image")
    p.add_argument("src")
    p.add_argument("-o", "--out", required=True)

    p = sub.add_parser("dis", help="disassemble an image")
    p.add_argument("img")

    p = sub.add_parser("sim", help="run the golden simulator")
    p.add_argument("img")
    p.add_argument("--trace", help="write the commit trace here")
    p.add_argument("--max-steps", type=int, default=200000)

    args = ap.parse_args(argv)
    try:
        if args.cmd == "asm":
            with open(args.src) as f:
                write_image(assemble(f.read()), args.out)
        elif args.cmd == "dis":
            mem = read_image(args.img)
            for waddr in sorted(mem):
                pc = waddr * 2
                print(f"{pc:04x}: {mem[waddr]:04x}  {disassemble(mem[waddr], pc)}")
        else:
            sim = GoldenSim(read_image(args.img))
            trace = sim.run(args.max_steps)
            if args.trace:
                with open(args.trace, "w") as f:
                    f.write("\n".join(trace) + "\n")
            print(f"instructions={len(trace)} regs=" +
                  " ".join(f"{r:04x}" for r in sim.regs) +
                  f" flags Z={int(sim.z)} N={int(sim.n)} V={int(sim.v)}")
            if sim.uninit_reads:
                print(f"warning: {len(sim.uninit_reads)} reads of uninitialized memory", file=sys.stderr)
    except (AsmError, RuntimeError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
