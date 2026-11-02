# WISC-S25 Processor — Project Description

This document describes both processors in this repository, as they are implemented in the RTL:

1. **The five-stage pipelined core** (`project_working_directory/`): the ECE/CS 552 phase-3 design.
   It is a classic IF/ID/EX/MEM/WB pipeline with forwarding, branches resolved in decode, and
   2-way set-associative instruction and data caches.
2. **The out-of-order core** (`ooo_core/`): the same ISA and top-level interface, rebuilt around
   - a reorder buffer, register renaming and a unified issue queue;
   - a store queue with store-to-load forwarding;
   - a choice of seven branch predictors;
   - a memory system with critical-word-first refills and next-line prefetching.

Both cores run the same WISC-S25 programs. A Python golden model checks the out-of-order core
instruction by instruction. On the programs the five-stage core runs correctly, the out-of-order
core is 1.60x faster (geometric mean).

Diagrams are plain-text figures so they render on GitHub, in the editor, and in PDF exports.
Each figure has a short caption that says what to look at, then the surrounding text walks
through the same picture.

## Contents

- [Part 0 — The WISC-S25 ISA](#part-0--the-wisc-s25-isa)
- [Part I — The five-stage pipelined core](#part-i--the-five-stage-pipelined-core)
- [Part II — The out-of-order core](#part-ii--the-out-of-order-core)
- [Part III — Verification and tooling](#part-iii--verification-and-tooling)
- [Part IV — Results](#part-iv--results)
- [Part V — Side-by-side comparison](#part-v--side-by-side-comparison)
- [Appendix — File index](#appendix--file-index)

---

# Part 0 — The WISC-S25 ISA

## Programmer-visible state

| State | Description |
|---|---|
| `R0`–`R15` | 16 general-purpose 16-bit registers. `R0` always reads 0, and writes to it are discarded. |
| `Z`, `N`, `V` | Zero, negative and overflow flags. Only the compute instructions set them (see below). |
| `PC` | 16-bit byte address of the current instruction; instructions are 16 bits, so `PC` advances by 2. |
| Memory | 64 K × 16-bit words, byte-addressed (address bit 0 is ignored). Code and data share one address space. |

## Instruction formats

Every instruction is 16 bits. Bit 15 is on the left. The 4-bit opcode in `[15:12]` picks the
row; the remaining fields are the operands.

```text
  bit:     15          12 11          8 7           4 3           0
           +-------------+-------------+-------------+-------------+
  ALU rr   | opcode      | rd          | rs          | rt          |  ADD SUB XOR RED PADDSB
  shift    | opcode      | rd          | rs          | imm4        |  SLL SRA ROR  (amount 0..15)
  memory   | opcode      | rt          | rs          | off4        |  LW  rt <- M[addr]
           |             |             |             |             |  SW  M[addr] <- rt
           |             |             |             |             |  addr = (rs & ~1) + (off4 << 1)
  byte     | opcode      | rd          | imm8                      |  LLB / LHB  (also read rd)
           +-------------+------+------+---------------------------+
  B        | opcode      | cond | imm9                             |  PC <- PC+2+(imm9<<1)
  BR       | opcode      | cond |  x   | rs          | xxxx        |  PC <- rs
  PCS      | opcode      | rd          | xxxxxxxxxxxxxxxxx         |  rd <- PC+2
  HLT      | 1111        | xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx         |  stop
           +-------------+-----------------------------------------+
```

*Figure 0.1 — How to decode one word. Start at bits `[15:12]`, then read the matching row.*

## Instructions

| Opcode | Mnemonic | Operation | Flags written |
|---|---|---|---|
| `0000` | `ADD rd, rs, rt` | `rd = sat16(rs + rt)` (saturates to `0x7FFF` / `0x8000`) | Z N V |
| `0001` | `SUB rd, rs, rt` | `rd = sat16(rs - rt)` | Z N V |
| `0010` | `XOR rd, rs, rt` | `rd = rs ^ rt` | Z |
| `0011` | `RED rd, rs, rt` | reduction add (see [arithmetic notes](#arithmetic-notes)) | — |
| `0100` | `SLL rd, rs, imm4` | shift left logical | Z |
| `0101` | `SRA rd, rs, imm4` | shift right arithmetic | Z |
| `0110` | `ROR rd, rs, imm4` | rotate right | Z |
| `0111` | `PADDSB rd, rs, rt` | four independent 4-bit saturating adds (each clamped to −8..7) | — |
| `1000` | `LW rt, rs, off4` | `rt = M[(rs & 0xFFFE) + (sext(off4) << 1)]` | — |
| `1001` | `SW rt, rs, off4` | `M[(rs & 0xFFFE) + (sext(off4) << 1)] = rt` | — |
| `1010` | `LLB rd, imm8` | `rd = (rd & 0xFF00) \| imm8` | — |
| `1011` | `LHB rd, imm8` | `rd = (rd & 0x00FF) \| (imm8 << 8)` | — |
| `1100` | `B cond, label` | if `cond`: `PC = PC + 2 + (sext(imm9) << 1)` | — |
| `1101` | `BR cond, rs` | if `cond`: `PC = rs` | — |
| `1110` | `PCS rd` | `rd = PC + 2` (with `BR`, this forms call/return) | — |
| `1111` | `HLT` | stop; the PC no longer advances | — |

`LLB` and `LHB` keep half of the old `rd`, so they read `rd` as a source as well as writing it.

## Condition codes

| `cond` | Name | Taken when | Flags read |
|---|---|---|---|
| `000` | NEQ | Z = 0 | Z |
| `001` | EQ | Z = 1 | Z |
| `010` | GT | Z = 0 and N = 0 | Z, N |
| `011` | LT | N = 1 | N |
| `100` | GTE | Z = 1 or N = 0 | Z, N |
| `101` | LTE | N = 1 or Z = 1 | Z, N |
| `110` | OVFL | V = 1 | V |
| `111` | UNCOND | always | — |

## Arithmetic notes

These are the exact semantics both cores implement, since both use the same arithmetic modules,
and the golden model reproduces them.

- **Saturation.** `ADD` and `SUB` clamp to the signed 16-bit range, and V reports that saturation
  happened.
- **PADDSB.** Each 4-bit lane is added as two signed 4-bit numbers, and the result is clamped to
  `-8..7`.
- **RED** (as built by `RED.v`):

```text
  a[15:12] + b[15:12]   a[11:8] + b[11:8]   a[7:4] + b[7:4]   a[3:0] + b[3:0]
       unsigned 4+4          unsigned 4+4        unsigned 4+4      unsigned 4+4
       = 5-bit signed        = 5-bit signed      = 5-bit signed    = 5-bit signed
              \                    /                    \                /
               +------------------+                      +--------------+
                     8-bit sum                                8-bit sum
                            \                                  /
                             +--------------------------------+
                                        8-bit sum
                                   sign-extended to 16 bits
```

*Figure 0.2 — RED adder tree. Each nibble pair is added first; those four 5-bit signed
values are then reduced to one 16-bit result.*
- **Shifts** use the 4-bit immediate. `ROR` by 0 returns the input unchanged.

## Assembler conveniences

The project's assembler, `ooo_core/tools/wisc.py`, adds labels, comments (`//`, `#`, `;`),
directives `.org`, `.word` (a number or a label) and `.fill`, and these pseudo-ops:

| Pseudo-op | Expands to | Why |
|---|---|---|
| `NOP` | `PADDSB R0, R0, R0` | writes nothing and touches no flags |
| `MOV rd, rs` | `PADDSB rd, rs, R0` | a copy that does not change flags (rs + 0, so no lane can saturate) |
| `CMP rs, rt` | `SUB R0, rs, rt` | sets Z/N/V without writing a register |
| `LI rd, value` | `LLB rd, lo(value)` + `LHB rd, hi(value)` | load a 16-bit constant (labels allowed) |

---

# Part I — The five-stage pipelined core

Source: `project_working_directory/`. Top level: `cpu.v`. Testbench: `cpu_ptb` in
`project-phase3-testbench.v`.

## I.1 Overview

Walk left to right: one instruction occupies each box for one cycle, then moves to the next.

```text
          IF/ID              ID/EX              EX/MEM             MEM/WB
            |                  |                  |                  |
            v                  v                  v                  v
  +--------+    +--------+    +--------+    +--------+    +--------+
  |  IF    |--->|  ID    |--->|  EX    |--->|  MEM   |--->|  WB    |---> architectural
  | fetch  |    | decode |    | execute|    | memory |    | write  |    state
  | I-cache|    | RF read|    | ALU /  |    | D-cache|    | RF, ZNV|
  | PC + 2 |    | branch |    | LLB/LHB|    | LW, SW |    | hlt    |
  +--------+    +--------+    +--------+    +--------+    +--------+
       ^             |              ^              ^            |
       |             |              |              |            |
       |        taken branch        |         store data        |
       |        redirects PC        |         from WB           |
       |        and flushes IF      |              |            |
       +----------------------------+              |            |
                                    forwarding     |            |
                                    (next figure)  +------------+
```

*Figure I.1 — Five-stage pipeline. Branches are decided in ID (predict not-taken). A taken
branch sends a new PC back to IF and kills the instruction already fetched behind it.*

| If this happens | What the pipeline does |
|---|---|
| I-cache miss | PC holds. IF injects `0xE000` (`PCS R0`, a no-op) into ID. |
| D-cache miss | Every pipeline register holds. The whole pipeline freezes. |
| Taken branch in ID | PC becomes the target. The IF/ID register is cleared (one bubble). |
| `HLT` in ID–WB | PC stops advancing so earlier instructions can finish. |

**Register naming in `cpu.v`.** Signals are named after the pipeline register they come out of.
For example, `ID_EX_*` is the decode stage's logic, which feeds the ID/EX register. In stage terms:

| Stage | Signal prefix in `cpu.v` | What happens there |
|---|---|---|
| IF | `IF_ID_*` | PC, I-cache read, PC + 2 |
| ID | `ID_EX_*` | decode, register read, branch resolution, hazard detection |
| EX | `EX_MEM_*` | forwarding muxes, ALU, LLB/LHB byte merge, address generation |
| MEM | `MEM_WB_*` | D-cache access, store-data forwarding |
| WB | `WB_*` | register-file write, flag write, `hlt` |

## I.2 Stage by stage

**IF.** The PC register is built from 16 `dff`s. `CLA_16b` computes `PC + 2`. The I-cache is read
combinationally. The PC holds when:
- a data or flag hazard stalls decode;
- the D-cache or I-cache is missing;
- an `HLT` is anywhere in ID through WB.

On an I-cache miss, IF sends `0xE000` (`PCS R0`, which has no effect) into the IF/ID register
instead of the instruction.

**ID.** `ControlSignal` (`controlsignal.v`) decodes the opcode. Its control signals:

| Opcode | RegWrite | ALUSrc | MemRead / MemWrite | MemtoReg | other |
|---|---|---|---|---|---|
| ADD, SUB, XOR, RED, PADDSB | 1 | 0 | – | 0 | ALUOp = op |
| SLL, SRA, ROR | 1 | 1 (imm4) | – | 0 | ALUOp = op |
| LW | 1 | 1 | Read | 1 | `DMEM_en`, ALUOp = ADD (address) |
| SW | 0 | 1 | Write | – | `DMEM_en`, `RegSel_rt` (data register = bits 11:8) |
| LLB / LHB | 1 | – | – | 0 | `LB_result_sel`, `RegSel_rs` (read rd), `LB_mode` = low/high |
| B / BR | 0 | – | – | – | `Branch`; BR also `bLabel_sel` (target from register) |
| PCS | 1 | – | – | – | `PC_save` (write PC + 2) |
| HLT | 0 | – | – | – | `Hlt` |

The register file has two read ports. `pc_control.v` evaluates the condition code against the
flags and produces the next PC:
- If the branch is not taken, the next PC is PC + 2.
- A taken `B` goes to `PC + 2 + (imm9 << 1)`.
- A taken `BR` goes to `Rs`.

The policy is predict not-taken. A taken branch resets the IF/ID register, which squashes the one
instruction fetched behind it, and redirects the PC. A taken branch therefore costs one bubble.

**EX.** Each ALU operand is chosen by a forwarding mux. Read this figure from the right: the
newest result that writes the needed register wins.

```text
  sources for one ALU operand (priority: newest first)

     EX/MEM result  ---- EX -> EX ----+
     (instr that was in EX last cycle)|
                                      v
     MEM/WB result  ---- MEM -> EX -->+--> operand mux --> ALU / address add
     (instr that was in MEM last cycle)
                                      ^
     value from ID/EX  ---------------+
     (no hazard; use the RF read)
```

*Figure I.2 — Operand forwarding into EX. The same mux exists for both ALU inputs.*

The ALU (`ALU.v`) selects one of the arithmetic units (`ALUOp`). For loads and stores, the base is
masked with `0xFFFE` and the offset shifted left by 1, and the ALU's ADD computes the address.
`LLB`/`LHB` bypass the ALU: a byte-merge path keeps one half of `rd` and inserts `imm8`.

**MEM.** LW/SW access the D-cache. If the store's data register is written by a load that is
in WB this cycle, the data is forwarded from WB (*MEM→MEM* forwarding).

**WB.** The write-back value is `PC+2` for PCS, the loaded word for LW, and the EX result
otherwise. Three `dff`s hold Z, N and V. They are written by ADD, SUB, XOR, SLL, SRA and ROR,
selected in hardware as opcodes with `op[3] = 0` and `op[1:0] != 11`. `hlt` is the HLT flag in WB.

## I.3 Hazards

Three kinds of problem, three kinds of fix: forward a value, stall a stage, or squash a fetch.

**Data hazards** (a later instruction needs a register an earlier one is still producing):

| Situation | How it is detected | Fix |
|---|---|---|
| ALU result needed by the next instruction | rd in MEM = source in EX | EX/MEM → EX forwarding |
| Result two instructions back | rd in WB = source in EX | MEM/WB → EX forwarding |
| Result being written this cycle | WB writes the register ID is reading | RF write-before-read bypass |
| Load, then a dependent ALU op | load in EX, its rd = a source in ID | stall IF/ID one cycle, then forward |
| Load, then a store of that value | load in WB, store in MEM, same rt | MEM/WB → MEM forwarding (no stall) |

**Control hazards** (a branch's outcome or target is not ready yet):

| Situation | How it is detected | Fix |
|---|---|---|
| Branch needs flags still in EX or MEM | flag-setting op in EX/MEM, condition uses that flag | stall the branch in ID |
| Branch needs flags being written now | flag-setting op in WB | flag bypass WB → ID |
| `BR` needs a register still in EX or MEM | Rs = rd of the instruction in EX or MEM | stall in ID |
| Taken branch | resolved in ID | flush the one fetched instruction (1 bubble) |

**Memory stalls:**

| Situation | Signal | Fix |
|---|---|---|
| I-cache miss | `instr_miss_stall` | hold PC, send a NOP into ID |
| D-cache miss | `data_miss_stall` | freeze every pipeline register |

Pipeline timing. Each column is a clock cycle. Follow one instruction across a row.

```text
  ALU -> ALU  (no stall; EX/MEM forwards R1 into the SUB in cycle 4)
                 c1    c2    c3    c4    c5    c6
  ADD R1,R2,R3   IF    ID    EX    MEM   WB
  SUB R4,R1,R5         IF    ID    EX    MEM   WB
                                   ^
                                   R1 from EX/MEM

  Load-use  (one stall; MEM/WB then forwards R1 into the ADD in cycle 5)
                 c1    c2    c3    c4    c5    c6    c7
  LW  R1,R2,0    IF    ID    EX    MEM   WB
  ADD R4,R1,R5         IF    ID    ID    EX    MEM   WB
                                   stall ^
                                         R1 from MEM/WB

  Branch waits for flags  (stalls in ID until SUB reaches WB)
                 c1    c2    c3    c4    c5    c6
  SUB R0,R1,R2   IF    ID    EX    MEM   WB
  B   EQ, tgt          IF    ID    ID    ID    EX ...
  fall-through               IF    IF    IF    (flushed if taken)
                                   stall stall
                                         flags from WB
```

*Figure I.3 — Three hazard cases. A stall repeats a stage name; a flush drops the fall-through.*

## I.4 Arithmetic units

All arithmetic is built structurally from carry-lookahead adders. The out-of-order core reuses
these same modules.

| Module | Function |
|---|---|
| `CLA_4b.v` | 4-bit carry-lookahead adder with P/G outputs and signed-overflow detection |
| `CLA_16b.v` | 16-bit adder from four `CLA_4b`s plus a second-level lookahead unit; used for the ALU, PC + 2, branch targets and the miss handler's address counter |
| `Adder_ALU.v` | saturating 16-bit add: on overflow, the result is `0x7FFF` (positive) or `0x8000` (negative) |
| `Subtractor.v` | saturating 16-bit subtract (`a + ~b + 1`) |
| `XOR.v` | bitwise XOR, Z only |
| `PSA_16bit.v` | PADDSB: four `CLA_4b`s with per-lane saturation |
| `RED.v` | three-level adder tree (4 × 4-bit, 2 × 8-bit, 1 × 8-bit), sign-extended |
| `Shifter.v` | SLL / SRA as a 2-level shifter (shift by 0–3, then by 0/4/8/12) |
| `Rotater.v` | ROR built the same way |
| `Shifter_ALU.v` | selects shift vs rotate by `mode` |
| `ALU.v` | instantiates all of the above and multiplexes the result and flags by `ALUOp` |

## I.5 Register file

`register_file.v` builds 16 registers out of `BitCell`s (`bit_cell.v`). Each cell has one
write port and two read bitlines, and the read ports are driven through tri-state bitlines
selected by one-hot decoders (`read_decoder_4_16.v`, `write_decoder_4_16.v`). Reads of `R0`
return 0. When WB writes the register that ID is reading in the same cycle, the new value is
passed straight through (write-before-read). Writes are suppressed while the D-cache is
missing.

## I.6 Memory hierarchy

Two caches, one miss handler, one main-memory port. Follow a miss downward; follow a store-hit
sideways.

```text
  IF: PC ------------------+                              +--> instruction --> ID
                           v                              |
                      +----------+                        |
                      | I-cache  |-- hit -----------------+
                      | 2 KB     |
                      +----+-----+
                           | miss
                           v
                      +----------+     +------------------+     +-------------+
                      | bridge   |---->| miss handler     |---->| memory4c    |
                      | I first, |     | 8-word burst     |     | 64K x 16    |
                      | then D   |     | start of line    |     | 4-cycle rd  |
                      +----+-----+     +------------------+     +------+------+
                           | miss                                      ^
                           v                                           | SW hit:
                      +----------+                                     | write-through
                      | D-cache  |-- hit: LW data --> MEM              |
                      | 2 KB     |-- hit: SW data ---------------------+
                      | WT, WA   |
                      +----------+
                           ^
  MEM: addr, store data ---+
```

*Figure I.4 — Unified memory. Both caches miss through the same handler. A store that hits
writes the D-cache and main memory in the same cycle.*

**Cache organisation.** The I-cache and D-cache have the same structure: 2 KB, 2-way
set-associative, 64 sets, 16-byte lines of eight 16-bit words.

```text
  address bit:  15              10  9              4  3     1  0
                +----------------+--+--------------+--+-----+--+
                | tag (6)        |  | set (6)      |  | word|  |  always 0 (16-bit words)
                +----------------+--+--------------+--+-----+--+
                       |                |               |
                       |                v               v
                       |          64 sets            8 words / line
                       v
                compare against both ways' tags; valid+match = hit
                miss: pick invalid way, else the LRU way
```

*Figure I.5 — Cache address split. Set index `[9:4]` picks the row; tag `[15:10]` picks the way.*

- `MetaDataArray.v` holds one byte per way and set: `{tag[5:0], valid, LRU}`.
- `DataArray.v` holds 64 blocks × 8 words of `dff` cells.
- The set and word are selected one-hot by `decoder_6_64.v` and `decoder_3_8.v`.
- A hit needs a valid way with a matching tag.
- On a miss, the victim way is chosen from the LRU bits.
- A shift register steps the word-enable through the 8 words as refill data arrives, and the tag
  is written when the line is complete.

**D-cache write policy.** The D-cache is write-through and write-allocate. A store hit writes the
cache word and main memory in the same cycle. A store miss first refills the line, then writes.

**Miss handler** (`cache_miss_handler.v`). A 12-bit shift register tracks one refill:

```text
  cycle after first read issued
                   0    1    2    3    4    5    6    7    8    9   10   11
  issue a read:   w0   w1   w2   w3   w4   w5   w6   w7
  word returns:                       w0   w1   w2   w3   w4   w5   w6   w7
  write into $:                       w0   w1   w2   w3   w4   w5   w6   w7
  tag + valid:                                                                X
```

*Figure I.6 — One line refill. Memory is pipelined, so eight reads can be in flight; each word
comes back four cycles after it was requested. The line is usable only after the tag write.*

The refill starts at the beginning of the line (`addr & 0xFFF0`). Counting the cycle in which the
miss is detected, the pipeline stalls for about 13 cycles per miss.

**Arbitration** (`cache_memory_bridge.v`). One handler serves both caches. If both miss at once,
the I-cache is served first, and the D-cache miss waits until no instruction refill is in flight.

**Main memory** (`memory4c.v`, course-provided):
- 64 K × 16-bit words.
- Writes take 1 cycle; reads take 4 cycles, pipelined, so one read can be issued per cycle.
- At reset it loads the image named by the `+IMG=<file>` plusarg, defaulting to
  `loadfile_test4.img`.

## I.7 Testbench and outputs

`project-phase3-testbench.v` (`cpu_ptb`) uses a 100-time-unit clock and holds reset for 201
units. It writes:
- `verilogsim.plog`: per-cycle PC, instruction, register and memory activity, plus a summary;
- `verilogsim.ptrace`: an architectural trace of `REG`, `LOAD` and `STORE` events;
- `dump.vcd`: a waveform.

The summary reports `sim_cycles`, `inst_count` and the I-/D-cache hit and request counts. Saved
reference runs:

| Test | Cycles | Instructions | I-cache hits / requests | D-cache hits / requests |
|---|---:|---:|---:|---:|
| TEST1 | 44 | 38 | 10 / 12 | 0 / 0 |
| TEST2 | 54 | 47 | 11 / 13 | 1 / 2 |
| TEST3 | 55 | 45 | 20 / 22 | 0 / 0 |
| TEST4 | 365 | 242 | 170 / 176 | 30 / 32 |

The testbench's `inst_count` also counts cache-refill activity, so it overstates the number of
instructions. For the IPC comparisons in Part IV, the instruction count comes from the golden
model instead.

## I.8 Where the five-stage core differs from the ISA

These came up while cross-checking against the golden model:

- **N and V after XOR and the shifts.** The flag registers are written for XOR, SLL, SRA and ROR
  as well as ADD/SUB. But `ALU.v` doesn't assign `ovfl`/`sign` for those operations, so those
  outputs hold their last values (a latch). The stale N/V can come from any earlier ADD-type
  operation, including a load or store's address add. The ISA says these instructions write
  only Z.
- **Address arithmetic.** LW/SW addresses go through the saturating `Adder_ALU`, so a base +
  offset that crosses `0x7FFF`/`0x8000` saturates instead of wrapping.

Because of these, the five-stage core ends with different register values on some of the newer
test programs, and it never halts on `flags_branches`. Which deviation causes each mismatch
hasn't been traced.

---

# Part II — The out-of-order core

Source: `ooo_core/rtl/`. Top level: `cpu.v`, with the same ports as the five-stage core:
`cpu(clk, rst_n, hlt, pc)`.

## II.1 Design goals

- **Out-of-order execution** with precise state: instructions run as soon as their operands are
  ready and retire in program order through a reorder buffer.
- **Register renaming** of R1–R15 and the flags, which removes WAR and WAW hazards.
- **Better branch prediction** than predict-not-taken: bimodal, gshare, tournament, perceptron
  and TAGE-lite, selectable by a parameter.
- **Single-wide**: fetch, dispatch and commit handle one instruction per cycle (a deliberate
  choice to avoid wide fetch). Several functional units can still issue in the same cycle.
- **Reuse**: the phase-3 arithmetic blocks and the course `memory4c` main memory are used
  unchanged.
- **Measurable**: every optimization is a parameter, so it can be turned off and compared.

## II.2 How an instruction moves through the core

Six steps. Fetch, rename and commit are in-order and one-wide. Issue and execute are out of
order, and up to four units can fire in the same cycle.

```text
  1. FETCH                2. RENAME               3. ISSUE
  I-cache + predictor     decoder + map table     oldest ready instr
  one instr / cycle       one instr / cycle       per FU class
  into 4-entry IFQ        into ROB, IQ, SQ        (ALU, BRU, LDU, STU)
         |                         |                       |
         v                         v                       v
  4. EXECUTE              5. WRITE-BACK           6. COMMIT
  ALU / BRU / LDU / STU   CDB A: ALU + flags      ROB head, if done
  one cycle each          CDB B: load value       writes ARF / flags
         |                         |              trains predictor
         |                         |              drains committed stores
         +---- wakeup IQ ----------+
         +---- mark ROB done ------+
         +---- BRU may recover ----+
```

*Figure II.1 — Instruction lifetime. Independent instructions can pass each other in step 3–4;
step 6 puts them back into program order.*

Where those steps live in the RTL:

```text
  fetch_pc --> I-cache --> predictor --> IFQ --1/cycle--> decode / rename / dispatch
     ^           |                                         |         |          |
     |           | miss                                    |         |          | SW
     |           v                                         v         v          v
     |      mem_system                                  ROB(16)   IQ(8)      SQ(8)
     |      + I/D $                                     commit       |          |
     |                                                  ARF, map     |          |
     |                                                       ^       v          v
     |                                                       |    ALU  BRU   LDU  STU
     |                                  recovery <-----------+     |    |     |    |
     |                                  (squash younger)           |    |     |    |
     +----- redirect PC, GHR --------------------------------------+    |     |    |
                                                                        v     v    v
                                                                     CDB A  CDB B  drain
                                                                     (ALU)  (load) to D$
```

*Figure II.2 — Block diagram. The left column is fetch and memory; the middle is rename and
commit; the right is issue and execute.*

## II.3 Pipeline timing

Each box is one clock cycle. This is the shortest path (ALU, operands already ready):

```text
  cycle      0              1                 2                  3               4
         +--------+    +----------+    +---------------+    +---------+    +--------+
         | FETCH  |    | DECODE   |    | SELECT+EXECUTE|    |  CDB    |    | COMMIT |
         | I-cache|    | rename   |    | IQ pick + ALU |    | wakeup  |    | ROB    |
         | predict|    | dispatch |    |               |    | ROB done|    | head   |
         | -> IFQ |    | -> ROB IQ|    |               |    |         |    |        |
         +--------+    +----------+    +---------------+    +---------+    +--------+
```

*Figure II.3 — Best-case ALU path. A dependent ALU can issue in the cycle after its producer
because the CDB is bypassed into IQ select.*

| Event | Latency |
|---|---|
| Dependent ALU → ALU | back-to-back. The result bus is bypassed into select, so the consumer issues the cycle after the producer. |
| Load hit → consumer | the same as ALU: the D-cache is read in the issue cycle. |
| Load miss → missed word arrives | 4 cycles after the refill starts with early restart (the critical word is read first); without it, the load waits for the whole line (the last word arrives 11 cycles after the start). |
| Correctly predicted taken branch | no bubble (the next PC is chosen in the fetch cycle). |
| Mispredicted branch (early recovery) | at least 2 lost fetch cycles, plus however long the branch waits in the IQ for its flags or register. |
| Mispredicted branch (commit recovery) | the branch must first reach the ROB head and retire. |

## II.4 Front end (`frontend.v`)

Each cycle the front end does the following:

1. **Read** the I-cache at `fetch_pc`. On a miss, it raises `i_miss_req` and fetches nothing.
2. **Predecode** the instruction bits and choose the next PC in the same cycle:

```text
  fetched word
       |
       +-- HLT? ------------ yes --> stop fetching until a redirect
       |
       +-- B UNCOND? ------- yes --> next PC = PC+2+(imm9<<1)     always taken
       |
       +-- B cond? --------- yes --> direction predictor
       |                                taken  --> PC+2+(imm9<<1)
       |                                not    --> PC+2
       |
       +-- BR? ------------- yes --> direction predictor (if cond)
       |                                and BTB hit?
       |                                yes --> next PC = BTB target
       |                                no  --> PC+2
       |
       +-- anything else --------------> PC+2
```

*Figure II.4 — Next-PC decision in the fetch cycle. A correctly predicted taken `B` costs no
bubble because the target is known from the instruction bits.*

   | Instruction | Predicted next PC |
   |---|---|
   | `B UNCOND` | always `PC + 2 + (imm9 << 1)` |
   | conditional `B` | that target if the direction predictor says taken, else PC + 2 |
   | `BR` | BTB target if the BTB hits and (unconditional, or predicted taken); else PC + 2 |
   | `HLT` | fetch stops (`stopped`) until a redirect |
   | anything else | PC + 2 |

3. **Update the GHR** speculatively. Every conditional branch shifts its predicted direction into
   the 16-bit global history register. Bit 0 is the newest.

```text
  GHR before this branch (saved in the IFQ / ROB):   h15 ... h1  h0
  predicted taken = 1:
  GHR after:                                         h14 ... h0   1
                                                     newest ----------------^

  On a mispredict the back end restores:
      GHR <- {saved snapshot, actual taken bit}
  so later predictions see the real history, not the wrong-path guess.
```

*Figure II.5 — Speculative GHR. The snapshot travels with the branch so recovery can repair it.*

4. **Enqueue** `{pc, instr, predicted next PC, GHR before this branch}` into the 4-entry
   instruction fetch queue (IFQ). Fetch stalls when the IFQ is full.

On a **redirect** from the back end, `fetch_pc` and the GHR are overwritten, the IFQ is cleared,
and `stopped` is released.

## II.5 Branch prediction

All direction predictors share one interface:
- a combinational lookup with the fetch PC and the speculative GHR;
- training at commit, using the GHR snapshot the branch was predicted with, carried in its ROB
  entry.

Training at commit means wrong-path branches never pollute the tables. `BP_TYPE` selects the
predictor:

| `BP_TYPE` | Predictor | Storage | Index / logic |
|---|---|---|---|
| 0 | static not-taken | – | never taken |
| 1 | BTFN | – | taken if the offset is negative (backward loop branch) |
| 2 | bimodal | 1024 × 2-bit | `PC[10:1]` |
| 3 | gshare | 1024 × 2-bit | `PC[10:1] XOR GHR[9:0]` |
| 4 | tournament | gshare 1024 × 2b + local history 64 × 10b + local PHT 1024 × 3b + chooser 1024 × 2b | the chooser (indexed by `GHR[9:0]`) picks global or local |
| 5 | perceptron | 32 perceptrons × 13 weights × 8-bit | `PC[5:1]`; predict taken when y ≥ 0 |
| 6 | **TAGE-lite** (default) | base 512 × 2b + 3 tagged tables × 128 entries | geometric histories of 4, 8 and 16 bits |

**Tournament** (Alpha 21264 style). Two experts, plus a chooser that learns which expert to trust:

```text
  PC, GHR --> gshare PHT [PC XOR GHR] ---- global guess --+
                                                          |     chooser[GHR]
  PC -------> local history[PC] --> local PHT             +--> picks one --> prediction
                              local guess ----------------+

  At commit: train both PHTs. If they disagreed, move the chooser toward the one that was right.
```

*Figure II.6 — Tournament predictor. The chooser is indexed by global history, not by PC.*

**Perceptron** (Jiménez & Lin). One weight per recent branch, plus a bias:

```text
  y = w0 + (GHR[0] ? +w1 : -w1) + ... + (GHR[11] ? +w12 : -w12)

  y >= 0  --> predict taken
  y <  0  --> predict not-taken

  Train at commit if the guess was wrong, or if |y| was smaller than theta (37):
      bump w0 toward the outcome
      bump w[i+1] up if GHR[i] matched the outcome, down otherwise
```

*Figure II.7 — Perceptron. `PC[5:1]` selects which of 32 perceptrons to use.*

**TAGE-lite** (Seznec). Longer history tables override shorter ones when their tag matches:

```text
  PC              --> base bimodal (512 x 2-bit)     always a guess
  PC, GHR[3:0]    --> T1  128 entries, tag+counter+u    hit?
  PC, GHR[7:0]    --> T2  128 entries                   hit?
  PC, GHR[15:0]   --> T3  128 entries                   hit?

  provider = the hitting table with the longest history (else the base)
  alternate = the next-shorter hit (used to train the useful bit)

  index = PC[7:1] XOR PC[14:8] XOR folded history
  tag   = PC[8:1] XOR folded history (different fold)
```

*Figure II.8 — TAGE-lite lookup. Walk T3, T2, T1, then the base; the first tag match wins.*

TAGE-lite updates at commit as follows:
1. **Provider.** The provider's counter moves toward the outcome. If no tagged table hit, the base
   counter moves instead.
2. **Usefulness.** If the provider and the alternate prediction (the next shorter hit, or the
   base) disagreed, the provider's `u` goes up when it was right and down when it was wrong.
3. **Allocation.** On a misprediction, one entry is allocated in the shortest longer-history table
   whose `u` is 0. Its counter starts weak, in the actual direction. If no such entry exists,
   `u` is decremented in all longer candidates instead.

**BTB** (`btb` in `branch_predictor.v`):
- 16 entries, direct-mapped: index `PC[4:1]`, tag `PC[15:5]`.
- It stores targets for `BR` only, since `B` targets come from the instruction bits.
- Each taken `BR` writes it at commit.

## II.6 Decode, rename and dispatch

**Decoder** (`decoder.v`). For each opcode: which unit runs it, what it reads, what it writes,
and whether it even needs the issue queue.

Compute:

| Instruction | Unit | Reads | Writes | IQ? |
|---|---|---|---|---|
| ADD, SUB | ALU | rs, rt | rd, Z, NV | yes |
| XOR | ALU | rs, rt | rd, Z | yes |
| RED, PADDSB | ALU | rs, rt | rd | yes |
| SLL, SRA, ROR | ALU | rs | rd, Z | yes |
| LLB, LHB | ALU | rd | rd | yes |

Memory and control:

| Instruction | Unit | Reads | Writes | IQ? |
|---|---|---|---|---|
| LW | LDU | rs (base) | rt | yes |
| SW | STU | rs (base), rt (data, bits 11:8) | memory | yes |
| B cond | BRU | flags for that condition | – | yes |
| B UNCOND | – | – | – | no (fetch already followed it) |
| BR | BRU | rs (target), flags if cond | – | yes |
| PCS | – | – | rd = PC + 2 | no (value known at dispatch) |
| HLT | – | – | – | no |

In addition, an ALU instruction with no architectural effect (`rd = R0` and no flags written,
for example the `PADDSB R0,R0,R0` NOP) is completed at dispatch and never occupies the IQ.

**Flag renaming.** Z and N+V are renamed as two extra "registers". XOR and the shifts write
only Z, so a later branch on N doesn't have to wait for them.

**Map table and operand read** (`rob.v`). Each of R1–R15, plus Z and NV, has a `busy` bit and the
ROB tag of its youngest in-flight producer. For each source, walk this list top to bottom and
stop at the first match:

```text
  source register (or Z / NV)
           |
           +-- R0, or map.busy = 0? ---- yes --> ARF value          ready
           |
           +-- producer ROB entry done?  yes --> ROB value          ready
           |
           +-- producer on CDB A or B?   yes --> CDB value          ready
           |
           +-- otherwise ----------------------> wait for that tag  not ready
```

*Figure II.9 — Operand lookup at dispatch. The destination's map entry is then pointed at the
new ROB slot.*

The destination's map entry is then pointed at the new ROB entry.

**Dispatch stalls.** One instruction dispatches per cycle unless one of these holds:
- the ROB is full;
- the instruction needs the IQ and the IQ is full;
- it is a store and the store queue is full;
- a recovery is happening this cycle;
- an `HLT` has committed.

## II.7 Reorder buffer (`rob.v`)

The ROB is a 16-entry circular buffer (`ROB_W = 4`). Each entry holds:

| Field | Purpose |
|---|---|
| `done` | result is available, so the entry can commit |
| `val`, `z`, `n`, `v` | result value and flags |
| `wr_rd`, `rd`, `wr_z`, `wr_nv` | what to write into the ARF at commit |
| `pc`, `instr` | for the commit trace and predictor training |
| `is_store`, `is_cond`, `is_brr`, `is_halt` | instruction class |
| `taken`, `npc`, `mispred` | branch outcome, written by the BRU |
| `ghr` | GHR snapshot (predictor training, history repair) |
| `sqp` | store-queue tail at dispatch (store-queue repair) |

**Commit.** One instruction per cycle, when the head is `done`. Commit:
- writes the ARF and flag registers;
- clears map entries that still point at this ROB entry;
- trains the predictor or BTB;
- marks stores committed in the store queue.

**Recovery** squashes every entry younger than the branch (`rec_tag`). Age is
`(tag − head) mod 16`. Walk the picture left to right: everything to the right of the branch is
wrong-path.

```text
  before:   [ older ... ] [ BRANCH ] [ younger ] [ younger ] [ younger ]
            ^ head        ^ rec_tag                              ^ tail

  after:    [ older ... ] [ BRANCH ]
            ^ head        ^ rec_tag
                          ^ new tail = rec_tag + 1

  map table: scan surviving entries from head to rec_tag;
             each register's tag becomes the youngest writer that is still alive
```

*Figure II.10 — ROB after a mispredict. No per-branch map checkpoints: the map is rebuilt from
the entries that remain.*

## II.8 Issue queue (`issue_queue.v`)

The issue queue is unified, has 8 entries (`IQ_N`), and uses **data capture**: each entry holds
operand values, not only tags. Each entry has:
- `fu`, `tag` (ROB index), `instr`, `pc`, `pred_npc`, `sqp`;
- four sources, `s1`, `s2`, `z` and `nv`, each with a `ready` bit, the producer `tag` and a
  captured `value`.

```text
  every cycle, for each IQ entry:

    1. WAKEUP     CDB A (ALU value + Z,N,V)  --+--> if tag matches a waiting source,
                  CDB B (load value)         --+    capture the value and set ready
                                                (also used combinationally this cycle)

    2. READY      all four sources ready (or arriving on a CDB now)
                  and, if this is a load: LDU free and no older store still has an unknown address

    3. SELECT     for ALU, for BRU, for LDU, for STU:
                    among ready entries of that class, pick the smallest age
                  up to four instructions issue; those IQ slots are freed
```

*Figure II.11 — Issue-queue cycle. Age is distance from the ROB head, so older work goes first.*

- **Select is oldest-first per class.** Age is the distance from the ROB head, so older
  instructions on the critical path go first.
- **Recovery** clears every entry younger than the mispredicted branch.

## II.9 Execution units

| Unit | Module | Work | Where the result goes |
|---|---|---|---|
| ALU | `alu_unit` | ADD/SUB/XOR/RED/PADDSB/shifts plus LLB/LHB, using the phase-3 arithmetic blocks. Z = (result == 0), N = result[15], V = add/sub overflow | CDB A next cycle |
| BRU | `branch_unit` | evaluate the condition, compute the real next PC, compare with the prediction | ROB (taken, npc, mispredict); may start recovery |
| AGU | in `cpu.v` | `(base & 0xFFFE) + (sext(off4) << 1)`, wrap-around add | LDU / STU this cycle |
| LDU | `lsu.v` | SQ forwarding or D-cache read | CDB B next cycle |
| STU | `lsu.v` | write address and data into the store's SQ entry | ROB marked done |

Each unit takes one cycle. The ALU's flags are always computed; the ROB only commits the ones
the instruction writes.

## II.10 Load/store unit (`lsu.v`)

**Store queue** (8 entries, `SQ_W = 3`). Pointers carry an extra wrap bit so full and empty are
distinct. A store walks from right to left as it ages:

```text
  sq_head                 sq_cmt                      sq_tail
     |                       |                           |
     v                       v                           v
  [ committed, waiting ]  [ speculative stores ]  [ free ... ]
    drain to D-cache        squashed on recovery
    and memory              (tail <- branch's saved sqp)

  four steps, in order:
    1. ALLOCATED at dispatch                         (tail advances)
    2. RESOLVED when STU writes addr and data
    3. COMMITTED when the store retires from the ROB (cmt advances)
    4. DRAINED: written to D-cache and memory        (head advances)
```

*Figure II.12 — Store-queue lifetime. Drain needs a D-cache hit and a free memory port. A drain
miss refills the line (write-allocate) and retries.*

**Loads.** The IQ only issues a load once every older store has an address, so the load can
compare against the queue safely:

```text
  load issues from IQ
        |
        v
  older store to the same word? -- yes --> forward youngest match --+
        | no                                                        |
        v                                                           v
  D-cache hit (including words     -- yes --> cache data -----------+--> CDB B next cycle
  already written during a refill)
        | no
        v
  hold in the pending-load register
  request a refill; block younger loads
        |
        +---- retry when the missed word arrives
```

*Figure II.13 — Load path. Forwarding uses the store queue; a miss occupies the load unit until
the line (or, with early restart, the missed word) is back.*

- **Memory disambiguation is conservative.** A load waits until every older store's address is
  known. It can then safely go ahead of older stores to other addresses (load bypassing), and it
  takes its data from an older store to the same word (load forwarding).
- A pending load that a recovery squashes is dropped.
- `hlt` rises only once `HLT` has committed **and** the store queue has drained, so memory is
  complete when the testbench stops.

## II.11 Branch recovery

`EARLY_RECOVERY = 1` (default) recovers in the cycle the BRU sees `actual next PC != predicted`.
Everything listed here happens in that same cycle:

```text
  BRU:  mispredict
    |
    +--> ROB     rec_tag = branch tag
    |            new tail = rec_tag + 1          (drop younger ROB entries)
    |            rebuild map from surviving entries
    |
    +--> IQ      drop entries younger than the branch
    |
    +--> SQ      tail = the branch's saved sqp   (drop younger stores)
    |
    +--> fetch   PC  = actual next PC
                 GHR = {snapshot from the branch, actual taken bit}
                 clear the IFQ
                 start correct-path fetch next cycle
```

*Figure II.14 — Early recovery. Same actions with `EARLY_RECOVERY = 0`, but they wait until the
branch is the ROB head.*

With `EARLY_RECOVERY = 0` the same squash happens only when the branch reaches the ROB head.
That is simpler (everything younger is already known to be wrong-path) but slower.

## II.12 Memory system (`cache.v`, `mem_system.v`)

**Caches.** The I-cache and D-cache keep the phase-3 geometry: 2 KB, 2-way, 64 sets, 8-word lines,
tag bits [15:10], set bits [9:4]. One LRU bit per set gives true LRU for 2 ways.

- *Read port*: a combinational lookup, used for fetch and loads.
- *Write port*: a store-drain word write on a hit.
- *Probe port*: a lookup only, so the prefetchers can skip lines that are already present.
- *Refill*: at `fill_start`, the victim (an invalid way, otherwise the LRU way) is chosen and
  invalidated. Words are written as they arrive, and the line becomes valid at `fill_done`.

**Refill engine.** One engine serves both caches. The memory port does at most one operation per
cycle. Highest number that is ready wins:

| Priority | Operation | When |
|---|---|---|
| 1 (highest) | D-cache demand miss | a load is waiting, or a store is draining to a missing line |
| 2 | I-cache demand miss | fetch missed |
| 3 | store write-through | also allowed once a refill has issued all 8 reads |
| 4 | I-cache next-line prefetch | line after the one being fetched, absent, memory idle |
| 5 (lowest) | D-cache next-line prefetch | line after the last D demand miss, absent, memory idle |

A refill issues 8 back-to-back word reads. With `EARLY_RESTART`, it starts at the missed word
(here word 5 of the line) and wraps around:

```text
  cycle            0    1    2    3    4    5    6    7    8    9   10   11
  issue read      w5   w6   w7   w0   w1   w2   w3   w4
  word arrives                        w5   w6   w7   w0   w1   w2   w3   w4
  load of w5                          ^ hits next cycle
  stores may use port:                               ^ all 8 reads already issued

  without EARLY_RESTART the reads are w0..w7 in order, and the load waits until
  the whole line is valid (last word arrives in cycle 11).
```

*Figure II.15 — Critical-word-first refill. The requester uses each word as soon as it arrives;
stores share the port on the refill's tail.*

| Feature | Parameter | Effect |
|---|---|---|
| Critical-word-first + early restart | `EARLY_RESTART` | A demand refill starts with the missing word, and the cache returns any word that has already arrived. |
| Next-line instruction prefetch | `I_PREFETCH` | While fetching from line L, line L+1 is refilled if it is absent and memory is idle. |
| Next-line data prefetch | `D_PREFETCH` | After a D-cache demand miss to line L, line L+1 is refilled when memory is idle. |
| Stores during the refill tail | always on | Once all 8 reads are issued, stores may use the memory port. `memory4c` samples read data at issue, and a store to the line being refilled misses (its way is invalid) and waits. |

## II.13 Configuration parameters

| Parameter | Default | Meaning |
|---|---|---|
| `BP_TYPE` | 6 | direction predictor, 0–6 (II.5) |
| `EARLY_RECOVERY` | 1 | 1: recover at branch execute; 0: at commit |
| `ROB_W` | 4 | ROB entries = 2^`ROB_W` |
| `IQ_N` | 8 | issue-queue entries |
| `SQ_W` | 3 | store-queue entries = 2^`SQ_W` |
| `EARLY_RESTART` | 1 | critical-word-first refills |
| `I_PREFETCH` | 1 | next-line instruction prefetch |
| `D_PREFETCH` | 1 | next-line data prefetch |

## II.14 Performance counters

`cpu.v` keeps these counters. The testbench prints them as a `STATS` line at halt.

| Counter | Counts |
|---|---|
| `cycles`, `commits` | clock cycles until `hlt`, retired instructions (IPC = commits / cycles) |
| `cond_br`, `cond_mispred` | committed conditional branches and how many were mispredicted |
| `br_reg`, `br_reg_mispred` | committed `BR`s and how many were mispredicted |
| `recoveries` | recovery events (including mispredicts that turned out to be on a wrong path) |
| `stall_rob`, `stall_iq`, `stall_sq` | cycles dispatch was blocked by a full ROB, IQ or SQ |
| `ifq_empty` | cycles with nothing to dispatch (I-cache misses, refetch after a redirect) |
| `icache_miss`, `dcache_miss`, `prefetches` | demand refills per cache, and prefetch refills |
| `loads`, `ld_fwd`, `ld_miss_cycles` | completed loads, loads served by forwarding, cycles a load waited on a miss |
| `issued`, `rob_occ_sum` | instructions issued (including wrong-path), sum of ROB occupancy (for the average) |

---

# Part III — Verification and tooling

## III.1 Flow

Two independent executions of the same program, then a line-by-line diff.

```text
  tests/*.s  or  random generator          course  tests/*.img
              |                                      |
              v                                      |
        wisc.py asm  ------>  program.img  <---------+
                                  |
                 +----------------+----------------+
                 |                                 |
                 v                                 v
        golden ISA simulator                 RTL testbench
        (one instr at a time)                (OoO core)
                 |                                 |
                 v                                 v
        expected trace + mem                 ROB commit trace
                                             + mem dump + STATS
                 |                                 |
                 +-------- compare ----------------+
                           |
                           +-- match: pass, record IPC
                           +-- first differing line: fail, print context
```

*Figure III.1 — How a test is judged. Architectural state must match; cycle counts are collected
but never used as a pass/fail check.*

**Commit trace.** There is one line per retired instruction: `<pc> <instr> -`,
`<pc> <instr> R<n>=<value>`, or `<pc> <instr> M[<addr>]=<value>`. The RTL and the golden model
write the same format, so any wrong value, missing instruction or wrong-path leak shows up at the
exact instruction where it happens. At halt, all 64 K words of memory are also compared.

**Golden model** (`tools/wisc.py sim`). It implements Part 0 exactly, including saturation, the
RED tree semantics, Z-only flags for XOR and the shifts, and wrap-around address arithmetic. It
was first checked against the saved phase-3 traces of the four course test images.

## III.2 Directed tests (`ooo_core/tests/`)

| Test | What it checks |
|---|---|
| `alu_ops` | every compute opcode on edge-case operands, including both saturation directions |
| `r0_and_nops` | R0 reads 0 and ignores writes; `SUB R0` compare and `PADDSB R0` NOP idioms |
| `shifts` | SLL / SRA / ROR by every amount 0–15, each result's Z checked with a branch |
| `flags_branches` | every branch condition under many flag states, for both B and BR |
| `mem_basic` | LW / SW with every offset −8..7, odd base addresses, round trips |
| `store_forwarding` | forwarding from the youngest older store; loads bypassing pending stores |
| `renaming` | WAW and WAR hazards on a few registers alongside an independent chain |
| `loops_nested` | nested counted loops with data-dependent trip counts |
| `calls_br_pcs` | `PCS`/`BR` calls and returns from several call sites, and a jump table |
| `cache_conflicts` | three lines in one set (forced evictions), store misses, re-reads after eviction |
| `wrong_path` | taken branches first predicted not-taken: the wrong-path HLT, stores and writes must never commit |
| `structural_stalls` | fills the ROB (load miss at the head), the IQ (many waiting dependents) and the SQ (a store burst) |
| `bench_branch_patterns` | lecture branch patterns: alternating, 1-in-3, correlated pairs, nested loops |
| `bench_bubble_sort` | bubble sort of 24 words plus a checksum (data-dependent branches) |
| `bench_fib` | Fibonacci numbers by a register recurrence and from memory |
| `bench_gcd` | subtraction-based GCD of 10 pairs (hard-to-predict branches) |
| `bench_latency_hiding` | a missing load followed by independent ALU work (out-of-order overlap) |
| `bench_linked_list` | pointer chasing through 32 scattered nodes |
| `bench_memcpy` | 128-word copy plus verification (streaming, store queue) |
| `bench_multiply` | shift-and-add multiply for a dot product |
| `course_test1`–`4` | the four course images |

## III.3 Constrained-random programs (`tools/gen_random.py`)

Each random program always terminates: branches only jump forward, and every loop counts a
reserved register down to zero. Register roles are fixed:

| Register | Role |
|---|---|
| R1–R7, R11 | random destinations |
| R14 | data base around `0x4010` |
| R9 | R14 + a small offset, so accesses through R9 and R14 alias |
| R8, R15 | R14 + `0x400` and R14 + `0x800`: same cache set, different tags (forces evictions) |
| R10 | target register for `BR` |
| R12 | constant 1 |
| R13 | loop counter |

Programs mix these blocks (relative weights in parentheses):
- simple ALU, load or store instructions (50);
- forward branches (14);
- counted loops (8);
- compares (6);
- store-then-reload pairs, for forwarding (8);
- indirect `BR` jumps (5);
- wrong-path traps: an always-taken branch over an `HLT` or a store (3).

Junk words follow the final `HLT` and must never be executed.

## III.4 Regression runner (`tools/run_tests.py`)

`run_tests.py` builds one simulator per configuration (any list of predictors, recovery modes,
ROB / IQ / SQ sizes and memory features). It runs every program on every configuration in
parallel, compares each run, and writes a summary table and an optional CSV of all counters.
`--baseline` also times the five-stage core. `tools/summarize.py` turns the result CSVs into
`ooo_core/results/SUMMARY.md`.

Development rule: every feature was added on its own and kept only after the full regression
passed again. The final regression, all passing:
- Icarus, 3,836 runs: 7 predictors × 2 recovery modes × (24 directed + 250 random programs).
- Icarus, 8,192 runs: gshare and TAGE-lite × both recovery modes × ROB 4/16 × SQ 2/16 × all 8
  memory-feature combinations, on directed + 40 random programs.
- Verilator, 1,848 runs: all predictors and recovery modes, plus IQ 2/16 × ROB 4/32 × SQ 2/16.

---

# Part IV — Results

All numbers come from `ooo_core/results/` and cover the 24 directed programs. "Suite IPC" is
total instructions / total cycles, so the long benchmarks dominate it.

## IV.1 Five-stage vs out-of-order

The out-of-order core here uses its default configuration. The five-stage core is timed with
`ooo_core/tb/baseline_tb.v`, and its instruction counts come from the golden model. Read a row
as "same program, two machines": the last column is OoO cycles divided into five-stage cycles.

| Program | Instructions | 5-stage cycles | 5-stage IPC | OoO cycles | OoO IPC | Speedup |
|---|---:|---:|---:|---:|---:|---:|
| course_test1 | 11 | 40 | 0.275 | 24 | 0.458 | 1.67x |
| course_test2 | 12 | 50 | 0.240 | 37 | 0.324 | 1.35x |
| course_test3 | 19 | 51 | 0.373 | 36 | 0.528 | 1.42x |
| course_test4 | 153 | 361 | 0.424 | 185 | 0.827 | 1.95x |
| alu_ops | 46 | 127 | 0.362 | 75 | 0.613 | 1.69x |
| calls_br_pcs | 116 | 286 | 0.406 | 190 | 0.611 | 1.51x |
| loops_nested | 167 | 343 | 0.487 | 204 | 0.819 | 1.68x |
| shifts | 292 | 919 | 0.318 | 477 | 0.612 | 1.93x |
| store_forwarding | 35 | 131 | 0.267 | 87 | 0.402 | 1.51x |
| structural_stalls | 56 | 305 | 0.184 | 249 | 0.225 | 1.22x |
| bench_gcd | 428 | 815 | 0.525 | 537 | 0.797 | 1.52x |
| bench_latency_hiding | 266 | 574 | 0.463 | 315 | 0.844 | 1.82x |
| bench_branch_patterns | 1941 | 3723 | 0.521 | 2185 | 0.888 | 1.70x |

The geometric-mean speedup over these 13 programs is **1.60x**.

On the other 11 programs, the five-stage core either halts with register values that differ
from the ISA (see I.8) or doesn't halt at all (`flags_branches`), so its cycle counts there
aren't comparable. On those programs the out-of-order core reaches, for example:
- IPC 0.987 on `bench_memcpy`;
- IPC 0.945 on `bench_fib`;
- IPC 0.908 on `bench_bubble_sort`.

## IV.2 Branch predictors and recovery point

Read left to right: a better predictor lowers the mispredict rate; recovering at execute (last
column) always beats recovering at commit (column before it).

| Predictor | Cond. mispredict | IPC, recover at commit | IPC, recover at execute |
|---|---:|---:|---:|
| static not-taken | 71.1% | 0.547 | 0.666 |
| BTFN | 27.9% | 0.702 | 0.765 |
| bimodal | 24.4% | 0.713 | 0.770 |
| gshare | 27.7% | 0.699 | 0.765 |
| tournament | 22.6% | 0.725 | 0.779 |
| perceptron | 18.8% | 0.743 | **0.788** |
| TAGE-lite | 19.0% | 0.740 | 0.786 |

- History-based predictors learn the repeating patterns. On `bench_branch_patterns`, mispredicts
  drop from 273 (bimodal) to about 105 (gshare, tournament).
- Perceptron and TAGE-lite are the best overall.
- Recovering at execute is worth 0.05–0.12 IPC for every predictor.
- The programs are short, so part of every predictor's mispredicts is warm-up.

## IV.3 Window sizes

One structure is varied at a time; the others stay at the defaults (ROB 16, IQ 8, SQ 8).
Read down a column: bigger is only useful if IPC actually moves.

| Entries | ROB suite IPC | IQ suite IPC | SQ suite IPC |
|---:|---:|---:|---:|
| 2 | — | 0.785 | 0.747 |
| 4 | 0.783 | 0.786 | 0.782 |
| 8 | 0.785 | 0.786 | 0.786 |
| 16 | 0.786 | 0.786 | 0.790 |
| 32 | 0.786 | — | — |

With one instruction dispatched per cycle, average ROB occupancy is about 3, so 16 entries is
already plenty. The store queue is the one that matters: stores wait there until they drain
through the single memory port.

## IV.4 Memory-side optimizations

These are total cycles over the suite, relative to all three features off (14,929 cycles).
Each row is one configuration; the last column is the only number that matters for IPC.

| Early restart | I prefetch | D prefetch | Cycles saved vs all-off |
|:---:|:---:|:---:|---:|
| on | off | off | 9.7% |
| off | on | off | 9.4% |
| on | on | off | 11.1% |
| on | on | on | 11.1% |

- Early restart and instruction prefetch both attack cold instruction misses, so their savings
  overlap instead of adding up.
- Data prefetch removes about 16% of demand D-cache misses, but its refills compete for the one
  memory port. On these programs it changes total cycles by less than 0.6% either way.
- Letting stores drain during a refill's last cycles halved the cycles lost to a full store queue
  (560 → 298), about 1.5% of total cycles.

---

# Part V — Side-by-side comparison

| Aspect | Five-stage core | Out-of-order core |
|---|---|---|
| Pipeline | IF / ID / EX / MEM / WB | fetch / rename-dispatch / issue-execute / write-back / commit |
| Fetch | 1 per cycle, no buffer | 1 per cycle into a 4-entry IFQ |
| Execution order | in order | out of order, up to 4 issues per cycle (ALU, BRU, LDU, STU) |
| Data hazards | forwarding (EX→EX, MEM→EX, MEM→MEM, RF bypass) + load-use stall | renaming (map table + ROB) removes WAR/WAW; wakeup/select handles RAW |
| Flags | 3 flip-flops; branches stall while a flag producer is in EX/MEM | renamed as Z and NV; branches wait in the IQ only for the flags they read |
| Branch prediction | predict not-taken | 7 selectable predictors + 16-entry BTB, speculative GHR |
| Branch resolution | in ID; a taken branch costs 1 bubble | in the BRU, then selective squash; ≥ 2 cycles on a mispredict |
| Precise state | in-order write-back | reorder buffer, in-order commit |
| Loads and stores | in MEM, in order | store queue, forwarding, loads bypass older stores to other addresses |
| Cache miss | freezes the whole pipeline (D) or inserts NOPs (I) | blocks only younger loads; independent work keeps executing |
| Caches | 2 KB, 2-way, 8-word lines, write-through, write-allocate | same geometry, true LRU, critical-word-first, next-line prefetch |
| Miss arbitration | I-cache first | D-cache first, then I-cache, stores, prefetches |
| Arithmetic | structural CLA-based units | the same modules, reused |
| Register file | 16 × 16 bit-cell array, 2 read ports | ARF + ROB values + map table |
| Verification | course testbench, saved traces | golden model, commit-trace + memory compare, random programs, sweeps |

---

# Appendix — File index

## Five-stage core (`project_working_directory/`)

| File | Role |
|---|---|
| `cpu.v` | top level: pipeline registers, hazard detection, forwarding, flags |
| `controlsignal.v` | opcode → control signals |
| `pc_control.v` | condition evaluation, branch target, next PC |
| `EX_MEM_Register.v` | EX/MEM pipeline register |
| `pldff.v`, `dff.v` | flip-flops (pipeline registers, flags, PC) |
| `ALU.v`, `Adder_ALU.v`, `Subtractor.v`, `XOR.v`, `RED.v`, `PSA_16bit.v`, `Shifter_ALU.v`, `Shifter.v`, `Rotater.v`, `CLA_16b.v`, `CLA_4b.v` | arithmetic (I.4) |
| `register_file.v`, `register.v`, `bit_cell.v`, `read_decoder_4_16.v`, `write_decoder_4_16.v` | register file (I.5) |
| `unified_memory.v`, `I_cache.v`, `D_cache.v`, `MetaDataArray.v`, `DataArray.v`, `decoder_6_64.v`, `decoder_3_8.v`, `cache_memory_bridge.v`, `cache_miss_handler.v`, `memory4c.v` | memory hierarchy (I.6) |
| `project-phase3-testbench.v` | course testbench |
| `loadfile_test1..4.img`, `TEST1..4.plog/.ptrace` | course programs and saved reference traces |

## Out-of-order core (`ooo_core/`)

| File | Role |
|---|---|
| `rtl/cpu.v` | top level: wiring, dispatch, AGU, recovery, result buses, counters |
| `rtl/frontend.v` | fetch, predecode, next-PC prediction, GHR, IFQ |
| `rtl/branch_predictor.v` | predictor selection and the BTB |
| `rtl/bp_basic.v`, `bp_tournament.v`, `bp_perceptron.v`, `bp_tage.v` | direction predictors |
| `rtl/decoder.v` | instruction classes, sources, destinations, flags |
| `rtl/rob.v` | reorder buffer, ARF, map table, operand lookup, recovery rebuild |
| `rtl/issue_queue.v` | data-capture issue queue, wakeup, oldest-first select |
| `rtl/exec_units.v` | ALU and branch unit |
| `rtl/lsu.v` | store queue, forwarding, load miss handling, store drain |
| `rtl/cache.v` | 2-way cache with early-restart fill tracking and a probe port |
| `rtl/mem_system.v` | refill engine, prefetchers, write-through path, `memory4c` |
| `rtl/ooo_defs.vh` | opcode, functional-unit and predictor constants |
| `tb/cpu_tb.v` | testbench: commit trace, memory dump, `STATS` |
| `tb/baseline_tb.v` | fast timing testbench for the five-stage core |
| `tools/wisc.py` | assembler, disassembler, golden ISA simulator |
| `tools/gen_random.py` | constrained-random program generator |
| `tools/run_tests.py` | regression runner |
| `tools/summarize.py` | `results/*.csv` → `results/SUMMARY.md` |
| `files.f` | source list (including the reused phase-3 files) |

How to build and run both cores is covered in the [repository README](README.md) and
[`ooo_core/README.md`](ooo_core/README.md).
