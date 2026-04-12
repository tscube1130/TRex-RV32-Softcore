// =============================================================================
// debouncer.v — Sticky Button Debouncer
// =============================================================================
// Two-stage output:
//   btn_stable  : debounced button signal (HIGH only while physically held)
//   btn_sticky  : latches HIGH on any press; stays HIGH until CPU clears it
//                 This ensures jump inputs are NOT lost during pipeline stalls
//                 (e.g., the ~32-cycle DIV stall from math_coproc.v)
//
// Debounce time: SETTLE_CYCLES clocks of steady input before state changes.
//   At 100 MHz with SETTLE_CYCLES=1_000_000 → 10 ms (standard mechanical debounce)
//
// Sticky clear: CPU writes to MMIO_BTN_CLR (0x2004) → mmio_decoder asserts clear
//
// Reset polarity: active-LOW (matches pipeline.v convention)
// =============================================================================
`timescale 1ns/1ps

module debouncer #(
    parameter SETTLE_CYCLES = 1_000_000   // 10 ms debounce at 100 MHz
)(
    input  wire clk,        // fast board clock (100 MHz)
    input  wire reset,      // active-LOW reset
    input  wire btn_raw,    // raw button signal from FPGA pin (active-HIGH)
    input  wire clear,      // from MMIO write: clear sticky latch
    output reg  btn_stable, // debounced level
    output reg  btn_sticky  // latched: HIGH from first press until CPU clears
);

    // -------------------------------------------------------------------------
    // Synchroniser — two-flop metastability chain on the async button input
    // -------------------------------------------------------------------------
    reg sync0, sync1;
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            sync0 <= 1'b0;
            sync1 <= 1'b0;
        end else begin
            sync0 <= btn_raw;
            sync1 <= sync0;
        end
    end

    // -------------------------------------------------------------------------
    // Debounce counter
    // -------------------------------------------------------------------------
    reg [$clog2(SETTLE_CYCLES)-1:0] counter;
    reg btn_prev;   // last stable state

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            counter    <= 0;
            btn_stable <= 1'b0;
            btn_prev   <= 1'b0;
        end else begin
            if (sync1 != btn_prev) begin
                // Input changed — restart settle timer
                counter  <= 0;
                btn_prev <= sync1;
            end else if (counter < SETTLE_CYCLES - 1) begin
                counter  <= counter + 1;
            end else begin
                // Input has been stable for SETTLE_CYCLES — accept it
                btn_stable <= btn_prev;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Sticky latch — set on rising edge of btn_stable, cleared by CPU
    // -------------------------------------------------------------------------
    reg btn_stable_prev;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            btn_sticky      <= 1'b0;
            btn_stable_prev <= 1'b0;
        end else begin
            btn_stable_prev <= btn_stable;

            if (clear) begin
                // CPU explicitly cleared the latch (MMIO write)
                btn_sticky <= 1'b0;
            end else if (btn_stable && !btn_stable_prev) begin
                // Rising edge detected on debounced signal — latch it
                btn_sticky <= 1'b1;
            end
            // else: hold current value
        end
    end

endmodule
