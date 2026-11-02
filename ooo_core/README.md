# WISC-S25 Out-of-Order Core

An out-of-order (OoO) version of the phase-3 five-stage pipeline in
[`../project_working_directory`](../project_working_directory). It runs the same WISC-S25
programs and keeps the same top-level interface (`cpu(clk, rst_n, hlt, pc)`). Inside, it is
a single-issue Tomasulo-style machine with a reorder buffer, register renaming, a unified
issue queue, a store queue with load forwarding, and a choice of seven branch predictors,
up to perceptron and TAGE.

On the programs the phase-3 core runs correctly, the default configuration is
**1.60x faster** (geometric mean, range 1.22x - 1.95x). Every configuration is
checked instruction-by-instruction against a golden ISA simulator.

Fetch, dispatch, issue and commit all handle **one instruction per cycle** (no superscalar
fetch), so IPC is at most 1.0. The default core reaches 0.99 on `bench_memcpy` and about 0.9
on the sorting and Fibonacci benchmarks.

## Contents

- [Microarchitecture](#microarchitecture)
- [Branch prediction](#branch-prediction)
- [Memory system](#memory-system)
- [Configuration parameters](#configuration-parameters)
- [Directory layout](#directory-layout)
- [How to run](#how-to-run)
- [Verification](#verification)
- [Results](#results)
- [Differences from the phase-3 core](#differences-from-the-phase-3-core)
- [Limitations and possible next steps](#limitations-and-possible-next-steps)

## Microarchitecture

```text
             +---------------------------------- redirect (mispredict) -----------------------------+
             v                                                                                      |
  +---------------------+    +-------+    +---------------------+    +------------------+           |
  | Fetch               |    |  IFQ  |    | Decode / Rename /   |    | Issue queue (8)  |           |
  |  I-cache 2 KB 2-way |--->|  (4)  |--->| Dispatch            |--->| data-capture,    |           |
  |  dir. predictor+BTB |    +-------+    |  map table (R1-R15, |    | oldest-first     |           |
  |  speculative GHR    |                 |  Z, NV) + ARF       |    | select per FU    |           |
  +---------------------+                 +---------------------+    +------------------+           |
             ^                                 |          |            |     |     |     |          |
             | refill                          v          v            v     v     v     v          |
  +---------------------+               +-----------+ +--------+     ALU   BRU   LDU   STU ---------+
  | mem_system          |               | ROB (16)  | | SQ (8) |      |           |     |
  |  1 refill engine    |<--------------| in-order  | | store  |<-----+-----------+-----+
  |  write-through path |   D refill /  | commit    | | queue  |      |           |
  |  memory4c (4-cycle) |   store drain +-----------+ +--------+      v           v
  +---------------------+                     ^                    CDB A (ALU)  CDB B (loads)
             ^                                |                       |           |
             +-------- D-cache 2 KB 2-way <---+---- wakeup / ROB write-back <-----+
```

An instruction goes through these steps:

1. **Fetch** (`frontend.v`). One instruction per cycle comes from the I-cache.
   - The next PC is predicted in the same cycle, so a correctly predicted taken branch costs
     no bubble.
   - `B UNCOND` is always taken.
   - Conditional `B` uses the direction predictor.
   - `BR` (register-indirect) is taken only when the BTB has a target for it.
   - Every fetched instruction goes into a 4-entry instruction fetch queue (IFQ), together with
     its predicted next PC and a snapshot of the global history register (GHR).
2. **Decode / rename / dispatch** (`decoder.v`, `rob.v`, `cpu.v`). Each instruction gets the
   next ROB entry, and its sources are looked up in the map table:
   - A register that isn't busy is read from the architectural register file (ARF).
   - A busy register whose producer is done is read from the ROB.
   - A value on a result bus this cycle is caught directly.
   - Otherwise the instruction waits for the producer's ROB tag.

   The flags are renamed as two extra registers, Z and NV. `XOR`/`SLL`/`SRA`/`ROR` write
   only Z, so they don't create false dependences on N and V.

   `PCS`, `HLT`, unconditional `B` and no-effect ALU ops (the `PADDSB R0,R0,R0` NOP) are
   completed at dispatch and never enter the issue queue. Stores also allocate a store-queue
   entry here.
3. **Issue** (`issue_queue.v`). The unified 8-entry issue queue holds operand values, not just
   tags (data capture).
   - Entries wake up when a result bus broadcasts the tag they are waiting for.
   - Each functional unit (ALU, BRU, LDU, STU) takes the oldest ready entry of its kind every
     cycle, so up to four instructions can issue per cycle.
   - A result can feed a dependent instruction that issues in the very next cycle (bypass at
     select).
   - A load is only selected once every older store has its address, which is a conservative
     form of memory disambiguation.
4. **Execute** (`exec_units.v`, `lsu.v`).
   - The ALU reuses the phase-3 adder, subtractor, XOR, PADDSB, RED and shifter blocks.
   - The BRU evaluates the condition and compares the actual next PC with the prediction.
   - The STU writes the address and data into the store queue.
   - The LDU forwards from the youngest older store to the same word, or reads the D-cache.
     On a miss, the load waits in a pending register until the line arrives; this also blocks
     later loads.
5. **Write-back.** There are two registered result buses, CDB A (ALU results with Z/N/V) and
   CDB B (loads). Both wake up issue-queue entries and mark ROB entries done.
6. **Commit** (`rob.v`). The oldest instruction retires once it is done.
   - It writes the ARF and the flag registers and frees its map-table entry.
   - A committing store is marked committed in the store queue and later drained to the D-cache
     and memory in program order (write-through).
   - `hlt` goes high once `HLT` has committed and the store queue is empty.

**Branch recovery.** By default (`EARLY_RECOVERY=1`) a mispredicted branch recovers as soon as
it executes:
- Every ROB, issue-queue and store-queue entry younger than the branch is squashed.
- Fetch is redirected and the GHR is restored to the branch's snapshot plus its real outcome.
- The map table is rebuilt from the ROB entries that survive, which avoids per-branch
  checkpoints and keeps the hardware small.

With `EARLY_RECOVERY=0` the core waits until the branch reaches the ROB head. That is simpler,
but measurably slower (see [Results](#results)).

## Branch prediction

All predictors train at commit, using the GHR snapshot the branch was predicted with. Select one
with `BP_TYPE`.

| `BP_TYPE` | Predictor | Organisation |
|---|---|---|
| 0 | static not-taken | - |
| 1 | BTFN | backward taken, forward not taken (sign of the offset) |
| 2 | bimodal | 1K x 2-bit counters, PC-indexed |
| 3 | gshare | 1K x 2-bit counters, PC XOR 10-bit global history |
| 4 | tournament (Alpha 21264 style) | gshare + local predictor (64-entry history table, 3-bit counters) + chooser indexed by global history |
| 5 | perceptron | 32 perceptrons, 12-bit history, 8-bit weights, threshold 37 |
| 6 | TAGE-lite (default) | 512-entry bimodal base + 3 tagged tables (128 entries, histories 4/8/16, 8-bit tags, 3-bit counters, 2-bit useful bits) |

`BR` targets come from a 16-entry direct-mapped BTB.

## Memory system

- **Caches** (`cache.v`): I-cache and D-cache, each 2 KB, 2-way set-associative, with 64 sets of
  16-byte (8-word) lines and LRU replacement. This matches the phase-3 geometry. The D-cache is
  write-through and write-allocate.
- **Refill engine** (`mem_system.v`):
  - One engine is shared by both caches and sits in front of the course `memory4c` (1-cycle
    writes, 4-cycle pipelined reads).
  - A refill issues 8 back-to-back reads.
  - Priority order: D-cache miss, then I-cache miss, then store write-through, then prefetches.
  - Stores may use the memory port once all reads of a refill have been issued.
- Three optimizations, each switchable so it can be measured on its own:
  - `EARLY_RESTART`: critical-word-first refills. The missing word is fetched first, and each
    word can be read as soon as it arrives.
  - `I_PREFETCH`: next-line instruction prefetch. While fetching from line *L*, line *L+1* is
    refilled if it isn't present and memory is idle.
  - `D_PREFETCH`: next-line data prefetch after a D-cache miss.

## Configuration parameters

All are parameters of `cpu` (and `cpu_tb`). The defaults are the configuration used in the results.

| Parameter | Default | Meaning |
|---|---|---|
| `BP_TYPE` | 6 | direction predictor (table above) |
| `EARLY_RECOVERY` | 1 | 1: recover when the branch executes, 0: at commit |
| `ROB_W` | 4 | ROB has 2^`ROB_W` entries (16) |
| `IQ_N` | 8 | issue-queue entries |
| `SQ_W` | 3 | store queue has 2^`SQ_W` entries (8) |
| `EARLY_RESTART` | 1 | critical-word-first / early restart |
| `I_PREFETCH` | 1 | next-line I prefetch |
| `D_PREFETCH` | 1 | next-line D prefetch |

## Directory layout

```text
ooo_core/
├── README.md              This file
├── files.f                Source list (reuses phase-3 ALU blocks and memory4c.v)
├── rtl/
│   ├── cpu.v              Top level: wiring, dispatch, recovery, result buses, counters
│   ├── frontend.v         Fetch, next-PC prediction, GHR, instruction fetch queue
│   ├── branch_predictor.v Predictor selection (BP_TYPE) and the BTB
│   ├── bp_basic.v         Bimodal and gshare
│   ├── bp_tournament.v    Tournament (global + local + chooser)
│   ├── bp_perceptron.v    Perceptron predictor
│   ├── bp_tage.v          TAGE-lite
│   ├── decoder.v          Instruction classes, sources, destinations, flag usage
│   ├── rob.v              Reorder buffer, ARF, map table, operand lookup, recovery rebuild
│   ├── issue_queue.v      Wakeup, oldest-first select per functional unit, squash
│   ├── exec_units.v       ALU (phase-3 arithmetic blocks) and branch unit
│   ├── lsu.v              Store queue, load forwarding, load miss handling, store drain
│   ├── cache.v            2-way cache with early-restart fill tracking and a probe port
│   ├── mem_system.v       Refill engine, prefetchers, write-through path, memory4c
│   └── ooo_defs.vh        Opcode, functional-unit and predictor constants
├── tb/
│   ├── cpu_tb.v           OoO testbench: commit trace, memory dump, STATS line
│   └── baseline_tb.v      Fast testbench for the phase-3 core (cycle counts only)
├── tests/                 Directed tests and benchmarks (*.s), course images (*.img)
├── tools/
│   ├── wisc.py            Assembler, disassembler and golden ISA simulator
│   ├── gen_random.py      Constrained-random program generator
│   ├── run_tests.py       Regression runner (build, run, compare, statistics)
│   └── summarize.py       Builds results/SUMMARY.md from the CSVs
└── results/               CSVs from the experiments and SUMMARY.md
```

## How to run

### Prerequisites

- **Icarus Verilog** 12 or newer (`iverilog`, `vvp`); 13 was used during development.
- **Python 3.8+**. No extra packages are needed.
- Optional: **Verilator** 5.x, which is faster for long random regressions.

Run every command below from `ooo_core/`.

### Regression runner

`tools/run_tests.py` assembles each program and runs the golden simulator on it. It then
builds and runs the RTL for every requested configuration and compares the commit trace and
final memory. Finally it prints cycles, IPC and conditional mispredicts per test.

```bash
python3 tools/run_tests.py                          # all directed tests, default configuration
python3 tools/run_tests.py --tests fib,memcpy -v    # a subset (substring match), verbose
python3 tools/run_tests.py --bp all --er 0,1        # every predictor x both recovery modes
python3 tools/run_tests.py --random 200 --seed 7    # add 200 constrained-random programs
python3 tools/run_tests.py --rob-w 2,3,4,5          # sweep ROB size (4..32 entries)
python3 tools/run_tests.py --restart 0,1 --ipf 0,1 --dpf 0,1   # memory-feature ablation
python3 tools/run_tests.py --baseline               # also time the phase-3 core (slow, ~3 min)
python3 tools/run_tests.py --sim verilator --random 100
python3 tools/run_tests.py --csv results/my_run.csv # all performance counters as CSV
```

Lists like `--bp 3,6` or `--iq-n 2,4,8,16` produce one configuration per combination. A
failing run prints the first commit where the RTL differs from the golden model, with a few
lines of context. Build products go to `build/`.

### One program by hand

```bash
mkdir -p build/manual
python3 tools/wisc.py asm tests/bench_fib.s -o build/manual/fib.img
iverilog -g2012 -I rtl -s cpu_tb -P cpu_tb.BP_TYPE=5 -o build/manual/sim.vvp -c files.f
cd build/manual
vvp -n sim.vvp +IMG=fib.img +TRACE=fib.trace           # prints the STATS line
python3 ../../tools/wisc.py sim fib.img --trace fib.golden
diff fib.golden fib.trace && echo "matches the ISA model"
```

Testbench plusargs:
- `+IMG=` memory image
- `+TRACE=` commit trace file
- `+MEMDUMP=` dump memory at halt
- `+MAX_CYCLES=` timeout, default 200000

Every `-P cpu_tb.<PARAM>=<value>` sets one of the parameters above.

### Writing programs

`tools/wisc.py` understands the full WISC-S25 ISA plus these conveniences:
- Labels.
- Comments starting with `//`, `#` or `;`.
- Directives: `.org`, `.word` (a number or a label) and `.fill`.
- Pseudo-ops:
  - `NOP` (= `PADDSB R0,R0,R0`)
  - `MOV rd, rs`
  - `CMP rs, rt` (= `SUB R0,rs,rt`)
  - `LI rd, value` (`LLB` + `LHB`; accepts labels)

`python3 tools/wisc.py dis prog.img` disassembles an image.

## Verification

Each test is judged by the architectural result, not by waveforms:

1. **Golden model.** `wisc.py` executes the program one instruction at a time and writes a
   commit trace, with one line per instruction showing the register or memory word it wrote.
   It was first checked against the saved phase-3 traces of the four course test images.
2. **RTL trace.** The testbench writes the same line from the ROB commit port, so the whole
   instruction stream must match in order. At halt, all of memory is dumped and compared too.
   Wrong-path work that leaks into architectural state therefore shows up at the exact
   instruction where it happens.
3. **Directed tests** (`tests/`). 24 programs: ALU and flag semantics, R0 and NOPs, renaming
   chains, store-to-load forwarding, cache conflicts, nested loops, calls via `PCS`/`BR`,
   wrong-path stores and halts, structural stalls, eight small benchmarks, and the four
   course images.
4. **Constrained-random programs** (`tools/gen_random.py`). These mix ALU ops, loads and
   stores with aliasing, forward branches, loops, indirect jumps, and wrong-path "trap" code
   that must never commit.
5. **Configuration sweeps.** Tiny structures (ROB 4, IQ 2, SQ 2) force every full-queue stall
   path, and every predictor and memory feature is run in both settings.

Each feature was added incrementally and only kept once the full regression passed again.

Final regression on the current RTL, all passing:
- Icarus, 3,836 runs: all 7 predictors × 2 recovery modes × (24 directed + 250 random programs).
- Icarus, 8,192 runs: gshare and TAGE-lite × both recovery modes × ROB 4/16 × SQ 2/16 ×
  all 8 memory-feature combinations, on the directed tests plus 40 random programs.
- Verilator, 1,848 runs: all predictors × both recovery modes, plus IQ 2/16 × ROB 4/32 ×
  SQ 2/16, on the directed tests plus 60 random programs.

## Results

The full tables are in [`results/SUMMARY.md`](results/SUMMARY.md), and the raw data, with every
performance counter, is in the CSVs under `results/`. "Suite IPC" is total instructions /
total cycles over the 24 directed programs.

**Versus the phase-3 core.** The geometric-mean speedup is **1.60x** (range 1.22x - 1.95x) over
the 13 programs the phase-3 core runs correctly. For example, `course_test4` takes 185 cycles
instead of 361, and `bench_branch_patterns` takes 2185 instead of 3723. The phase-3 core never
halts on `flags_branches`, and on 10 other programs it halts with registers that differ from
the ISA model (see [below](#differences-from-the-phase-3-core)). Its cycle counts on those are
not comparable.

**Branch predictors** (suite IPC; the mispredict rate is for conditional branches):

| Predictor | Mispredict rate | IPC, recover at commit | IPC, recover at execute |
|---|---|---|---|
| static not-taken | 71.1% | 0.547 | 0.666 |
| BTFN | 27.9% | 0.702 | 0.765 |
| bimodal | 24.4% | 0.713 | 0.770 |
| gshare | 27.7% | 0.699 | 0.765 |
| tournament | 22.6% | 0.725 | 0.779 |
| perceptron | 18.8% | 0.743 | 0.788 |
| TAGE-lite | 19.0% | 0.740 | 0.786 |

- History-based predictors win wherever patterns repeat. For example, `bench_branch_patterns`
  drops from 273 bimodal mispredicts to about 105 with gshare or tournament.
- Perceptron and TAGE-lite are the best overall.
- Plain gshare loses to bimodal on these short programs, because its 10-bit history spreads
  each branch over many counters that each have to warm up.
- Recovering at execute instead of at commit is worth 0.05-0.12 IPC for every predictor.

**Window sizes.** With one instruction per cycle, the default ROB 16 / IQ 8 is already large
enough: average ROB occupancy is about 3, and 32 entries give no further gain. The store queue
matters most, since stores wait there until they drain to memory. At 2 entries, dispatch
stalls in 10% of cycles and IPC is 0.747; at 8 entries it is 0.786.

**Memory optimizations** (total cycles over the suite, relative to all three off):

| Optimization | Cycles saved |
|---|---|
| early restart only | 9.7% |
| next-line I prefetch only | 9.4% |
| early restart + I prefetch | 11.1% |
| all three | 11.1% |

The two help with the same problem, cold instruction misses, which is why they don't add up.
D prefetch removes about 16% of demand D-cache misses. Its prefetch refills compete with demand
refills for the single memory port, so overall it changes total cycles by less than 0.6% either
way on these programs.
Letting stores drain during a refill's last 4 cycles cut cycles stalled on a full store queue by
about half, about 1.5% of total cycles.

## Differences from the phase-3 core

The OoO core follows the ISA specification. The phase-3 core differs from it in a few places,
which is why some phase-3 runs above end with different register values:

- **Flags.** The phase-3 ALU keeps N and V in latches, so `XOR`, `SLL`, `SRA` and `ROR` leave
  stale N/V values from an earlier `ADD`/`SUB`. The specification (and this core) has these
  instructions write only Z.
- **Address arithmetic.** The phase-3 core computes `LW`/`SW` addresses with the saturating
  ALU adder. This core uses ordinary 16-bit wrap-around addition, as the golden model does.
- **RED.** Both cores, and the golden model, use the phase-3 RED semantics: each nibble pair is
  added into a 5-bit signed value, and the four results are summed and sign-extended.

Which of these bugs causes each individual phase-3 mismatch hasn't been traced.

The OoO core reuses the phase-3 arithmetic blocks (`Adder_ALU`, `Subtractor`, `XOR`, `RED`,
`PSA_16bit`, `Shifter_ALU`, CLA adders) and the course `memory4c` main memory. `memory4c.v` was
given a `+IMG=<file>` plusarg; it still defaults to `loadfile_test4.img`, so the phase-3 flow is
unchanged. The phase-3 `ALU.v` wrapper isn't used, because Verilator rejects its tristate
outputs.

## Limitations and possible next steps

- **Single-wide.** IPC can't exceed 1.0. The next big step would be a 2-wide fetch, rename and
  commit path.
- **Blocking loads.** A D-cache miss blocks younger loads (`cache_conflicts` runs at IPC 0.50).
  A small miss queue would allow hit-under-miss.
- **One refill at a time.** With early restart, fetch reaches the end of a line about when its
  refill finishes. The next-line prefetch then has no idle memory cycles left to start in.
  Overlapping two refills would fix this.
- **Indirect branches.** `BR` uses only the BTB (60% mispredicted in these tests). A
  return-address stack would catch `PCS`/`BR` call-return pairs.
- **Conservative disambiguation.** A load waits for every older store address. A store-set or
  similar dependence predictor could let it run earlier.
- **Self-modifying code isn't supported.** The I-cache isn't kept coherent with stores.
