// =============================================================================
// tb_debouncer.v — Testbench for debouncer.v
// =============================================================================
// Tests:
//   1. Short glitch (< debounce time) → btn_stable stays LOW
//   2. Sustained press (> debounce time) → btn_stable goes HIGH
//   3. Sticky latch: press → release → sticky stays HIGH
//   4. CPU clear: sticky drops LOW after clear pulse
//   5. KEY TEST: sticky stays HIGH during a simulated pipeline stall
//      (no clear asserted during stall → jump not lost)
// =============================================================================
`timescale 1ns/1ps

module tb_debouncer;

    // -------------------------------------------------------------------------
    // Use a small SETTLE_CYCLES for simulation speed (20 cycles = 200 ns)
    // -------------------------------------------------------------------------
    localparam SETTLE = 20;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg  clk, reset;
    reg  btn_raw;
    reg  clear;
    wire btn_stable;
    wire btn_sticky;

    // -------------------------------------------------------------------------
    // DUT instantiation with shortened settle time for simulation
    // -------------------------------------------------------------------------
    debouncer #(.SETTLE_CYCLES(SETTLE)) dut (
        .clk        (clk),
        .reset      (reset),
        .btn_raw    (btn_raw),
        .clear      (clear),
        .btn_stable (btn_stable),
        .btn_sticky (btn_sticky)
    );

    // -------------------------------------------------------------------------
    // Clock: 10 ns period
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    integer pass, fail;

    task check;
        input [127:0] test_name;
        input         got;
        input         expected;
        begin
            if (got === expected) begin
                $display("PASS [%0s] got=%b", test_name, got);
                pass = pass + 1;
            end else begin
                $display("FAIL [%0s] expected=%b got=%b", test_name, expected, got);
                fail = fail + 1;
            end
        end
    endtask

    task wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
            #1;
        end
    endtask

    // -------------------------------------------------------------------------
    // Test stimulus
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_debouncer.vcd");
        $dumpvars(0, tb_debouncer);

        pass = 0; fail = 0;
        btn_raw = 0;
        clear   = 0;

        // Apply reset
        reset = 0;
        wait_cycles(3);
        reset = 1;
        wait_cycles(2);

        // -----------------------------------------------------------------
        // TEST 1: Short glitch — press for SETTLE/2 cycles, should NOT propagate
        // -----------------------------------------------------------------
        $display("=== TEST 1: Short glitch (<settle time) stays LOW ===");
        btn_raw = 1;
        wait_cycles(SETTLE / 2);
        btn_raw = 0;
        wait_cycles(SETTLE + 5);   // wait long enough for debouncer to settle back
        check("T1_stable_stays_low", btn_stable, 1'b0);
        check("T1_sticky_stays_low", btn_sticky, 1'b0);

        // -----------------------------------------------------------------
        // TEST 2: Sustained press — hold for > SETTLE cycles → should go HIGH
        // -----------------------------------------------------------------
        $display("=== TEST 2: Sustained press (>settle time) goes HIGH ===");
        btn_raw = 1;
        wait_cycles(SETTLE + 5);
        check("T2_stable_high",  btn_stable, 1'b1);
        check("T2_sticky_high",  btn_sticky, 1'b1);

        // -----------------------------------------------------------------
        // TEST 3: Release button — stable drops but sticky stays HIGH
        // -----------------------------------------------------------------
        $display("=== TEST 3: Release — stable drops, sticky HOLDS ===");
        btn_raw = 0;
        wait_cycles(SETTLE + 5);
        check("T3_stable_dropped", btn_stable, 1'b0);
        check("T3_sticky_held",    btn_sticky, 1'b1);  // ← must hold!

        // -----------------------------------------------------------------
        // TEST 4: CPU clears sticky latch
        // -----------------------------------------------------------------
        $display("=== TEST 4: CPU clear drops sticky ===");
        @(posedge clk); #1;
        clear = 1;
        @(posedge clk); #1;
        clear = 0;
        @(posedge clk); #1;
        check("T4_sticky_cleared", btn_sticky, 1'b0);

        // -----------------------------------------------------------------
        // TEST 5: STICKY SURVIVES STALL
        // Simulate: button pressed, CPU is in a ~34-cycle DIV stall (no clear),
        // sticky must still be HIGH after stall ends.
        // -----------------------------------------------------------------
        $display("=== TEST 5: Sticky survives 34-cycle stall (no clear) ===");
        // Press button
        btn_raw = 1;
        wait_cycles(SETTLE + 5);
        check("T5_sticky_set_before_stall", btn_sticky, 1'b1);

        // Simulate stall: no clear for 34 cycles (pipeline frozen during DIV)
        btn_raw = 0;
        wait_cycles(34);

        // Stall ends — check sticky is still there for CPU to read
        check("T5_sticky_survived_stall", btn_sticky, 1'b1);

        // Now CPU reads and clears
        clear = 1;
        @(posedge clk); #1;
        clear = 0;
        @(posedge clk); #1;
        check("T5_sticky_cleared_after_stall", btn_sticky, 1'b0);

        // -----------------------------------------------------------------
        // TEST 6: Multiple rapid presses — sticky latches first, stays high
        // -----------------------------------------------------------------
        $display("=== TEST 6: Rapid double press — sticky latches correctly ===");
        // First press
        btn_raw = 1;
        wait_cycles(SETTLE + 5);
        btn_raw = 0;
        wait_cycles(5);
        // Second press before clear
        btn_raw = 1;
        wait_cycles(SETTLE + 5);
        btn_raw = 0;
        wait_cycles(5);
        check("T6_sticky_still_high", btn_sticky, 1'b1);
        // Clear both
        clear = 1;
        @(posedge clk); #1;
        clear = 0;
        @(posedge clk); #1;
        check("T6_cleared", btn_sticky, 1'b0);

        // -----------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------
        $display("====================================");
        $display("RESULTS: %0d PASSED, %0d FAILED", pass, fail);
        $display("====================================");
        $finish;
    end

endmodule
