// =============================================================================
// seg7_mux.v — 8-Digit 7-Segment Display Multiplexer
// =============================================================================
// Drives the Nexys A7's 8 on-board 7-segment digits via time-division multiplexing.
//
// MMIO Interface (2 × 32-bit write registers):
//   seg_data0 [31:0] — packed BCD/hex nibbles for digits 3..0
//                       [31:28]=digit3  [27:24]=digit2  [23:20]=digit1  [19:16]=digit0
//   seg_data1 [31:0] — packed BCD/hex nibbles for digits 7..4
//                       [31:28]=digit7  [27:24]=digit6  [23:20]=digit5  [19:16]=digit4
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
    // 7-segment decoder (active-LOW segments)
    // Segment order: {g, f, e, d, c, b, a}
    //
    //   aaa
    //  f   b
    //  f   b
    //   ggg
    //  e   c
    //  e   c
    //   ddd
    // -------------------------------------------------------------------------
    always @(*) begin
        case (digit_nibble)
            4'h0: seg = 7'b100_0000;   // 0
            4'h1: seg = 7'b111_1001;   // 1
            4'h2: seg = 7'b010_0100;   // 2
            4'h3: seg = 7'b011_0000;   // 3
            4'h4: seg = 7'b001_1001;   // 4
            4'h5: seg = 7'b001_0010;   // 5
            4'h6: seg = 7'b000_0010;   // 6
            4'h7: seg = 7'b111_1000;   // 7
            4'h8: seg = 7'b000_0000;   // 8
            4'h9: seg = 7'b001_0000;   // 9
            4'hA: seg = 7'b000_1000;   // A
            4'hB: seg = 7'b000_0011;   // b
            4'hC: seg = 7'b100_0110;   // C
            4'hD: seg = 7'b010_0001;   // d
            4'hE: seg = 7'b000_0110;   // E
            4'hF: seg = 7'b000_1110;   // F (also used for blank/error)
            default: seg = 7'b111_1111; // all off
        endcase
    end

endmodule
