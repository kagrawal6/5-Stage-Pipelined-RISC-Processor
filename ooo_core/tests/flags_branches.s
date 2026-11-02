# Every branch condition under many flag states, for both B and BR.
# Markers are written with MOV (PADDSB with R0), which never changes flags,
# so the trace shows exactly which branches fell through.
    LLB R12, 1
    LI  R1, 0x0005
    LI  R2, 0x0100
    LI  R3, 0x7FFF
    LI  R4, 0x8000
    LI  R14, 0x4000
# --- state 0: Z=1 N=0 V=0  (B) ---
    SUB R0, R1, R1
    B NEQ, s0b0
    MOV R8, R12      # fell through
    SW R1, R14, 0
s0b0:
    B EQ, s0b1
    MOV R9, R12      # fell through
    SW R1, R14, 1
s0b1:
    B GT, s0b2
    MOV R8, R12      # fell through
    SW R1, R14, 2
s0b2:
    B LT, s0b3
    MOV R9, R12      # fell through
    SW R1, R14, 3
s0b3:
    B GTE, s0b4
    MOV R8, R12      # fell through
    SW R1, R14, 4
s0b4:
    B LTE, s0b5
    MOV R9, R12      # fell through
    SW R1, R14, 5
s0b5:
    B OVFL, s0b6
    MOV R8, R12      # fell through
    SW R1, R14, 6
s0b6:
    B UNCOND, s0b7
    MOV R9, R12      # fell through
    SW R1, R14, 7
s0b7:
# --- state 0: Z=1 N=0 V=0  (BR) ---
    SUB R0, R1, R1
    LI R10, s0br0
    BR NEQ, R10
    MOV R8, R12      # fell through
    SW R1, R14, 0
s0br0:
    LI R10, s0br1
    BR EQ, R10
    MOV R9, R12      # fell through
    SW R1, R14, 1
s0br1:
    LI R10, s0br2
    BR GT, R10
    MOV R8, R12      # fell through
    SW R1, R14, 2
s0br2:
    LI R10, s0br3
    BR LT, R10
    MOV R9, R12      # fell through
    SW R1, R14, 3
s0br3:
    LI R10, s0br4
    BR GTE, R10
    MOV R8, R12      # fell through
    SW R1, R14, 4
s0br4:
    LI R10, s0br5
    BR LTE, R10
    MOV R9, R12      # fell through
    SW R1, R14, 5
s0br5:
    LI R10, s0br6
    BR OVFL, R10
    MOV R8, R12      # fell through
    SW R1, R14, 6
s0br6:
    LI R10, s0br7
    BR UNCOND, R10
    MOV R9, R12      # fell through
    SW R1, R14, 7
s0br7:
# --- state 1: N=1 (small - large)  (B) ---
    SUB R0, R1, R2
    B NEQ, s1b0
    MOV R8, R12      # fell through
    SW R1, R14, 0
s1b0:
    B EQ, s1b1
    MOV R9, R12      # fell through
    SW R1, R14, 1
s1b1:
    B GT, s1b2
    MOV R8, R12      # fell through
    SW R1, R14, 2
s1b2:
    B LT, s1b3
    MOV R9, R12      # fell through
    SW R1, R14, 3
s1b3:
    B GTE, s1b4
    MOV R8, R12      # fell through
    SW R1, R14, 4
s1b4:
    B LTE, s1b5
    MOV R9, R12      # fell through
    SW R1, R14, 5
s1b5:
    B OVFL, s1b6
    MOV R8, R12      # fell through
    SW R1, R14, 6
s1b6:
    B UNCOND, s1b7
    MOV R9, R12      # fell through
    SW R1, R14, 7
s1b7:
# --- state 1: N=1 (small - large)  (BR) ---
    SUB R0, R1, R2
    LI R10, s1br0
    BR NEQ, R10
    MOV R8, R12      # fell through
    SW R1, R14, 0
s1br0:
    LI R10, s1br1
    BR EQ, R10
    MOV R9, R12      # fell through
    SW R1, R14, 1
s1br1:
    LI R10, s1br2
    BR GT, R10
    MOV R8, R12      # fell through
    SW R1, R14, 2
s1br2:
    LI R10, s1br3
    BR LT, R10
    MOV R9, R12      # fell through
    SW R1, R14, 3
s1br3:
    LI R10, s1br4
    BR GTE, R10
    MOV R8, R12      # fell through
    SW R1, R14, 4
s1br4:
    LI R10, s1br5
    BR LTE, R10
    MOV R9, R12      # fell through
    SW R1, R14, 5
s1br5:
    LI R10, s1br6
    BR OVFL, R10
    MOV R8, R12      # fell through
    SW R1, R14, 6
s1br6:
    LI R10, s1br7
    BR UNCOND, R10
    MOV R9, R12      # fell through
    SW R1, R14, 7
s1br7:
# --- state 2: all clear (large - small)  (B) ---
    SUB R0, R2, R1
    B NEQ, s2b0
    MOV R8, R12      # fell through
    SW R1, R14, 0
s2b0:
    B EQ, s2b1
    MOV R9, R12      # fell through
    SW R1, R14, 1
s2b1:
    B GT, s2b2
    MOV R8, R12      # fell through
    SW R1, R14, 2
s2b2:
    B LT, s2b3
    MOV R9, R12      # fell through
    SW R1, R14, 3
s2b3:
    B GTE, s2b4
    MOV R8, R12      # fell through
    SW R1, R14, 4
s2b4:
    B LTE, s2b5
    MOV R9, R12      # fell through
    SW R1, R14, 5
s2b5:
    B OVFL, s2b6
    MOV R8, R12      # fell through
    SW R1, R14, 6
s2b6:
    B UNCOND, s2b7
    MOV R9, R12      # fell through
    SW R1, R14, 7
s2b7:
# --- state 2: all clear (large - small)  (BR) ---
    SUB R0, R2, R1
    LI R10, s2br0
    BR NEQ, R10
    MOV R8, R12      # fell through
    SW R1, R14, 0
s2br0:
    LI R10, s2br1
    BR EQ, R10
    MOV R9, R12      # fell through
    SW R1, R14, 1
s2br1:
    LI R10, s2br2
    BR GT, R10
    MOV R8, R12      # fell through
    SW R1, R14, 2
s2br2:
    LI R10, s2br3
    BR LT, R10
    MOV R9, R12      # fell through
    SW R1, R14, 3
s2br3:
    LI R10, s2br4
    BR GTE, R10
    MOV R8, R12      # fell through
    SW R1, R14, 4
s2br4:
    LI R10, s2br5
    BR LTE, R10
    MOV R9, R12      # fell through
    SW R1, R14, 5
s2br5:
    LI R10, s2br6
    BR OVFL, R10
    MOV R8, R12      # fell through
    SW R1, R14, 6
s2br6:
    LI R10, s2br7
    BR UNCOND, R10
    MOV R9, R12      # fell through
    SW R1, R14, 7
s2br7:
# --- state 3: V=1 N=0 (0x7FFF + 1 saturates)  (B) ---
    ADD R0, R3, R12
    B NEQ, s3b0
    MOV R8, R12      # fell through
    SW R1, R14, 0
s3b0:
    B EQ, s3b1
    MOV R9, R12      # fell through
    SW R1, R14, 1
s3b1:
    B GT, s3b2
    MOV R8, R12      # fell through
    SW R1, R14, 2
s3b2:
    B LT, s3b3
    MOV R9, R12      # fell through
    SW R1, R14, 3
s3b3:
    B GTE, s3b4
    MOV R8, R12      # fell through
    SW R1, R14, 4
s3b4:
    B LTE, s3b5
    MOV R9, R12      # fell through
    SW R1, R14, 5
s3b5:
    B OVFL, s3b6
    MOV R8, R12      # fell through
    SW R1, R14, 6
s3b6:
    B UNCOND, s3b7
    MOV R9, R12      # fell through
    SW R1, R14, 7
s3b7:
# --- state 3: V=1 N=0 (0x7FFF + 1 saturates)  (BR) ---
    ADD R0, R3, R12
    LI R10, s3br0
    BR NEQ, R10
    MOV R8, R12      # fell through
    SW R1, R14, 0
s3br0:
    LI R10, s3br1
    BR EQ, R10
    MOV R9, R12      # fell through
    SW R1, R14, 1
s3br1:
    LI R10, s3br2
    BR GT, R10
    MOV R8, R12      # fell through
    SW R1, R14, 2
s3br2:
    LI R10, s3br3
    BR LT, R10
    MOV R9, R12      # fell through
    SW R1, R14, 3
s3br3:
    LI R10, s3br4
    BR GTE, R10
    MOV R8, R12      # fell through
    SW R1, R14, 4
s3br4:
    LI R10, s3br5
    BR LTE, R10
    MOV R9, R12      # fell through
    SW R1, R14, 5
s3br5:
    LI R10, s3br6
    BR OVFL, R10
    MOV R8, R12      # fell through
    SW R1, R14, 6
s3br6:
    LI R10, s3br7
    BR UNCOND, R10
    MOV R9, R12      # fell through
    SW R1, R14, 7
s3br7:
# --- state 4: V=1 N=1 (0x8000 - 1 saturates)  (B) ---
    SUB R0, R4, R12
    B NEQ, s4b0
    MOV R8, R12      # fell through
    SW R1, R14, 0
s4b0:
    B EQ, s4b1
    MOV R9, R12      # fell through
    SW R1, R14, 1
s4b1:
    B GT, s4b2
    MOV R8, R12      # fell through
    SW R1, R14, 2
s4b2:
    B LT, s4b3
    MOV R9, R12      # fell through
    SW R1, R14, 3
s4b3:
    B GTE, s4b4
    MOV R8, R12      # fell through
    SW R1, R14, 4
s4b4:
    B LTE, s4b5
    MOV R9, R12      # fell through
    SW R1, R14, 5
s4b5:
    B OVFL, s4b6
    MOV R8, R12      # fell through
    SW R1, R14, 6
s4b6:
    B UNCOND, s4b7
    MOV R9, R12      # fell through
    SW R1, R14, 7
s4b7:
# --- state 4: V=1 N=1 (0x8000 - 1 saturates)  (BR) ---
    SUB R0, R4, R12
    LI R10, s4br0
    BR NEQ, R10
    MOV R8, R12      # fell through
    SW R1, R14, 0
s4br0:
    LI R10, s4br1
    BR EQ, R10
    MOV R9, R12      # fell through
    SW R1, R14, 1
s4br1:
    LI R10, s4br2
    BR GT, R10
    MOV R8, R12      # fell through
    SW R1, R14, 2
s4br2:
    LI R10, s4br3
    BR LT, R10
    MOV R9, R12      # fell through
    SW R1, R14, 3
s4br3:
    LI R10, s4br4
    BR GTE, R10
    MOV R8, R12      # fell through
    SW R1, R14, 4
s4br4:
    LI R10, s4br5
    BR LTE, R10
    MOV R9, R12      # fell through
    SW R1, R14, 5
s4br5:
    LI R10, s4br6
    BR OVFL, R10
    MOV R8, R12      # fell through
    SW R1, R14, 6
s4br6:
    LI R10, s4br7
    BR UNCOND, R10
    MOV R9, R12      # fell through
    SW R1, R14, 7
s4br7:
# --- state 5: XOR sets Z=1 only; N=1 V=1 kept  (B) ---
    SUB R0, R4, R12
    XOR R0, R1, R1
    B NEQ, s5b0
    MOV R8, R12      # fell through
    SW R1, R14, 0
s5b0:
    B EQ, s5b1
    MOV R9, R12      # fell through
    SW R1, R14, 1
s5b1:
    B GT, s5b2
    MOV R8, R12      # fell through
    SW R1, R14, 2
s5b2:
    B LT, s5b3
    MOV R9, R12      # fell through
    SW R1, R14, 3
s5b3:
    B GTE, s5b4
    MOV R8, R12      # fell through
    SW R1, R14, 4
s5b4:
    B LTE, s5b5
    MOV R9, R12      # fell through
    SW R1, R14, 5
s5b5:
    B OVFL, s5b6
    MOV R8, R12      # fell through
    SW R1, R14, 6
s5b6:
    B UNCOND, s5b7
    MOV R9, R12      # fell through
    SW R1, R14, 7
s5b7:
# --- state 5: XOR sets Z=1 only; N=1 V=1 kept  (BR) ---
    SUB R0, R4, R12
    XOR R0, R1, R1
    LI R10, s5br0
    BR NEQ, R10
    MOV R8, R12      # fell through
    SW R1, R14, 0
s5br0:
    LI R10, s5br1
    BR EQ, R10
    MOV R9, R12      # fell through
    SW R1, R14, 1
s5br1:
    LI R10, s5br2
    BR GT, R10
    MOV R8, R12      # fell through
    SW R1, R14, 2
s5br2:
    LI R10, s5br3
    BR LT, R10
    MOV R9, R12      # fell through
    SW R1, R14, 3
s5br3:
    LI R10, s5br4
    BR GTE, R10
    MOV R8, R12      # fell through
    SW R1, R14, 4
s5br4:
    LI R10, s5br5
    BR LTE, R10
    MOV R9, R12      # fell through
    SW R1, R14, 5
s5br5:
    LI R10, s5br6
    BR OVFL, R10
    MOV R8, R12      # fell through
    SW R1, R14, 6
s5br6:
    LI R10, s5br7
    BR UNCOND, R10
    MOV R9, R12      # fell through
    SW R1, R14, 7
s5br7:
# --- state 6: SLL sets Z=0 only; N=1 V=1 kept  (B) ---
    SUB R0, R4, R12
    SLL R0, R1, 0
    B NEQ, s6b0
    MOV R8, R12      # fell through
    SW R1, R14, 0
s6b0:
    B EQ, s6b1
    MOV R9, R12      # fell through
    SW R1, R14, 1
s6b1:
    B GT, s6b2
    MOV R8, R12      # fell through
    SW R1, R14, 2
s6b2:
    B LT, s6b3
    MOV R9, R12      # fell through
    SW R1, R14, 3
s6b3:
    B GTE, s6b4
    MOV R8, R12      # fell through
    SW R1, R14, 4
s6b4:
    B LTE, s6b5
    MOV R9, R12      # fell through
    SW R1, R14, 5
s6b5:
    B OVFL, s6b6
    MOV R8, R12      # fell through
    SW R1, R14, 6
s6b6:
    B UNCOND, s6b7
    MOV R9, R12      # fell through
    SW R1, R14, 7
s6b7:
# --- state 6: SLL sets Z=0 only; N=1 V=1 kept  (BR) ---
    SUB R0, R4, R12
    SLL R0, R1, 0
    LI R10, s6br0
    BR NEQ, R10
    MOV R8, R12      # fell through
    SW R1, R14, 0
s6br0:
    LI R10, s6br1
    BR EQ, R10
    MOV R9, R12      # fell through
    SW R1, R14, 1
s6br1:
    LI R10, s6br2
    BR GT, R10
    MOV R8, R12      # fell through
    SW R1, R14, 2
s6br2:
    LI R10, s6br3
    BR LT, R10
    MOV R9, R12      # fell through
    SW R1, R14, 3
s6br3:
    LI R10, s6br4
    BR GTE, R10
    MOV R8, R12      # fell through
    SW R1, R14, 4
s6br4:
    LI R10, s6br5
    BR LTE, R10
    MOV R9, R12      # fell through
    SW R1, R14, 5
s6br5:
    LI R10, s6br6
    BR OVFL, R10
    MOV R8, R12      # fell through
    SW R1, R14, 6
s6br6:
    LI R10, s6br7
    BR UNCOND, R10
    MOV R9, R12      # fell through
    SW R1, R14, 7
s6br7:
# --- state 7: SRA result 0 sets Z=1; N=0 V=0 kept  (B) ---
    SUB R0, R2, R1
    SRA R0, R12, 1
    B NEQ, s7b0
    MOV R8, R12      # fell through
    SW R1, R14, 0
s7b0:
    B EQ, s7b1
    MOV R9, R12      # fell through
    SW R1, R14, 1
s7b1:
    B GT, s7b2
    MOV R8, R12      # fell through
    SW R1, R14, 2
s7b2:
    B LT, s7b3
    MOV R9, R12      # fell through
    SW R1, R14, 3
s7b3:
    B GTE, s7b4
    MOV R8, R12      # fell through
    SW R1, R14, 4
s7b4:
    B LTE, s7b5
    MOV R9, R12      # fell through
    SW R1, R14, 5
s7b5:
    B OVFL, s7b6
    MOV R8, R12      # fell through
    SW R1, R14, 6
s7b6:
    B UNCOND, s7b7
    MOV R9, R12      # fell through
    SW R1, R14, 7
s7b7:
# --- state 7: SRA result 0 sets Z=1; N=0 V=0 kept  (BR) ---
    SUB R0, R2, R1
    SRA R0, R12, 1
    LI R10, s7br0
    BR NEQ, R10
    MOV R8, R12      # fell through
    SW R1, R14, 0
s7br0:
    LI R10, s7br1
    BR EQ, R10
    MOV R9, R12      # fell through
    SW R1, R14, 1
s7br1:
    LI R10, s7br2
    BR GT, R10
    MOV R8, R12      # fell through
    SW R1, R14, 2
s7br2:
    LI R10, s7br3
    BR LT, R10
    MOV R9, R12      # fell through
    SW R1, R14, 3
s7br3:
    LI R10, s7br4
    BR GTE, R10
    MOV R8, R12      # fell through
    SW R1, R14, 4
s7br4:
    LI R10, s7br5
    BR LTE, R10
    MOV R9, R12      # fell through
    SW R1, R14, 5
s7br5:
    LI R10, s7br6
    BR OVFL, R10
    MOV R8, R12      # fell through
    SW R1, R14, 6
s7br6:
    LI R10, s7br7
    BR UNCOND, R10
    MOV R9, R12      # fell through
    SW R1, R14, 7
s7br7:
# --- state 8: ROR result nonzero; Z=0 after ADD gave Z=1  (B) ---
    ADD R0, R0, R0
    ROR R0, R3, 4
    B NEQ, s8b0
    MOV R8, R12      # fell through
    SW R1, R14, 0
s8b0:
    B EQ, s8b1
    MOV R9, R12      # fell through
    SW R1, R14, 1
s8b1:
    B GT, s8b2
    MOV R8, R12      # fell through
    SW R1, R14, 2
s8b2:
    B LT, s8b3
    MOV R9, R12      # fell through
    SW R1, R14, 3
s8b3:
    B GTE, s8b4
    MOV R8, R12      # fell through
    SW R1, R14, 4
s8b4:
    B LTE, s8b5
    MOV R9, R12      # fell through
    SW R1, R14, 5
s8b5:
    B OVFL, s8b6
    MOV R8, R12      # fell through
    SW R1, R14, 6
s8b6:
    B UNCOND, s8b7
    MOV R9, R12      # fell through
    SW R1, R14, 7
s8b7:
# --- state 8: ROR result nonzero; Z=0 after ADD gave Z=1  (BR) ---
    ADD R0, R0, R0
    ROR R0, R3, 4
    LI R10, s8br0
    BR NEQ, R10
    MOV R8, R12      # fell through
    SW R1, R14, 0
s8br0:
    LI R10, s8br1
    BR EQ, R10
    MOV R9, R12      # fell through
    SW R1, R14, 1
s8br1:
    LI R10, s8br2
    BR GT, R10
    MOV R8, R12      # fell through
    SW R1, R14, 2
s8br2:
    LI R10, s8br3
    BR LT, R10
    MOV R9, R12      # fell through
    SW R1, R14, 3
s8br3:
    LI R10, s8br4
    BR GTE, R10
    MOV R8, R12      # fell through
    SW R1, R14, 4
s8br4:
    LI R10, s8br5
    BR LTE, R10
    MOV R9, R12      # fell through
    SW R1, R14, 5
s8br5:
    LI R10, s8br6
    BR OVFL, R10
    MOV R8, R12      # fell through
    SW R1, R14, 6
s8br6:
    LI R10, s8br7
    BR UNCOND, R10
    MOV R9, R12      # fell through
    SW R1, R14, 7
s8br7:
# --- state 9: RED/PADDSB/LLB do not touch flags (Z=1 from SUB)  (B) ---
    SUB R0, R1, R1
    RED R5, R3, R4
    PADDSB R6, R3, R4
    LLB R7, 0x00
    B NEQ, s9b0
    MOV R8, R12      # fell through
    SW R1, R14, 0
s9b0:
    B EQ, s9b1
    MOV R9, R12      # fell through
    SW R1, R14, 1
s9b1:
    B GT, s9b2
    MOV R8, R12      # fell through
    SW R1, R14, 2
s9b2:
    B LT, s9b3
    MOV R9, R12      # fell through
    SW R1, R14, 3
s9b3:
    B GTE, s9b4
    MOV R8, R12      # fell through
    SW R1, R14, 4
s9b4:
    B LTE, s9b5
    MOV R9, R12      # fell through
    SW R1, R14, 5
s9b5:
    B OVFL, s9b6
    MOV R8, R12      # fell through
    SW R1, R14, 6
s9b6:
    B UNCOND, s9b7
    MOV R9, R12      # fell through
    SW R1, R14, 7
s9b7:
# --- state 9: RED/PADDSB/LLB do not touch flags (Z=1 from SUB)  (BR) ---
    SUB R0, R1, R1
    RED R5, R3, R4
    PADDSB R6, R3, R4
    LLB R7, 0x00
    LI R10, s9br0
    BR NEQ, R10
    MOV R8, R12      # fell through
    SW R1, R14, 0
s9br0:
    LI R10, s9br1
    BR EQ, R10
    MOV R9, R12      # fell through
    SW R1, R14, 1
s9br1:
    LI R10, s9br2
    BR GT, R10
    MOV R8, R12      # fell through
    SW R1, R14, 2
s9br2:
    LI R10, s9br3
    BR LT, R10
    MOV R9, R12      # fell through
    SW R1, R14, 3
s9br3:
    LI R10, s9br4
    BR GTE, R10
    MOV R8, R12      # fell through
    SW R1, R14, 4
s9br4:
    LI R10, s9br5
    BR LTE, R10
    MOV R9, R12      # fell through
    SW R1, R14, 5
s9br5:
    LI R10, s9br6
    BR OVFL, R10
    MOV R8, R12      # fell through
    SW R1, R14, 6
s9br6:
    LI R10, s9br7
    BR UNCOND, R10
    MOV R9, R12      # fell through
    SW R1, R14, 7
s9br7:
    HLT
