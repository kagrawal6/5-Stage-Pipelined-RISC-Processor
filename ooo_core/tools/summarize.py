#!/usr/bin/env python3
"""Turn the CSVs in results/ into results/SUMMARY.md.

"Suite IPC" below is total committed instructions / total cycles over all directed
tests, so the long benchmarks dominate it; per-test numbers are in the CSVs.

Regenerate everything (from ooo_core/):
  python3 tools/run_tests.py --baseline                    --csv results/baseline_vs_ooo.csv
  python3 tools/run_tests.py --bp all --er 0,1             --csv results/predictors.csv
  python3 tools/run_tests.py --rob-w 2,3,4,5               --csv results/sweep_rob.csv
  python3 tools/run_tests.py --iq-n 2,4,8,16               --csv results/sweep_iq.csv
  python3 tools/run_tests.py --sq-w 1,2,3,4                --csv results/sweep_sq.csv
  python3 tools/run_tests.py --restart 0,1 --ipf 0,1 --dpf 0,1 --csv results/memory_features.csv
  python3 tools/summarize.py
"""

import collections
import csv
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "results")
BP_NAMES = ["static not-taken", "BTFN", "bimodal", "gshare", "tournament", "perceptron", "TAGE-lite"]


def load(name):
    path = os.path.join(RES, name)
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return list(csv.DictReader(f))


def group(rows, key):
    out = collections.OrderedDict()
    for r in sorted(rows, key=lambda r: tuple(int(r[k]) for k in key)):
        out.setdefault(tuple(int(r[k]) for k in key), []).append(r)
    return out


def total(rows, col):
    return sum(int(r[col]) for r in rows)


def suite_ipc(rows):
    return total(rows, "commits") / total(rows, "cycles")


def table(head, lines):
    out = ["| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"]
    out += ["| " + " | ".join(str(x) for x in ln) + " |" for ln in lines]
    return "\n".join(out) + "\n"


def baseline_section(rows):
    lines, speedups = [], []
    for r in sorted(rows, key=lambda r: r["test"]):
        com, cyc = int(r["commits"]), int(r["cycles"])
        bc = int(r["baseline_cycles"]) if r["baseline_cycles"] else None
        ok = r.get("baseline_ok") == "1"
        if bc and ok:
            speedups.append(bc / cyc)
        lines.append([r["test"], com,
                      (f"{bc}" if ok else f"{bc} *") if bc else "no halt",
                      f"{com / bc:.3f}" if bc and ok else "-",
                      cyc, f"{com / cyc:.3f}",
                      f"{bc / cyc:.2f}x" if bc and ok else "-"])
    gm = math.exp(sum(map(math.log, speedups)) / len(speedups)) if speedups else 0
    return ("## Phase-3 in-order core vs out-of-order core\n\n"
            "Default OoO configuration (TAGE-lite, early recovery, ROB 16, IQ 8, SQ 8, "
            "early restart, I/D next-line prefetch). `*` = the phase-3 core halted with wrong "
            "register values (its known flag/address bugs), so its cycle count is not comparable "
            "and is excluded from the speedup.\n\n"
            + table(["test", "insts", "5-stage cycles", "5-stage IPC", "OoO cycles", "OoO IPC", "speedup"],
                    lines)
            + f"\nGeometric-mean speedup over the {len(speedups)} programs the phase-3 core runs "
              f"correctly: **{gm:.2f}x** (range {min(speedups):.2f}x - {max(speedups):.2f}x).\n")


def predictor_section(rows):
    g = group(rows, ["bp", "early_recovery"])
    lines = []
    for bp in range(7):
        commit, early = g.get((bp, 0)), g.get((bp, 1))
        if not commit or not early:
            continue
        lines.append([BP_NAMES[bp],
                      f"{100 * total(early, 'cond_mispred') / total(early, 'cond_br'):.1f}%",
                      f"{100 * total(early, 'br_reg_mispred') / max(1, total(early, 'br_reg')):.1f}%",
                      f"{suite_ipc(commit):.3f}", f"{suite_ipc(early):.3f}"])
    bench = sorted({r["test"] for r in rows if r["test"].startswith("bench_") or r["test"] == "flags_branches"})
    per = []
    for t in bench:
        ln = [t]
        for bp in range(7):
            rs = [r for r in g.get((bp, 1), []) if r["test"] == t]
            ln.append(f"{rs[0]['cond_mispred']}/{rs[0]['cond_br']}" if rs else "-")
        per.append(ln)
    return ("## Branch predictors and recovery point\n\n"
            "Mispredict rates are with early (execute-time) recovery; the direction predictor does "
            "not depend on the recovery mode, only on what it is trained with. The programs are "
            "short, so a noticeable part of every predictor's mispredicts is warm-up.\n\n"
            + table(["predictor", "cond. mispredict", "BR (BTB) mispredict",
                     "suite IPC, recover at commit", "suite IPC, recover at execute"], lines)
            + "\nConditional mispredicts / conditional branches per program (early recovery):\n\n"
            + table(["test"] + BP_NAMES, per))


def sweep_section(rows, col, title, stall_col, fmt_size):
    lines = []
    for (size,), rs in group(rows, [col]).items():
        cyc = total(rs, "cycles")
        lines.append([fmt_size(size), f"{suite_ipc(rs):.3f}", cyc,
                      f"{100 * total(rs, stall_col) / cyc:.1f}%",
                      f"{total(rs, 'rob_occ_sum') / cyc:.2f}"])
    return (f"### {title}\n\n"
            + table([col.upper() + " entries", "suite IPC", "total cycles",
                     f"cycles stalled on full {col.upper()}", "avg ROB occupancy"], lines))


def memory_section(rows):
    g = group(rows, ["early_restart", "i_prefetch", "d_prefetch"])
    base = total(g[(0, 0, 0)], "cycles")
    lines = []
    for (rs, ipf, dpf), r in g.items():
        cyc = total(r, "cycles")
        lines.append(["on" if rs else "off", "on" if ipf else "off", "on" if dpf else "off",
                      cyc, f"{100 * (base - cyc) / base:+.1f}%", f"{suite_ipc(r):.3f}",
                      total(r, "icache_miss"), total(r, "dcache_miss"), total(r, "prefetches")])
    return ("## Memory-side optimizations\n\n"
            "Cycles saved are relative to all three features off.\n\n"
            + table(["early restart", "I prefetch", "D prefetch", "total cycles", "cycles saved",
                     "suite IPC", "I demand misses", "D demand misses", "prefetches"], lines))


def main():
    parts = ["# Results\n\nGenerated by `tools/summarize.py` from the CSVs in this directory.\n"]
    for name, fn in [("baseline_vs_ooo.csv", baseline_section), ("predictors.csv", predictor_section)]:
        rows = load(name)
        if rows:
            parts.append(fn(rows))
    sweeps = [("sweep_rob.csv", "rob", "Reorder buffer size", "stall_rob", str),
              ("sweep_iq.csv", "iq", "Issue queue size", "stall_iq", str),
              ("sweep_sq.csv", "sq", "Store queue size", "stall_sq", str)]
    sweep_parts = [sweep_section(load(n), *a) for n, *a in sweeps if load(n)]
    if sweep_parts:
        parts.append("## Window sizes\n\nOne structure varied at a time, everything else at the "
                     "default (ROB 16, IQ 8, SQ 8).\n\n" + "\n".join(sweep_parts))
    rows = load("memory_features.csv")
    if rows and "early_restart" in rows[0]:
        parts.append(memory_section(rows))
    with open(os.path.join(RES, "SUMMARY.md"), "w") as f:
        f.write("\n".join(parts))
    print("wrote results/SUMMARY.md")


if __name__ == "__main__":
    main()
