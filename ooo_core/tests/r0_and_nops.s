# R0 is hardwired to zero: writes are discarded, reads return 0.
# SUB R0 is the compare idiom (sets flags), PADDSB R0 is the NOP idiom.
    LI  R1, 0x00FF
    LLB R0, 0x55
    LHB R0, 0x55
    ADD R0, R1, R1
    ADD R2, R0, R1          # must read 0 + 0x00FF
    PCS R0
    LW  R0, R1, 0
    ADD R3, R0, R0
    SUB R0, R1, R1          # Z = 1
    NOP
    NOP
    PADDSB R0, R1, R1
    B EQ, ok
    LLB R4, 0xEE            # must not happen
ok:
    MOV R5, R1
    CMP R1, R5              # Z = 1
    B NEQ, bad
    LLB R6, 0x01
bad:
    HLT
