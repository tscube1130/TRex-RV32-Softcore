//  OPCODE and parameter definitions

`define OPCODE      6:0
`define FUNC3       14:12
`define SUBTYPE     30
`define RD          11:7
`define RS1         19:15
`define RS2         24:20


localparam  [31: 0] NOP        = 32'h0000_0013;     // addi x0, x0, 0

// OPCODE, INST[6:0]
localparam  [ 6: 0] LUI     = 7'b0110111,        // U-type
                    JAL     = 7'b1101111,        // J-type
                    JALR    = 7'b1100111,        // I-type
                    BRANCH  = 7'b1100011,        // B-type
                    LOAD    = 7'b0000011,        // I-type
                    STORE   = 7'b0100011,        // S-type
                    ARITHI  = 7'b0010011,        // I-type
                    ARITHR  = 7'b0110011;        // R-type



// FUNC3, INST[14:12], INST[6:0] = 7'b1100011
localparam  [ 2: 0] BEQ     = 3'b000,
                    BNE     = 3'b001,
                    BLT     = 3'b100,
                    BGE     = 3'b101,
                    BLTU    = 3'b110,
                    BGEU    = 3'b111;

// FUNC3, INST[14:12], INST[6:0] = 7'b0000011
localparam  [ 2: 0] LB      = 3'b000,
                    LH      = 3'b001,
                    LW      = 3'b010,
                    LBU     = 3'b100,
                    LHU     = 3'b101;

// FUNC3, INST[14:12], INST[6:0] = 7'b0100011
localparam  [ 2: 0] SB      = 3'b000,
                    SH      = 3'b001,
                    SW      = 3'b010;
                    
// FUNC3, INST[14:12], INST[6:0] = 7'b0110011, 7'b0010011
localparam  [ 2: 0] ADD     = 3'b000,    // inst[30] == 0: ADD, inst[31] == 1: SUB
                    SLL     = 3'b001,
                    SLT     = 3'b010,
                    SLTU    = 3'b011,
                    XOR     = 3'b100,
                    SR      = 3'b101,    // inst[30] == 0: SRL, inst[31] == 1: SRA
                    OR      = 3'b110,
                    AND     = 3'b111;

// =================================================================
// DSP / M-EXTENSION IDENTIFIERS (FUNC7)
// These share the ARITHR opcode (7'b0110011)
// =================================================================
localparam [6:0] M_EXT   = 7'b0000001; // Standard RV32M Extension
localparam [6:0] MAC_EXT = 7'b0000010; // Custom DSP Extension

// =================================================================
// RV32M FUNC3 DEFINITIONS (When FUNC7 == M_EXT)
// =================================================================
localparam [2:0] MUL    = 3'b000, // Lower 32 bits of Rs1 * Rs2
                 MULH   = 3'b001, // Upper 32 bits (Signed x Signed)
                 MULHSU = 3'b010, // Upper 32 bits (Signed x Unsigned)
                 MULHU  = 3'b011, // Upper 32 bits (Unsigned x Unsigned)
                 DIV    = 3'b100, // Rs1 / Rs2 (Signed)
                 DIVU   = 3'b101, // Rs1 / Rs2 (Unsigned)
                 REM    = 3'b110, // Remainder (Signed)
                 REMU   = 3'b111; // Remainder (Unsigned)

// =================================================================
// CUSTOM MAC FUNC3 DEFINITIONS (When FUNC7 == MAC_EXT)
// =================================================================
localparam [2:0] MAC    = 3'b000, // Accumulator = Accumulator + (Rs1 * Rs2)
                 MVACC  = 3'b001; // Rd = Accumulator