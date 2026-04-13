// =============================================================================
// seg7_mux.v — 8-Digit 7-Segment Display Multiplexer
// =============================================================================
// Drives the Nexys A7's 8 on-board 7-segment digits via time-division multiplexing.
//
// MMIO Interface (2 × 32-bit write registers):
//   seg_data0 [31:0] — packed nibbles for digits 3..0
//                       [15:12]=digit3  [11:8]=digit2  [7:4]=digit1  [3:0]=digit0
//   seg_data1 [31:0] — packed nibbles for digits 7..4
//                       [15:12]=digit7  [11:8]=digit6  [7:4]=digit5  [3:0]=digit4
//
// =============================================================================
// GAME NIBBLE ENCODING (tell Sanjeebani to use these nibble values):
// =============================================================================
//   0x0 - 0x9 : Score digits 0-9  (standard decimal)
//   0xA       : BLANK             — empty track position   (all segments off)
//   0xB       : DINO (ground)     — dino standing: "II" shape (b,c,e,f segments)
//   0xC       : DINO (air)        — dino jumping:  "⊓" shape (a,b,f segments)
//   0xD       : CACTUS            — cactus shape:  "8-bottom" (a,b,c,e,f,g — no d)
//   0xE       : BLANK (spare)
//   0xF       : BLANK (spare)
//
// GAME DISPLAY LAYOUT (8 digits, leftmost=7, rightmost=0):
//   Normal:  [DINO(B)][blank][blank][blank][blank][blank][blank][CACTUS(D)]
//   Jump:    [DINO(C)][blank][blank][blank][blank][blank][CACTUS(D)][blank]
//   Pair:    [DINO(B)][blank][blank][blank][blank][CACTUS(D)][CACTUS(D)][blank]
//            → pair cactus = nibble 0xD on TWO adjacent digits
//
// Score display: write BCD digits to the leftmost digits (separate seg_data1 write)
// =============================================================================
//
// Segment naming:  {g,f,e,d,c,b,a}  (active-LOW: 0=ON, 1=OFF)
//        aaa
//       f   b
//       f   b
//        ggg
//       e   c
//       e   c
//        ddd
//
// Outputs (Nexys A7 standard):
//   seg[6:0]  — active-LOW segment lines {CG, CF, CE, CD, CC, CB, CA}
//   an[7:0]   — active-LOW anode enables (one LOW at a time = which digit is lit)
//   dp        — decimal point (active-LOW; driven HIGH = off unless needed)
//
// Refresh rate:
//   REFRESH_COUNT = 100_000 → at 100 MHz each digit is active for 1 ms
//   Full 8-digit cycle = 8 ms → 125 Hz per digit, well above flicker threshold
//
// Reset polarity: active-LOW (matches pipeline.v convention)
// =============================================================================
`timescale 1ns/1ps

module seg7_mux #(
    parameter REFRESH_COUNT = 100_000   // switch digit every 1 ms at 100 MHz
)(
    input  wire        clk,         // fast board clock (100 MHz)
    input  wire        reset,       // active-LOW reset

    // Latched MMIO data (written by CPU)
    input  wire [31:0] seg_data0,  // digits 3..0 (each nibble = one digit)
    input  wire [31:0] seg_data1,  // digits 7..4

    // Nexys A7 display outputs
    output reg  [6:0]  seg,         // segment lines (active-LOW)
    output reg  [7:0]  an,          // anode enables (active-LOW)
    output wire        dp           // decimal point (tie HIGH = off)
);

    assign dp = 1'b1;   // decimal point off by default

    // -------------------------------------------------------------------------
    // Refresh counter & digit selector
    // -------------------------------------------------------------------------
    reg [$clog2(REFRESH_COUNT)-1:0] refresh_cnt;
    reg [2:0] digit_sel;    // 0..7 selects which digit is active

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            refresh_cnt <= 0;
            digit_sel   <= 3'd0;
        end else begin
            if (refresh_cnt == REFRESH_COUNT - 1) begin
                refresh_cnt <= 0;
                digit_sel   <= digit_sel + 1'b1;   // wraps 7→0 naturally
            end else begin
                refresh_cnt <= refresh_cnt + 1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Anode enable — pull active digit LOW, all others HIGH
    // -------------------------------------------------------------------------
    always @(*) begin
        an = 8'b1111_1111;
        an[digit_sel] = 1'b0;
    end

    // -------------------------------------------------------------------------
    // Digit nibble selection from packed MMIO registers
    // -------------------------------------------------------------------------
    reg [3:0] digit_nibble;

    always @(*) begin
        case (digit_sel)
            3'd0: digit_nibble = seg_data0[3:0];    // digit 0 (rightmost)
            3'd1: digit_nibble = seg_data0[7:4];
            3'd2: digit_nibble = seg_data0[11:8];
            3'd3: digit_nibble = seg_data0[15:12];
            3'd4: digit_nibble = seg_data1[3:0];
            3'd5: digit_nibble = seg_data1[7:4];
            3'd6: digit_nibble = seg_data1[11:8];
            3'd7: digit_nibble = seg_data1[15:12];  // digit 7 (leftmost)
            default: digit_nibble = 4'hF;
        endcase
    end

    // -------------------------------------------------------------------------
    // 7-segment decoder (active-LOW: 0=segment ON, 1=segment OFF)
    // Bit order: {g, f, e, d, c, b, a}
    //
    // Nibbles 0-9  : standard score digits
    // Nibbles A-F  : game-specific characters (dino, cactus, blank)
    // -------------------------------------------------------------------------
    always @(*) begin
        case (digit_nibble)
            // ------ Score digits (standard decimal) ------
            4'h0: seg = 7'b100_0000;   // digit 0
            4'h1: seg = 7'b111_1001;   // digit 1
            4'h2: seg = 7'b010_0100;   // digit 2
            4'h3: seg = 7'b011_0000;   // digit 3
            4'h4: seg = 7'b001_1001;   // digit 4
            4'h5: seg = 7'b001_0010;   // digit 5
            4'h6: seg = 7'b000_0010;   // digit 6
            4'h7: seg = 7'b111_1000;   // digit 7
            4'h8: seg = 7'b000_0000;   // digit 8
            4'h9: seg = 7'b001_0000;   // digit 9

            // ------ Game characters ------
            // 0xA: BLANK — empty track position (all segments off)
            4'hA: seg = 7'b111_1111;

            // 0xB: DINO (ground) — "II" shape: left+right verticals, no bars
            //   Segments ON: f(top-left), e(bot-left), b(top-right), c(bot-right)
            //   Segments OFF: a(top), d(bot), g(mid)
            //   Visual: two vertical bars side-by-side = dino body standing on ground
            4'hB: seg = 7'b100_1001;   // {g=1,f=0,e=0,d=1,c=0,b=0,a=1}

            // 0xC: DINO (air/jumping) — "⊓" shape: top + upper-left + upper-right
            //   Segments ON: a(top), f(top-left), b(top-right)
            //   Segments OFF: e, d, c, g
            //   Visual: top bracket = dino at apex of jump (only upper body visible)
            4'hC: seg = 7'b101_1100;   // {g=1,f=0,e=1,d=1,c=1,b=0,a=0}

            // 0xD: CACTUS — "8-no-bottom" shape: all except bottom bar
            //   Segments ON: a(top), b, c, e, f, g — all except d(bottom)
            //   Visual: T-shape cactus silhouette with arms
            //   PAIR cactus: write 0xD on TWO adjacent digits
            4'hD: seg = 7'b000_1000;   // {g=0,f=0,e=0,d=1,c=0,b=0,a=0}

            // 0xE, 0xF: BLANK (spare, same as 0xA)
            4'hE: seg = 7'b111_1111;
            4'hF: seg = 7'b111_1111;

            default: seg = 7'b111_1111; // all off
        endcase
    end

endmodule
