// =============================================================================
// seg7_mux.v — 8-Digit 7-Segment Display Multiplexer (BANK SWITCHING EDITION)
// =============================================================================
`timescale 1ns/1ps

module seg7_mux #(
    parameter REFRESH_COUNT = 100_000   // switch digit every 1 ms at 100 MHz
)(
    input  wire        clk,         
    input  wire        reset,       

    // Latched MMIO data (written by CPU)
    input  wire [31:0] seg_data0,  // digits 3..0 (Score)
    input  wire [31:0] seg_data1,  // digits 7..4 (Game Graphics / Text)

    // Nexys A7 display outputs
    output reg  [6:0]  seg,         
    output reg  [7:0]  an,          
    output wire        dp           
);

    assign dp = 1'b1;

    reg [$clog2(REFRESH_COUNT)-1:0] refresh_cnt;
    reg [2:0] digit_sel;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            refresh_cnt <= 0;
            digit_sel   <= 3'd0;
        end else begin
            if (refresh_cnt == REFRESH_COUNT - 1) begin
                refresh_cnt <= 0;
                digit_sel   <= digit_sel + 1'b1; 
            end else begin
                refresh_cnt <= refresh_cnt + 1;
            end
        end
    end

    always @(*) begin
        an = 8'b1111_1111;
        an[digit_sel] = 1'b0;
    end

    reg [3:0] digit_nibble;
    always @(*) begin
        case (digit_sel)
            3'd0: digit_nibble = seg_data0[3:0];    
            3'd1: digit_nibble = seg_data0[7:4];
            3'd2: digit_nibble = seg_data0[11:8];
            3'd3: digit_nibble = seg_data0[15:12];
            3'd4: digit_nibble = seg_data1[3:0];
            3'd5: digit_nibble = seg_data1[7:4];
            3'd6: digit_nibble = seg_data1[11:8];
            3'd7: digit_nibble = seg_data1[15:12];  
            default: digit_nibble = 4'hF;
        endcase
    end

    // =========================================================================
    // THE SECRET HARDWARE BANK SWITCH
    // If Bit 31 of seg_data1 is HIGH, swap to the Text Dictionary!
    // =========================================================================
    wire text_mode = seg_data1[31];

    always @(*) begin
        if (text_mode && digit_sel >= 3'd4) begin
            // --- BANK 1: HIDDEN TEXT DICTIONARY (For W/L Screens Only) ---
            case (digit_nibble)
                4'h1: seg = 7'b100_0001; // Perfect 'U' (b,c,d,e,f ON)
                4'h2: seg = 7'b111_1001; // Perfect 'I' (b,c ON)
                4'h3: seg = 7'b010_1011; // Perfect 'n' (c,e,g ON)
                4'h4: seg = 7'b100_0111; // Perfect 'L' (d,e,f ON)
                4'h5: seg = 7'b100_0000; // Perfect 'O' (a,b,c,d,e,f ON)
                4'h6: seg = 7'b001_0010; // Perfect 'S' (a,c,d,f,g ON)
                4'h7: seg = 7'b000_0110; // Perfect 'E' (a,d,e,f,g ON)
                default: seg = 7'b111_1111; // Blank
            endcase
        end else begin
            // --- BANK 0: STANDARD GAME DICTIONARY (Score & Gameplay) ---
            case (digit_nibble)
                4'h0: seg = 7'b100_0000; // Normal Score 0
                4'h1: seg = 7'b111_1001; // Normal Score 1
                4'h2: seg = 7'b010_0100; // Normal Score 2
                4'h3: seg = 7'b011_0000; // Normal Score 3
                4'h4: seg = 7'b001_1001; // Normal Score 4
                4'h5: seg = 7'b001_0010; // Normal Score 5
                4'h6: seg = 7'b000_0010; // Normal Score 6
                4'h7: seg = 7'b111_1000; // Normal Score 7
                4'h8: seg = 7'b000_0000; // Normal Score 8
                4'h9: seg = 7'b001_0000; // Normal Score 9
                4'hA: seg = 7'b111_1111; // BLANK
                4'hB: seg = 7'b100_1001; // DINO GROUND
                4'hC: seg = 7'b101_1100; // DINO AIR
                4'hD: seg = 7'b000_1000; // CACTUS
                default: seg = 7'b111_1111; 
            endcase
        end
    end
endmodule