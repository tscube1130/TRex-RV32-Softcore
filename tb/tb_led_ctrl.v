// =============================================================================
// tb_led_ctrl.v — Testbench for led_ctrl.v
// =============================================================================
// Tests:
//   1. All LEDs OFF after reset
//   2. Write pattern → LEDs update correctly
//   3. LEDs HOLD value when we=0 (no write)
//   4. Overwrite with a new pattern → LEDs update
//   5. Write all ON (0xFFFF) → crash animation pattern
//   6. Write all OFF (0x0000) → clear
//   7. Write alternating pattern (0xAAAA / 0x5555) → left/right halves
// =============================================================================
`timescale 1ns/1ps

module tb_led_ctrl;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg         clk, reset;
    reg         we;
    reg  [15:0] wdata;
    wire [15:0] led_out;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    led_ctrl dut (
        .clk    (clk),
        .reset  (reset),
        .we     (we),
        .wdata  (wdata),
        .led_out(led_out)
    );

    // -------------------------------------------------------------------------
    // Clock: 10 ns period (100 MHz)
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    integer pass, fail;

    task check16;
        input [127:0] name;
        input [15:0]  got;
        input [15:0]  expected;
        begin
            if (got === expected) begin
                $display("  PASS [%0s] led_out=0x%04X", name, got);
                pass = pass + 1;
            end else begin
                $display("  FAIL [%0s] expected=0x%04X got=0x%04X", name, expected, got);
                fail = fail + 1;
            end
        end
    endtask

    // Write one pattern and check it appears on led_out next cycle
    task write_and_check;
        input [127:0] name;
        input [15:0]  pattern;
        begin
            we    = 1;
            wdata = pattern;
            @(posedge clk); #1;   // latch on clock edge
            we    = 0;
            check16(name, led_out, pattern);
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_led_ctrl.vcd");
        $dumpvars(0, tb_led_ctrl);

        pass = 0; fail = 0;
        we    = 0;
        wdata = 16'h0000;

        // Reset
        reset = 0;
        @(negedge clk); #1;
        reset = 1;
        @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 1: All LEDs OFF after reset
        // ------------------------------------------------------------------
        $display("=== TEST 1: All LEDs OFF after reset ===");
        check16("T1_reset_all_off", led_out, 16'h0000);

        // ------------------------------------------------------------------
        // TEST 2: Write a pattern — LEDs update
        // ------------------------------------------------------------------
        $display("=== TEST 2: Write 0xBEEF ===");
        write_and_check("T2_write_BEEF", 16'hBEEF);

        // ------------------------------------------------------------------
        // TEST 3: LEDs HOLD when we=0
        // ------------------------------------------------------------------
        $display("=== TEST 3: LEDs hold value for 5 cycles with no write ===");
        we = 0;
        repeat(5) @(posedge clk);
        #1;
        check16("T3_hold_BEEF", led_out, 16'hBEEF);

        // ------------------------------------------------------------------
        // TEST 4: Overwrite with a new pattern
        // ------------------------------------------------------------------
        $display("=== TEST 4: Overwrite with 0x1234 ===");
        write_and_check("T4_overwrite_1234", 16'h1234);

        // ------------------------------------------------------------------
        // TEST 5: All LEDs ON — crash animation (0xFFFF)
        // ------------------------------------------------------------------
        $display("=== TEST 5: All ON — crash animation (0xFFFF) ===");
        write_and_check("T5_all_on_FFFF", 16'hFFFF);

        // ------------------------------------------------------------------
        // TEST 6: All LEDs OFF — game clear / reset state
        // ------------------------------------------------------------------
        $display("=== TEST 6: All OFF — clear (0x0000) ===");
        write_and_check("T6_all_off_0000", 16'h0000);

        // ------------------------------------------------------------------
        // TEST 7: Alternating patterns — left/right halves
        // ------------------------------------------------------------------
        $display("=== TEST 7: Alternating 0xAAAA (even LEDs) ===");
        write_and_check("T7a_pattern_AAAA", 16'hAAAA);

        $display("=== TEST 7: Alternating 0x5555 (odd LEDs) ===");
        write_and_check("T7b_pattern_5555", 16'h5555);

        // ------------------------------------------------------------------
        // TEST 8: we=0 with different wdata — output must NOT change
        // ------------------------------------------------------------------
        $display("=== TEST 8: we=0, changing wdata — output stays 0x5555 ===");
        we    = 0;
        wdata = 16'hDEAD;   // not we, so should NOT update
        @(posedge clk); #1;
        check16("T8_no_write_no_change", led_out, 16'h5555);

        // ------------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------------
        $display("====================================");
        $display("RESULTS: %0d PASSED, %0d FAILED", pass, fail);
        $display("====================================");
        $finish;
    end

endmodule
