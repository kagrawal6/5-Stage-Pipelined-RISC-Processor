# Fill every queue: a load miss at the ROB head with a long run of younger
# work (ROB full), many waiting dependents (issue queue full), and a burst
# of stores to missing lines (store queue full while stores drain).
    LLB R12, 1
    LI  R1, 0x7000
    LW  R2, R1, 0           # miss at the head of the ROB
    ADD R3, R2, R12         # these all wait for the load (fill the IQ)
    ADD R4, R2, R12
    ADD R5, R2, R12
    ADD R6, R2, R12
    ADD R7, R2, R12
    ADD R8, R2, R12
    ADD R9, R2, R12
    ADD R10, R2, R12
    ADD R11, R2, R12
    ADD R13, R2, R12
    ADD R3, R3, R4
    ADD R5, R5, R6
    ADD R7, R7, R8
    ADD R9, R9, R10
    ADD R11, R11, R13
    ADD R3, R3, R5
    ADD R7, R7, R9
    ADD R3, R3, R7
    ADD R3, R3, R11
    # store burst to 12 different lines
    LI  R1, 0x7100
    LLB R14, 16
    SW  R3, R1, 0
    ADD R1, R1, R14
    SW  R3, R1, 0
    ADD R1, R1, R14
    SW  R3, R1, 0
    ADD R1, R1, R14
    SW  R3, R1, 0
    ADD R1, R1, R14
    SW  R3, R1, 0
    ADD R1, R1, R14
    SW  R3, R1, 0
    ADD R1, R1, R14
    SW  R3, R1, 0
    ADD R1, R1, R14
    SW  R3, R1, 0
    ADD R1, R1, R14
    SW  R3, R1, 0
    ADD R1, R1, R14
    SW  R3, R1, 0
    ADD R1, R1, R14
    SW  R3, R1, 0
    ADD R1, R1, R14
    SW  R3, R1, 0
    # read some of them back
    LI  R1, 0x7100
    LW  R4, R1, 0
    LI  R1, 0x71B0
    LW  R5, R1, 0
    HLT
