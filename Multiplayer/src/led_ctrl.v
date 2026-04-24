// =============================================================================
// led_ctrl.v — LED Controller
// =============================================================================
// Holds a 16-bit LED pattern written by the CPU via MMIO.
// The CPU writes to MMIO_LED_W (0x200C) to update the LED state.
//
// Usage in game:
//   - All LEDs ON during crash animation
//   - Partial pattern during gameplay (e.g., lives remaining)
//   - All LEDs OFF at game start / reset
//
// Reset polarity: active-LOW (matches pipeline.v convention)
// =============================================================================
`timescale 1ns/1ps

module led_ctrl (
    input  wire        clk,           // fast board clock
    input  wire        reset,         // active-LOW reset
    input  wire        we,            // write enable from mmio_decoder
    input  wire [15:0] wdata,         // 16-bit data from CPU (dmem_wdata[15:0])
    output reg  [15:0] led_out        // to physical LED pins (active-HIGH on Nexys A7)
);

    always @(posedge clk or negedge reset) begin
        if (!reset)
            led_out <= 16'h0000;      // all LEDs off on reset
        else if (we)
            led_out <= wdata;         // capture new pattern from CPU
        // else: hold current value
    end

endmodule
