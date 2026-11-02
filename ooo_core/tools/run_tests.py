#!/usr/bin/env python3
"""Regression runner for the out-of-order core.

For every (test program, core configuration) pair:
  1. assemble the program (tests/*.s or generated random programs),
  2. run the golden ISA simulator -> expected commit trace + final memory,
  3. run the RTL testbench        -> actual commit trace + memory dump,
  4. compare both line by line and collect the performance counters.

Examples (run from ooo_core/):
  python3 tools/run_tests.py                       # all directed tests, default config
  python3 tools/run_tests.py --bp all --er 0,1     # every predictor, both recovery modes
  python3 tools/run_tests.py --random 200 --seed 7 # constrained-random programs
  python3 tools/run_tests.py --tests sort,fib -v   # a subset, verbose
  python3 tools/run_tests.py --sim verilator       # use Verilator instead of Icarus
"""

import argparse
import concurrent.futures as cf
import glob
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                       # ooo_core/
sys.path.insert(0, HERE)
import wisc                                         # noqa: E402
import gen_random                                   # noqa: E402

BP_NAMES = {0: "static-NT", 1: "BTFN", 2: "bimodal", 3: "gshare",
            4: "tournament", 5: "perceptron", 6: "TAGE"}


# --------------------------------------------------------------------------
# Building simulators
# --------------------------------------------------------------------------

class Config:
    def __init__(self, bp=6, er=1, rob_w=4, iq_n=8, sq_w=3, rs=1, ipf=1, dpf=1):
        self.bp, self.er, self.rob_w, self.iq_n, self.sq_w = bp, er, rob_w, iq_n, sq_w
        self.rs, self.ipf, self.dpf = rs, ipf, dpf

    @property
    def params(self):
        return {"BP_TYPE": self.bp, "EARLY_RECOVERY": self.er,
                "ROB_W": self.rob_w, "IQ_N": self.iq_n, "SQ_W": self.sq_w,
                "EARLY_RESTART": self.rs, "I_PREFETCH": self.ipf, "D_PREFETCH": self.dpf}

    @property
    def name(self):
        return (f"bp{self.bp}_er{self.er}_rob{1 << self.rob_w}_iq{self.iq_n}_sq{1 << self.sq_w}"
                f"_rs{self.rs}_pf{self.ipf}{self.dpf}")

    def label(self):
        return (f"{BP_NAMES[self.bp]}, {'early' if self.er else 'commit'} recovery, "
                f"ROB {1 << self.rob_w}, IQ {self.iq_n}, SQ {1 << self.sq_w}, "
                f"early-restart {self.rs}, I/D prefetch {self.ipf}/{self.dpf}")


def build(cfg, sim):
    """Compile the testbench for one configuration; return the run command prefix."""
    out_dir = os.path.join(ROOT, "build", f"{sim}_{cfg.name}")
    os.makedirs(out_dir, exist_ok=True)
    srcs = [os.path.join(ROOT, "rtl", "ooo_defs.vh")] + _file_list()
    if sim == "icarus":
        exe = os.path.join(out_dir, "sim.vvp")
        if _stale(exe, srcs):
            cmd = ["iverilog", "-g2012", "-I", os.path.join(ROOT, "rtl"), "-s", "cpu_tb", "-o", exe]
            for k, v in cfg.params.items():
                cmd += ["-P", f"cpu_tb.{k}={v}"]
            cmd += _file_list()
            _check_call(cmd)
        return ["vvp", "-n", exe]
    exe = os.path.join(out_dir, "Vcpu_tb")
    if _stale(exe, srcs):
        cmd = ["verilator", "--binary", "--timing", "-j", "0", "-Wno-fatal", "-Wno-lint",
               "-Wno-style", "-Wno-MULTIDRIVEN", "-I" + os.path.join(ROOT, "rtl"),
               "--top-module", "cpu_tb", "-Mdir", out_dir]
        for k, v in cfg.params.items():
            cmd += [f"-G{k}={v}"]
        cmd += _file_list()
        _check_call(cmd)
    return [exe]


def build_baseline():
    exe = os.path.join(ROOT, "build", "baseline", "sim.vvp")
    os.makedirs(os.path.dirname(exe), exist_ok=True)
    base_dir = os.path.join(ROOT, "..", "project_working_directory")
    srcs = [f for f in glob.glob(os.path.join(base_dir, "*.v"))
            if not f.endswith("project-phase3-testbench.v")]
    srcs.append(os.path.join(ROOT, "tb", "baseline_tb.v"))
    if _stale(exe, srcs):
        _check_call(["iverilog", "-g2012", "-s", "baseline_tb", "-o", exe] + srcs)
    return ["vvp", "-n", exe]


def _file_list():
    files = []
    with open(os.path.join(ROOT, "files.f")) as f:
        for line in f:
            line = line.split("//")[0].strip()
            if line:
                files.append(os.path.normpath(os.path.join(ROOT, line)))
    return files


def _stale(target, sources):
    if not os.path.exists(target):
        return True
    t = os.path.getmtime(target)
    return any(os.path.getmtime(s) > t for s in sources)


def _check_call(cmd):
    res = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if res.returncode != 0:
        print(res.stdout[-4000:], res.stderr[-4000:], sep="\n")
        raise SystemExit(f"build failed: {' '.join(cmd[:3])} ...")


# --------------------------------------------------------------------------
# Tests
# --------------------------------------------------------------------------

class Test:
    def __init__(self, name, source):
        self.name, self.source = name, source
        self.img = self.golden = None
        self.golden_mem = None
        self.golden_regs = None


def prepare(test, work):
    """Assemble and run the golden model once per test."""
    os.makedirs(work, exist_ok=True)
    mem = test.source if isinstance(test.source, dict) else wisc.assemble(test.source)
    test.img = os.path.join(work, test.name + ".img")
    wisc.write_image(mem, test.img)
    sim = wisc.GoldenSim(mem)
    trace = sim.run()
    test.golden = trace
    test.golden_mem = sim.mem
    test.golden_regs = sim.regs[1:]
    return test


def parse_stats(text):
    m = re.search(r"^STATS (.*)$", text, re.M)
    if not m:
        return None
    return {k: int(v) for k, v in (kv.split("=") for kv in m.group(1).split())}


def run_one(test, cfg, cmd, work, max_cycles):
    tag = f"{test.name}.{cfg.name}"
    trace_path = os.path.join(work, tag + ".trace")
    mem_path = os.path.join(work, tag + ".mem")
    res = subprocess.run(cmd + [f"+IMG={test.img}", f"+TRACE={trace_path}",
                                f"+MEMDUMP={mem_path}", f"+MAX_CYCLES={max_cycles}"],
                         cwd=work, capture_output=True, text=True)
    out = res.stdout + res.stderr
    result = {"test": test.name, "cfg": cfg, "ok": False, "why": "", "stats": parse_stats(out)}
    if "TIMEOUT" in out or result["stats"] is None:
        result["why"] = "timeout / no halt" if "TIMEOUT" in out else "simulator error: " + out[-300:]
        result["detail"] = _trace_mismatch(test.golden, _read_lines(trace_path))
        return result
    actual = _read_lines(trace_path)
    mismatch = _trace_mismatch(test.golden, actual)
    if mismatch:
        result["why"], result["detail"] = "commit trace mismatch", mismatch
        return result
    rtl_mem = wisc.read_image(mem_path)
    for waddr, val in sorted(test.golden_mem.items()):
        if rtl_mem.get(waddr, 0) != val:
            result["why"] = (f"memory mismatch at 0x{waddr * 2:04x}: "
                             f"expected {val:04x}, got {rtl_mem.get(waddr, 0):04x}")
            return result
    os.remove(mem_path)
    result["ok"] = True
    return result


def run_baseline(test, cmd, work):
    # The phase-3 core is gate-level and slow to simulate, and its flag bugs can send
    # some programs into a loop that never reaches HLT, so bound each run.
    max_cycles = 20 * len(test.golden) + 5000
    try:
        res = subprocess.run(cmd + [f"+IMG={test.img}", f"+MAX_CYCLES={max_cycles}"],
                             cwd=work, capture_output=True, text=True, timeout=600)
        out = res.stdout
    except subprocess.TimeoutExpired:
        out = "TIMEOUT"
    m = re.search(r"BASELINE cycles=(\d+)", out)
    r = re.search(r"REGS (.*)", out)
    regs = [int(x, 16) for x in r.group(1).split()] if r else None
    status = "ok" if m and regs == test.golden_regs else ("wrong result" if m else "no halt")
    print(f"  baseline {test.name:<22} {m.group(1) if m else '-':>7} cycles  {status}", flush=True)
    return {"test": test.name, "cycles": int(m.group(1)) if m else None,
            "regs_ok": regs == test.golden_regs}


def _read_lines(path):
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return [ln.rstrip("\n") for ln in f if ln.strip()]


def _trace_mismatch(expected, actual):
    for i, (e, a) in enumerate(zip(expected, actual)):
        if e != a:
            lo = max(0, i - 3)
            ctx = "\n".join(f"    {'>' if j == i else ' '} #{j}: expected {expected[j]:<24} got {actual[j]}"
                            for j in range(lo, min(i + 2, len(expected), len(actual))))
            return f"first difference at commit #{i}:\n{ctx}"
    if len(expected) != len(actual):
        return (f"expected {len(expected)} commits, got {len(actual)}"
                + (f" (next expected: {expected[len(actual)]})" if len(actual) < len(expected) else ""))
    return ""


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

def _int_list(text, all_values):
    return list(all_values) if text == "all" else [int(x) for x in text.split(",")]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sim", choices=["icarus", "verilator"], default="icarus")
    ap.add_argument("--bp", default="6", help="predictor list, e.g. 3,6 or 'all'")
    ap.add_argument("--er", default="1", help="early recovery: 0, 1 or 0,1")
    ap.add_argument("--rob-w", default="4", help="log2 ROB size list, e.g. 3,4,5")
    ap.add_argument("--iq-n", default="8", help="issue-queue size list")
    ap.add_argument("--sq-w", default="3", help="log2 store-queue size list")
    ap.add_argument("--restart", default="1", help="critical-word-first / early restart: 0, 1 or 0,1")
    ap.add_argument("--ipf", default="1", help="next-line I-cache prefetch: 0, 1 or 0,1")
    ap.add_argument("--dpf", default="1", help="next-line D-cache prefetch: 0, 1 or 0,1")
    ap.add_argument("--tests", default="", help="comma-separated substrings of directed test names")
    ap.add_argument("--no-directed", action="store_true", help="skip tests/*.s")
    ap.add_argument("--random", type=int, default=0, help="number of random programs")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--baseline", action="store_true", help="also time the phase-3 in-order core")
    ap.add_argument("--max-cycles", type=int, default=300000)
    ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--csv", help="write per-run results to this CSV file")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    configs = [Config(bp, er, rw, iq, sw, rs, ipf, dpf)
               for bp in _int_list(args.bp, range(7))
               for er in _int_list(args.er, (0, 1))
               for rw in _int_list(args.rob_w, ())
               for iq in _int_list(args.iq_n, ())
               for sw in _int_list(args.sq_w, ())
               for rs in _int_list(args.restart, (0, 1))
               for ipf in _int_list(args.ipf, (0, 1))
               for dpf in _int_list(args.dpf, (0, 1))]

    tests = []
    if not args.no_directed:
        paths = glob.glob(os.path.join(ROOT, "tests", "*.s")) + glob.glob(os.path.join(ROOT, "tests", "*.img"))
        for path in sorted(paths):
            name = os.path.splitext(os.path.basename(path))[0]
            if args.tests and not any(t in name for t in args.tests.split(",")):
                continue
            if path.endswith(".img"):
                tests.append(Test(name, wisc.read_image(path)))
            else:
                with open(path) as f:
                    tests.append(Test(name, f.read()))
    for i in range(args.random):
        seed = args.seed + i
        tests.append(Test(f"rand{seed:05d}", gen_random.generate(seed)))
    if not tests:
        raise SystemExit("no tests selected")

    work = os.path.join(ROOT, "build", "runs")
    for t in tests:
        try:
            prepare(t, work)
        except (wisc.AsmError, RuntimeError) as e:
            raise SystemExit(f"{t.name}: {e}")

    print(f"Building {len(configs)} configuration(s) with {args.sim} ...", flush=True)
    with cf.ThreadPoolExecutor(max_workers=min(args.jobs, len(configs))) as ex:
        cmds = dict(zip([c.name for c in configs], ex.map(lambda c: build(c, args.sim), configs)))

    jobs = [(t, c) for c in configs for t in tests]
    print(f"Running {len(jobs)} simulations ({len(tests)} programs x {len(configs)} configs) ...", flush=True)
    results = []
    with cf.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futs = [ex.submit(run_one, t, c, cmds[c.name], work, args.max_cycles) for t, c in jobs]
        for fut in cf.as_completed(futs):
            r = fut.result()
            results.append(r)
            if not r["ok"]:
                print(f"FAIL {r['test']} [{r['cfg'].label()}]: {r['why']}")
                if r.get("detail"):
                    print(r["detail"])

    base = {}
    if args.baseline:
        print("Timing the phase-3 in-order core (Icarus, slow) ...", flush=True)
        bcmd = build_baseline()
        with cf.ThreadPoolExecutor(max_workers=args.jobs) as ex:
            for b in ex.map(lambda t: run_baseline(t, bcmd, work), tests):
                base[b["test"]] = b

    _report(tests, configs, results, base, args)
    failed = sum(not r["ok"] for r in results)
    print(f"\n{len(results) - failed}/{len(results)} passed")
    return 1 if failed else 0


def _report(tests, configs, results, base, args):
    by_key = {(r["test"], r["cfg"].name): r for r in results}
    if args.csv:
        keys = sorted({k for r in results for k in (r["stats"] or {})})
        with open(args.csv, "w") as f:
            f.write("test,config,bp,early_recovery,rob,iq,sq,early_restart,i_prefetch,d_prefetch,"
                    "pass,ipc,baseline_cycles,baseline_ok," + ",".join(keys) + "\n")
            for r in sorted(results, key=lambda r: (r["cfg"].name, r["test"])):
                s, c = r["stats"] or {}, r["cfg"]
                cyc, com = s.get("cycles", 0), s.get("commits", 0)
                b = base.get(r["test"], {})
                f.write(f"{r['test']},{c.name},{c.bp},{c.er},{1 << c.rob_w},{c.iq_n},{1 << c.sq_w},"
                        f"{c.rs},{c.ipf},{c.dpf},"
                        f"{int(r['ok'])},{com / cyc if cyc else 0:.4f},{b.get('cycles') or ''},"
                        f"{int(b['regs_ok']) if b else ''},"
                        + ",".join(str(s.get(k, "")) for k in keys) + "\n")

    show_tests = [t for t in tests if not t.name.startswith("rand")] if len(tests) > 40 else tests
    if not show_tests and not args.verbose:
        return
    print()
    head = f"{'test':<22}{'insts':>7}"
    if base:
        head += f"{'base cyc':>10}{'base IPC':>9}"
    for c in configs:
        head += f" | {c.name[:22]:>22}"
    print(head)
    for t in show_tests:
        line = f"{t.name:<22}{len(t.golden):>7}"
        if base:
            bc = base.get(t.name, {}).get("cycles")
            mark = "" if base.get(t.name, {}).get("regs_ok") else "*"
            line += f"{(str(bc) + mark) if bc else '-':>10}{(len(t.golden) / bc) if bc else 0:>9.3f}"
        for c in configs:
            r = by_key[(t.name, c.name)]
            s = r["stats"] or {}
            if r["ok"]:
                ipc = s["commits"] / s["cycles"]
                mp = f"{s['cond_mispred']}/{s['cond_br']}" if s["cond_br"] else "-"
                line += f" | {s['cycles']:>7} {ipc:5.3f} {mp:>8}"
            else:
                line += f" | {'FAIL':>22}"
        print(line)
    if base and any(not b["regs_ok"] for b in base.values()):
        print("  * baseline final registers differ from the ISA model (known phase-3 flag bugs)")


if __name__ == "__main__":
    sys.exit(main())
