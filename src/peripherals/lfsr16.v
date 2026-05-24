// =============================================================================
// lfsr16.v — 16-bit Maximal-Length Linear Feedback Shift Register
// =============================================================================
// Taps: bits [15, 13, 12, 10] (standard Galois LFSR, period = 2^16 - 1 = 65535)
// Runs continuously every clock cycle independent of the CPU.
// The MMIO decoder exposes lfsr_out to the CPU as a read-only register.
//
// Reset seed: 16'hACE1 (non-zero — a zero seed locks the LFSR forever)
// Reset polarity: active-LOW (matches pipeline.v convention)
// =============================================================================
`timescale 1ns/1ps

module lfsr16 (
    input  wire        clk,       // fast board clock (100 MHz)
    input  wire        reset,     // active-LOW reset
    output wire [15:0] lfsr_out   // current LFSR state (read via MMIO)
);

    reg [15:0] lfsr_reg;

    // Feedback tap: XOR of bits 15, 13, 12, 10 (0-indexed from LSB)
    // Polynomial: x^16 + x^14 + x^13 + x^11 + 1
    wire feedback = lfsr_reg[15] ^ lfsr_reg[13] ^ lfsr_reg[12] ^ lfsr_reg[10];

    always @(posedge clk or negedge reset) begin
        if (!reset)
            lfsr_reg <= 16'hACE1;           // non-zero seed
        else
            lfsr_reg <= {lfsr_reg[14:0], feedback};  // shift left, insert feedback
    end

    assign lfsr_out = lfsr_reg;

endmodule
