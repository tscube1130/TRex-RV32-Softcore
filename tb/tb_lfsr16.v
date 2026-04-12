// =============================================================================
// tb_lfsr16.v — Testbench for lfsr16.v
// =============================================================================
// Tests:
//   1. Non-zero value after reset
//   2. Output changes every cycle
//   3. Never reaches zero (check 70,000 cycles — close to full 65,535 period)
//   4. Full period sanity (count unique values)
// =============================================================================
`timescale 1ns/1ps

module tb_lfsr16;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg  clk, reset;
    wire [15:0] lfsr_out;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    lfsr16 dut (
        .clk      (clk),
        .reset    (reset),
        .lfsr_out (lfsr_out)
    );

    // -------------------------------------------------------------------------
    // Clock: 10 ns period (100 MHz)
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Test tracking
    // -------------------------------------------------------------------------
    integer cycle_count;
    integer zero_count;
    integer repeat_count;
    reg [15:0] prev_val;
    integer pass, fail;

    initial begin
        $dumpfile("tb_lfsr16.vcd");
        $dumpvars(0, tb_lfsr16);

        pass = 0; fail = 0;

        // -----------------------------------------------------------------
        // TEST 1: Reset
        // Check seed COMBINATIONALLY right after reset deasserts —
        // BEFORE any posedge clk, so the LFSR hasn't shifted yet.
        // -----------------------------------------------------------------
        $display("=== TEST 1: Reset ===");
        reset = 0;
        @(negedge clk);     // align to a falling edge
        #1;                  // release reset just after falling edge
        reset = 1;
        #1;                  // tiny delay — read combinationally (no clock yet)

        if (lfsr_out != 16'h0000) begin
            $display("PASS: Output non-zero right after reset = 0x%04X", lfsr_out);
            pass = pass + 1;
        end else begin
            $display("FAIL: Output is zero right after reset!");
            fail = fail + 1;
        end

        // Seed should be exactly ACE1 before any clock edge
        if (lfsr_out == 16'hACE1) begin
            $display("PASS: Seed is correct (0xACE1) before first shift");
            pass = pass + 1;
        end else begin
            $display("FAIL: Seed mismatch, got 0x%04X (expected 0xACE1)", lfsr_out);
            fail = fail + 1;
        end

        // Now let one clock tick — LFSR should shift to 0x59C3
        // (ACE1 with taps [15,13,12,10]: feedback = 1^0^1^1 = 1 → 59C3)
        @(posedge clk); #1;
        if (lfsr_out == 16'h59C3) begin
            $display("PASS: First shift correct (ACE1 → 59C3)");
            pass = pass + 1;
        end else begin
            $display("FAIL: First shift wrong, got 0x%04X (expected 0x59C3)", lfsr_out);
            fail = fail + 1;
        end

        // -----------------------------------------------------------------
        // TEST 2 & 3: Run 70,000 cycles — check changes every cycle, never zero
        // NOTE: Set Vivado simulation runtime to 'all' to reach this test:
        //   Run → Simulation Settings → xsim.simulate.runtime = all
        // -----------------------------------------------------------------
        $display("=== TEST 2 & 3: 70,000 cycles — changes every cycle, never zero ===");
        prev_val    = lfsr_out;
        zero_count  = 0;
        repeat_count = 0;
        cycle_count = 0;

        repeat (70000) begin
            @(posedge clk); #1;
            if (lfsr_out == 16'h0000) zero_count = zero_count + 1;
            if (lfsr_out == prev_val)  repeat_count = repeat_count + 1;
            prev_val    = lfsr_out;
            cycle_count = cycle_count + 1;
        end

        if (zero_count == 0) begin
            $display("PASS: Never zero over %0d cycles", cycle_count);
            pass = pass + 1;
        end else begin
            $display("FAIL: Hit zero %0d times over %0d cycles!", zero_count, cycle_count);
            fail = fail + 1;
        end

        if (repeat_count == 0) begin
            $display("PASS: Output changed every cycle over %0d cycles", cycle_count);
            pass = pass + 1;
        end else begin
            $display("FAIL: Output repeated %0d times (no change consecutive cycles)!", repeat_count);
            fail = fail + 1;
        end

        // -----------------------------------------------------------------
        // TEST 4: Reset mid-run → check seed combinationally (before any shift)
        // -----------------------------------------------------------------
        $display("=== TEST 4: Mid-run reset returns to seed ===");
        reset = 0;
        @(negedge clk);
        #1;                  // release AFTER falling edge
        reset = 1;
        #1;                  // check combinationally — no clock yet

        if (lfsr_out == 16'hACE1) begin
            $display("PASS: Seed restored after mid-run reset (0xACE1)");
            pass = pass + 1;
        end else begin
            $display("FAIL: Not at seed after reset, got 0x%04X", lfsr_out);
            fail = fail + 1;
        end

        // -----------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------
        $display("====================================");
        $display("RESULTS: %0d PASSED, %0d FAILED", pass, fail);
        $display("====================================");
        $finish;
    end

endmodule
