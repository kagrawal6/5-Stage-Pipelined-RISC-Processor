# Project Working Directory

This folder is the complete implementation of the **16-bit WISC-S25 five-stage pipelined processor** with separate instruction and data caches. For how to compile, pick a memory image, and run simulation, see the [repository README](../README.md).

The top-level RTL module is `cpu` in `cpu.v`. The simulation harness is `cpu_ptb` in `project-phase3-testbench.v`.


## What this design does

`cpu.v` wires a classic **IF → ID → EX → MEM → WB** pipeline around a 16-register file and a unified memory system.

**Fetch / decode.** The PC is updated in `pc_control.v`. Instructions come from the I-cache (`I_cache.v`). `controlsignal.v` decodes the 4-bit opcode into ALU op, memory enables, register-write, branch, PCS, and HLT controls. Branches are resolved in **ID** using the Z/N/V flags (predict not-taken; taken branches flush IF).

**Execute.** `ALU.v` selects ADD, SUB, XOR, RED, SLL, SRA, ROR, or PADDSB. Address generation for LW/SW and the LLB/LHB read-modify-write path also happen here.

**Memory / writeback.** LW and SW go through the D-cache (`D_cache.v`). Results (ALU, memory, PCS, or load-byte) write the register file in WB. `HLT` is held until it reaches a later stage so earlier instructions can complete.

**Hazards.** Data hazards use stalling plus forwarding (EX→EX, MEM→EX, MEM→MEM). Load-use and flag-use cases stall. Control hazards flush on taken branches.

**Caches.** I-cache and D-cache are each **2 KB, 2-way set-associative, 16-byte blocks**. D-cache is **write-through, write-allocate**. Misses are filled by `cache_miss_handler.v` with burst reads from 4-cycle pipelined main memory (`memory4c.v`). `cache_memory_bridge.v` arbitrates when both caches miss.


## How the files fit together

```text
project-phase3-testbench.v          cpu_ptb  — clock, reset, traces
        │
        ▼
     cpu.v                          pipeline + hazard + flag logic
        ├── pc_control.v            next PC and branch conditions
        ├── controlsignal.v         opcode → control signals
        ├── register_file.v         16 × 16-bit registers
        ├── ALU.v                   execute-stage operations
        ├── EX_MEM_Register.v       EX/MEM pipeline register
        └── unified_memory.v        I-cache + D-cache + main memory
                ├── I_cache.v
                ├── D_cache.v
                ├── cache_memory_bridge.v
                │       └── cache_miss_handler.v
                └── memory4c.v      loads loadfile_testN.img
```


## File map

### Top level and control

| File | Role |
| --- | --- |
| `cpu.v` | Top-level processor: five pipeline stages, forwarding, stalls, flushes, flag registers |
| `controlsignal.v` | Combinational decode of the 16 WISC-S25 opcodes |
| `pc_control.v` | PC increment, B/BR target, and condition codes (BNE, BE, BGT, BLT, BGE, BLE, BO, unconditional) |
| `EX_MEM_Register.v` | Pipeline register between execute and memory |
| `pldff.v` | Parameterized multi-bit flop used for pipeline registers |
| `dff.v` | Single-bit enabled flop (flags and other 1-bit state) |

### ALU datapath

| File | Role |
| --- | --- |
| `ALU.v` | Selects the functional unit from `ALUOp` and produces result, Z, N, V |
| `Adder_ALU.v` | 16-bit add with overflow / zero / sign |
| `Subtractor.v` | 16-bit subtract with flags |
| `XOR.v` | Bitwise XOR |
| `RED.v` | Multi-level reduction add |
| `PSA_16bit.v` | PADDSB: four saturating 4-bit adds packed into 16 bits |
| `Shifter_ALU.v` | Shift/rotate wrapper used by the ALU |
| `Shifter.v` | SLL and SRA |
| `Rotater.v` | ROR |
| `CLA_16b.v` | 16-bit carry-lookahead adder (ALU, PC, cache address increment) |
| `CLA_4b.v` | 4-bit CLA used inside the 16-bit adder and RED/PADDSB |

### Register file

| File | Role |
| --- | --- |
| `register_file.v` | 16-register file with two read ports and one write port |
| `register.v` | One 16-bit register built from bit cells |
| `bit_cell.v` | One storage bit with dual read bitlines |
| `read_decoder_4_16.v` | 4-to-16 one-hot read select |
| `write_decoder_4_16.v` | 4-to-16 one-hot write select |

### Memory hierarchy

| File | Role |
| --- | --- |
| `unified_memory.v` | Connects I-cache, D-cache, miss handler, and main memory to the pipeline |
| `I_cache.v` | 2-way I-cache: tag compare, LRU, hit/miss, fill |
| `D_cache.v` | 2-way D-cache for LW/SW; write-through / write-allocate |
| `DataArray.v` | Cache data storage (blocks × words × bits) |
| `MetaDataArray.v` | Per-block tag, valid, and LRU bits |
| `decoder_6_64.v` | One-hot set select (6-bit index → 64 sets) |
| `decoder_3_8.v` | One-hot word select inside a 16-byte block |
| `cache_memory_bridge.v` | Arbitrates simultaneous I-cache and D-cache misses onto one memory port |
| `cache_miss_handler.v` | FSM that bursts a 16-byte line from main memory into the cache |
| `memory4c.v` | Byte-addressable 16-bit main memory; 1-cycle write, 4-cycle read; `$readmemh` of the selected `.img` |

### Testbench, programs, and traces

| File | Role |
| --- | --- |
| `project-phase3-testbench.v` | Instantiates `cpu`, drives clk/rst_n, logs cycle state, cache stats, and stops on halt |
| `loadfile_test1.img` | Hex program: LLB/LHB and ALU |
| `loadfile_test2.img` | Hex program: LW/SW, PADDSB, RED |
| `loadfile_test3.img` | Hex program: B, BR, PCS, HLT |
| `loadfile_test4.img` | Hex program: longer loops and cache traffic (the image currently named in `memory4c.v`) |
| `TEST1.plog` … `TEST4.plog` | Saved per-cycle logs from those four images |
| `TEST1.ptrace` … `TEST4.ptrace` | Saved register/memory traces |
| `verilogsim.plog` / `verilogsim.ptrace` | Output of the most recent simulation |
| `transcript` | ModelSim/Questa console log |

### Simulator / project metadata

These are not RTL. You can ignore them when reading the design.

| File | Role |
| --- | --- |
| `Final_Project.mpf` | ModelSim/Questa project (open this to simulate in the GUI) |
| `Final_Project.cr.mti`, `Final_Project_v1.cr.mti`, `Design.cr.mti` | Compile-record files created by ModelSim |
| `work_quartus/` | Compiled library leftovers from a previous tool flow |


## ISA opcodes (as decoded in this RTL)

| Opcode | Instruction |
| --- | --- |
| `0000` | ADD |
| `0001` | SUB |
| `0010` | XOR |
| `0011` | RED |
| `0100` | SLL |
| `0101` | SRA |
| `0110` | ROR |
| `0111` | PADDSB |
| `1000` | LW |
| `1001` | SW |
| `1010` | LLB |
| `1011` | LHB |
| `1100` | B |
| `1101` | BR |
| `1110` | PCS |
| `1111` | HLT |

Memory images are hex instruction words, one per line, loaded at reset by `memory4c.v`.
