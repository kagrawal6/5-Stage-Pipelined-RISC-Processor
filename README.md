# WISC-S25 RISC Processor — Verilog Implementation

This project implements a complete **16-bit WISC-S25 RISC processor** in Verilog, developed for ECE/CS 552 (Introduction to Computer Architecture). The design evolves from a single-cycle CPU into a fully **five-stage pipelined processor with instruction and data caches**, implementing all architectural and microarchitectural requirements defined in the course specification.

The processor supports the full **WISC-S25 instruction set**, including:

- **Arithmetic and logical operations**: ADD, SUB, XOR, and RED, with correct Zero (Z), Negative (N), and Overflow (V) flag behavior  
- **Sub-word and reduction operations**: PADDSB and RED, using saturating arithmetic and multi-level reduction logic  
- **Shift and rotate instructions**: SLL, SRA, and ROR using immediate shift amounts  
- **Memory operations**: LW and SW with aligned, byte-addressable memory  
- **Immediate loads**: LLB and LHB implemented using read-modify-write semantics  
- **Control-flow instructions**: B, BR, PCS, and HLT, with conditional branching based on processor flags  

The microarchitecture uses a **five-stage pipeline (IF, ID, EX, MEM, WB)** with:

- **Data hazard handling** via stalling and register forwarding (EX→EX, MEM→EX, MEM→MEM)  
- **Control hazard handling** using predict-not-taken branches and pipeline flushes  
- **Branch resolution in the decode stage (ID)**  
- Correct handling of **HLT** across pipeline stages  

A **two-level memory hierarchy** is implemented with separate instruction and data caches:

- **2 KB, 2-way set-associative I-cache and D-cache**  
- **16-byte cache blocks**  
- **Write-through, write-allocate policy**  
- Cache miss handling using a **finite-state machine** with burst transfers from pipelined main memory  
- **Arbitration logic** to handle simultaneous I-cache and D-cache misses  

The design was verified using the provided testbenches, memory images, and waveform and execution traces to ensure correctness across instruction execution, pipeline hazards, and cache behavior.


The top-level module is `cpu.v`.



## Repository Structure

```text
.
├── README.md                           This file
├── project_working_directory/          All RTL, tests, and simulator files
│   └── README.md                       File map and design overview
├── Project-Description.pdf             Official WISC-S25 ISA, pipeline, and cache spec
├── RISC_CPU_Block_Diagram.pdf          Datapath, pipeline, and cache diagram
└── Final Project Report RISC V.pdf     Design explanation and validation results
```

The processor source lives entirely in `project_working_directory/`. Start there to simulate the design; see that folder's README for a file-by-file map of the RTL.


## How to Run

Simulation was developed and verified in **Questa / ModelSim** (QuestaSim 2023.2). The top-level DUT is `cpu` in `cpu.v`. The provided testbench is `cpu_ptb` in `project-phase3-testbench.v`.

### 1. Prerequisites

- **QuestaSim or ModelSim** (Intel/Mentor), with `vlog` and `vsim` on your `PATH`
- Working directory: `project_working_directory/`

If you do not have ModelSim, Icarus Verilog can compile the same sources (`iverilog` + `vvp`). Waveforms can then be viewed in GTKWave.

### 2. Choose a test program

Main memory is initialized from a hex image in `memory4c.v`. Change the `$readmemh` filename to select a program:

```verilog
$readmemh("loadfile_test1.img", mem);
```

| Image | What it exercises | Saved result traces |
| --- | --- | --- |
| `loadfile_test1.img` | Immediate loads (LLB/LHB) and ALU ops | `TEST1.plog`, `TEST1.ptrace` |
| `loadfile_test2.img` | LW/SW plus PADDSB and RED | `TEST2.plog`, `TEST2.ptrace` |
| `loadfile_test3.img` | Branches (B, BR), PCS, and HLT | `TEST3.plog`, `TEST3.ptrace` |
| `loadfile_test4.img` | Longer mix with loops and cache traffic *(currently selected)* | `TEST4.plog`, `TEST4.ptrace` |

Recompile `memory4c.v` after changing the image. The testbench does not take a plusarg for the image name.

### 3. Simulate with ModelSim / Questa (GUI)

1. Open the project file `project_working_directory/Final_Project.mpf` in ModelSim or Questa.
2. Compile the design (**Compile → Compile All**, or compile every `.v` file into the `work` library).
3. Start the simulator on the testbench:

   ```tcl
   vsim -voptargs=+acc work.cpu_ptb
   ```

4. Optionally add waves, then run until halt:

   ```tcl
   add wave -position insertpoint sim:/cpu_ptb/DUT/*
   run -all
   ```

The testbench prints `Hello world...simulation starting` and stops when `HLT` reaches a later pipeline stage (`$finish`). A 100,000-cycle cap aborts runaway simulations.

### 4. Simulate with ModelSim / Questa (command line)

From `project_working_directory/`:

```bash
vlib work
vlog *.v
vsim -c -voptargs=+acc work.cpu_ptb -do "run -all; quit -f"
```

To re-run after switching the `.img` file, recompile `memory4c.v` and `restart` (GUI) or repeat `vlog` + `vsim` (command line).

### 5. Simulate with Icarus Verilog (optional)

From `project_working_directory/`:

```bash
iverilog -g2012 -o cpu_sim *.v
vvp cpu_sim
```

### 6. What to look at after a run

The testbench writes these files in `project_working_directory/`:

| File | Contents |
| --- | --- |
| `verilogsim.plog` | Per-cycle log: PC, instruction, register write, memory access, then halt stats |
| `verilogsim.ptrace` | Architectural trace of `REG` / `LOAD` / `STORE` events |
| `dump.vcd` | Waveform dump from `$dumpvars` (open in ModelSim or GTKWave) |
| `transcript` | ModelSim console history from previous GUI sessions |

On halt, the `.plog` footer reports:

- `sim_cycles` — clock cycles until halt
- `inst_count` — committed instructions (halt, register write, or store)
- `icachehit_count` / `icachereq_count` — I-cache hits vs. requests
- `dcachehit_count` / `dcachereq_count` — D-cache hits vs. requests

Compare a new `verilogsim.plog` / `verilogsim.ptrace` against the matching `TESTn.*` files for that memory image.

Saved results from the last verification pass:

| Test | Cycles | Instructions | I-cache hits / reqs | D-cache hits / reqs |
| --- | ---: | ---: | ---: | ---: |
| TEST1 | 44 | 38 | 10 / 12 | 0 / 0 |
| TEST2 | 54 | 47 | 11 / 13 | 1 / 2 |
| TEST3 | 55 | 45 | 20 / 22 | 0 / 0 |
| TEST4 | 365 | 242 | 170 / 176 | 30 / 32 |

Clock period in the testbench is **100 time units** (50-unit half-period). Reset is held for **201 time units**.


## Documentation

The following documents describe the design and specification of the processor:

- Project-Description.pdf — Official WISC-S25 ISA, pipeline, and cache specifications
- RISC_CPU_Block_Diagram.pdf — Datapath, pipeline, and cache block diagram
- Final Project Report RISC V.pdf — Design explanation and validation results


## Reference Material

- Course Lectures: https://youtube.com/playlist?list=PLYPFPSvBJgaeS8NVVMlmt_w24vUaWGI2C&si=G_H_8zdJ1Gowo0VY

- Textbook: Computer Organization and Design by David A. Patterson and John L. Hennessy
