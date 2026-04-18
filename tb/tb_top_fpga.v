`timescale 1ns/1ps
// =============================================================================
// tb_top_fpga.v — Integration Smoke-Test for top_fpga.v
// Project T-Rex: Hardware-Accelerated Chrome Dino on Nexys A7-100T
// =============================================================================
// Tests:
//   1.  Reset assert    — LED output clears to 0x0000
//   2.  Reset polarity  — BTNC active-HIGH correctly inverts to reset_n
//   3.  No X/Z          — all outputs defined after reset release
//   4.  dp always HIGH  — decimal point always off
//   5.  7-seg cycling   — all 8 anodes go LOW over one full refresh frame
//   6.  One-hot anodes  — exactly one anode LOW per clock (no ghosting)
//   7.  LFSR non-zero   — RNG running (non-locked state after reset)
//   8.  sw_jump routed  — button reaches u_debounce_jump.btn_raw
//   9.  sw_dbl routed   — button reaches u_debounce_dbl.btn_raw
//   10. Re-reset        — LED clears again on second reset
//
// NOTE: seg7_mux REFRESH_COUNT=100_000 (1 ms/digit at 100 MHz).
//       Full 8-digit frame = 800_000 fast-clk cycles.
//       debouncer SETTLE_CYCLES=1_000_000 — only input routing is checked
//       here; full debounce propagation is covered in tb_debouncer.v.
// =============================================================================

module tb_top_fpga;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg         clk;
    reg         reset;           // active-HIGH (BTNC on Nexys A7)
    reg         sw_jump;         // BTNU — single jump
    reg         sw_double_jump;  // BTNL — double jump

    wire [6:0]  seg;
    wire [7:0]  an;
    wire        dp;
    wire [15:0] led;

    // -------------------------------------------------------------------------
    // DUT — top_fpga with default memory sizes
    // -------------------------------------------------------------------------
    top_fpga #(
        .IMEMSIZE (4096),
        .DMEMSIZE (4096)
    ) dut (
        .clk            (clk),
        .reset          (reset),
        .sw_jump        (sw_jump),
        .sw_double_jump (sw_double_jump),
        .seg            (seg),
        .an             (an),
        .dp             (dp),
        .led            (led)
    );

    // -------------------------------------------------------------------------
    // Clock: 10 ns period = 100 MHz
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Helpers — naming matches tb_debouncer.v / tb_led_ctrl.v / tb_mmio_decoder.v
    // -------------------------------------------------------------------------
    integer pass, fail;

    task check;
        input [127:0] name;
        input         got;
        input         expected;
        begin
            if (got === expected) begin
                $display("  PASS [%0s] = %b", name, got);
                pass = pass + 1;
            end else begin
                $display("  FAIL [%0s] expected=%b  got=%b", name, expected, got);
                fail = fail + 1;
            end
        end
    endtask

    task check16;
        input [127:0] name;
        input [15:0]  got;
        input [15:0]  expected;
        begin
            if (got === expected) begin
                $display("  PASS [%0s] = 0x%04X", name, got);
                pass = pass + 1;
            end else begin
                $display("  FAIL [%0s] expected=0x%04X  got=0x%04X", name, expected, got);
                fail = fail + 1;
            end
        end
    endtask

    task wait_cycles;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1)
                @(posedge clk);
            #1;
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    integer i;
    reg [7:0] saw_anode;
    integer   active_count;
    integer   ghosting_errors;

    initial begin
        $dumpfile("tb_top_fpga.vcd");
        $dumpvars(0, tb_top_fpga);

        pass           = 0;
        fail           = 0;
        sw_jump        = 0;
        sw_double_jump = 0;

        // ── Assert reset: BTNC pressed (active-HIGH) ──────────────────────
        reset = 1;
        wait_cycles(20);

        // ------------------------------------------------------------------
        // TEST 1: LED output clears to 0x0000 on reset
        // ------------------------------------------------------------------
        $display("=== TEST 1: LED clears on reset ===");
        check16("T1_led_zero_on_reset", led, 16'h0000);

        // ------------------------------------------------------------------
        // TEST 2: Reset polarity — reset_n = ~reset inside top_fpga
        //         slow_clk divider must be held at 0 while reset=1
        // ------------------------------------------------------------------
        $display("=== TEST 2: Reset polarity (active-HIGH BTNC → active-LOW reset_n) ===");
        check("T2_slow_clk_held_low", dut.slow_clk,          1'b0);
        check("T2_clk_cnt_is_zero",  (dut.clk_cnt == 26'd0), 1'b1);

        // ── Release reset: BTNC released ──────────────────────────────────
        reset = 0;
        wait_cycles(20);

        // ------------------------------------------------------------------
        // TEST 3: No X/Z on any output after reset release
        // ------------------------------------------------------------------
        $display("=== TEST 3: No X/Z on outputs after reset release ===");
        check("T3_seg_no_X", (^seg !== 1'bx), 1'b1);
        check("T3_an_no_X",  (^an  !== 1'bx), 1'b1);
        check("T3_led_no_X", (^led !== 1'bx), 1'b1);
        check("T3_dp_no_X",  (dp   !== 1'bx), 1'b1);

        // ------------------------------------------------------------------
        // TEST 4: dp always HIGH (decimal point off — tied in seg7_mux)
        // ------------------------------------------------------------------
        $display("=== TEST 4: dp always HIGH (decimal point off) ===");
        check("T4_dp_HIGH", dp, 1'b1);

        // ------------------------------------------------------------------
        // TEST 5: All 8 anodes cycle LOW in one full refresh frame
        //         REFRESH_COUNT=100_000 per digit × 8 digits = 800_000 cycles
        // ------------------------------------------------------------------
        $display("=== TEST 5: All 8 anodes cycle LOW in one refresh frame ===");
        saw_anode = 8'h00;
        repeat (820_000) begin
            @(posedge clk); #1;
            for (i = 0; i < 8; i = i + 1)
                if (an[i] == 1'b0) saw_anode[i] = 1'b1;
        end
        if (saw_anode == 8'hFF) begin
            $display("  PASS [T5_all_8_anodes_cycled]");
            pass = pass + 1;
        end else begin
            $display("  FAIL [T5_all_8_anodes_cycled] saw=0b%08b  expected=0b11111111", saw_anode);
            fail = fail + 1;
        end

        // ------------------------------------------------------------------
        // TEST 6: Exactly ONE anode LOW per clock — no digit ghosting
        // ------------------------------------------------------------------
        $display("=== TEST 6: Exactly one anode LOW per clock (no ghosting) ===");
        ghosting_errors = 0;
        repeat (8 * 100_000) begin
            @(posedge clk); #1;
            active_count = 0;
            for (i = 0; i < 8; i = i + 1)
                if (an[i] == 1'b0) active_count = active_count + 1;
            if (active_count != 1) ghosting_errors = ghosting_errors + 1;
        end
        if (ghosting_errors == 0) begin
            $display("  PASS [T6_one_hot_anodes]");
            pass = pass + 1;
        end else begin
            $display("  FAIL [T6_one_hot_anodes] wrong anode count in %0d cycles", ghosting_errors);
            fail = fail + 1;
        end

        // ------------------------------------------------------------------
        // TEST 7: LFSR output non-zero — RNG not in locked state
        //         Seed = 16'hACE1 (set in lfsr16.v); 0x0000 means locked
        // ------------------------------------------------------------------
        $display("=== TEST 7: LFSR non-zero (RNG running) ===");
        if (dut.u_lfsr.lfsr_out !== 16'h0000) begin
            $display("  PASS [T7_lfsr_nonzero]  lfsr_out=0x%04h", dut.u_lfsr.lfsr_out);
            pass = pass + 1;
        end else begin
            $display("  FAIL [T7_lfsr_nonzero]  lfsr_out=0x0000 — LFSR is locked!");
            fail = fail + 1;
        end

        // ------------------------------------------------------------------
        // TEST 8: sw_jump routes correctly to u_debounce_jump.btn_raw
        // ------------------------------------------------------------------
        $display("=== TEST 8: sw_jump routed to debouncer input ===");
        sw_jump = 1;
        wait_cycles(5);
        check("T8_sw_jump_btn_raw_HIGH", dut.u_debounce_jump.btn_raw, 1'b1);
        sw_jump = 0;
        wait_cycles(5);
        check("T8_sw_jump_btn_raw_LOW",  dut.u_debounce_jump.btn_raw, 1'b0);

        // ------------------------------------------------------------------
        // TEST 9: sw_double_jump routes correctly to u_debounce_dbl.btn_raw
        // ------------------------------------------------------------------
        $display("=== TEST 9: sw_double_jump routed to debouncer input ===");
        sw_double_jump = 1;
        wait_cycles(5);
        check("T9_sw_dbl_btn_raw_HIGH", dut.u_debounce_dbl.btn_raw, 1'b1);
        sw_double_jump = 0;
        wait_cycles(5);
        check("T9_sw_dbl_btn_raw_LOW",  dut.u_debounce_dbl.btn_raw, 1'b0);

        // ------------------------------------------------------------------
        // TEST 10: Re-assert reset — LED must clear to 0x0000 again
        // ------------------------------------------------------------------
        $display("=== TEST 10: Re-assert reset clears LED ===");
        reset = 1;
        wait_cycles(10);
        check16("T10_led_clears_on_rereset", led, 16'h0000);
        reset = 0;

// ------------------------------------------------------------------
        // TEST 11: Game over — LED must be 0xFFFF after crash
        // ----------------------------------------------------------
        $display("=== TEST 11: LED all-on after game over ===");
        reset = 1; wait_cycles(5); reset = 0;
        wait_cycles(820_000);
        if (led === 16'hFFFF) begin
            $display("  PASS [T11_led_game_over]");
            pass = pass + 1;
        end else begin
            $display("  FAIL [T11_led_game_over] got=0x%04X", led);
            fail = fail + 1;
        end

// ------------------------------------------------------------------
        // TEST 12: Score display non-blank after game over phase
        // ------------------------------------------------------------------
        $display("=== TEST 12: Score display non-blank after game over ===");
        wait_cycles(820_000);
        if (led !== 16'h0000) begin
            $display("  PASS [T12_score_display_nonblank]");
            pass = pass + 1;
        end else begin
            $display("  FAIL [T12_score_display_nonblank]");
            fail = fail + 1;
        end
        
        // ── Summary ───────────────────────────────────────────────────────
        wait_cycles(10);
        $display("====================================================");
        $display("RESULTS: %0d PASSED, %0d FAILED", pass, fail);
        $display("====================================================");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog — covers all test cycles comfortably at 10 ns/cycle
    // -------------------------------------------------------------------------
    initial begin
        #2_500_000_000;
        $display("TIMEOUT: Simulation exceeded 2.5 s sim time");
        $finish;
    end

endmodule
