# Cache behaviour: three lines that map to the same set (2-way, so one is
# always evicted), stores that miss (write-allocate), and re-reads after
# eviction (the data must come back from memory, written through).
# Set index = addr[9:4]; adding 0x400 keeps the set and changes the tag.
    LLB R12, 1
    LI  R1, 0x5010          # set 1, tag A
    LI  R2, 0x5410          # set 1, tag B
    LI  R3, 0x5810          # set 1, tag C
    LI  R4, 0xA5A5
    LI  R5, 0x5A5A
    LLB R6, 4               # repeat the pattern a few times
again:
    SW  R4, R1, 0           # miss -> allocate A
    SW  R5, R2, 1           # miss -> allocate B
    LW  R7, R1, 0           # hit A
    SW  R4, R3, 2           # miss -> evict (LRU = B)
    LW  R8, R2, 1           # miss -> evict A, B comes back from memory
    LW  R9, R1, 0           # miss again
    LW  R10, R3, 2
    ADD R4, R4, R12
    SUB R5, R5, R12
    ADD R1, R1, R12         # move to the next word (same line)
    ADD R1, R1, R12
    SUB R6, R6, R12
    B NEQ, again
    # walk 40 consecutive lines (more than one way's worth of sets is fine,
    # this just exercises many fills back to back)
    LI  R1, 0x6000
    LLB R6, 40
    LLB R11, 0
walk:
    LW  R7, R1, 0
    ADD R11, R11, R7
    SW  R6, R1, 1
    LLB R13, 16
    ADD R1, R1, R13
    SUB R6, R6, R12
    B NEQ, walk
    LI  R1, 0x6000
    LW  R2, R1, 1
    LW  R3, R1, 7
    HLT
