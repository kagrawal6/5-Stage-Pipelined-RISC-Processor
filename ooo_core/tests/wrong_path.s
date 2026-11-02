# Wrong-path safety. Each branch below is taken, but a predictor that has
# not seen it yet guesses not-taken, so the core fetches the fall-through
# path speculatively. Nothing on those paths may become architectural:
# not the HLT, not the stores, not the register writes.
    LLB R12, 1
    LI  R14, 0x4500
    LI  R1, 0x1234
    SUB R0, R1, R1          # Z = 1
    B EQ, t1
    HLT                     # wrong-path HLT: fetch must restart after recovery
t1:
    SUB R0, R1, R1
    B EQ, t2
    SW  R1, R14, 0          # wrong-path store: must be squashed
    SW  R1, R14, 1
t2:
    LW  R2, R14, 0          # must read 0
    SUB R0, R1, R1
    B EQ, t3
    LI  R3, 0xFFF0
    LW  R4, R3, 0           # wrong-path load from a far address
    BR  UNCOND, R3          # wrong-path jump into empty memory
t3:
    # slow branch: its condition depends on a cache-missing load, so many
    # wrong-path instructions get fetched and dispatched before it resolves
    LI  R5, 0x4F00
    LW  R6, R5, 0           # 0, misses in the cache
    SUB R0, R6, R0          # Z = 1
    B EQ, t4
    ADD R7, R1, R1
    SW  R7, R14, 2
    ADD R7, R7, R7
    LW  R8, R14, 2
    SW  R8, R14, 3
    HLT
t4:
    LW  R9, R14, 2          # must be 0
    LW  R10, R14, 3
    HLT
