// =============================================================================
// tb_seg7_mux.v — Testbench for seg7_mux.v
// =============================================================================
// Tests:
//   1. All 8 anodes cycle LOW over one full display frame
//   2. Exactly one anode active at a time (no ghosting)
//   3. Correct segment encoding for score digits 0–9
//   4. Correct segment encoding for game characters A–F:
//        0xA = BLANK  (7'b111_1111)
//        0xB = DINO ground (7'b100_1001)
//        0xC = DINO air    (7'b101_1100)
//        0xD = CACTUS      (7'b000_1000)
//        0xE = BLANK spare (7'b111_1111)
//        0xF = BLANK spare (7'b111_1111)
//   5. dp always HIGH (decimal point off)
//   6. Nibble extraction from seg_data0 / seg_data1
//   7. Dynamic update — seg_data changes mid-run, display follows
// =============================================================================
`timescale 1ns/1ps

module tb_seg7_mux;

    // Use small refresh count for simulation speed
    localparam REFRESH = 10;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg        clk, reset;
    reg [31:0] seg_data0, seg_data1;
    wire [6:0] seg;
    wire [7:0] an;
    wire       dp;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    seg7_mux #(.REFRESH_COUNT(REFRESH)) dut (
        .clk       (clk),
        .reset     (reset),
        .seg_data0 (seg_data0),
        .seg_data1 (seg_data1),
        .seg       (seg),
        .an        (an),
        .dp        (dp)
    );

    // -------------------------------------------------------------------------
    // Clock: 10 ns
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Expected segment encodings (active-LOW, {g,f,e,d,c,b,a})
    // MUST match seg7_mux.v decoder exactly.
    //
    // Score digits (0-9): standard 7-seg
    // Game characters:
    //   0xA BLANK        — all segments OFF  (7'b111_1111)
    //   0xB DINO ground  — "II" shape        (7'b100_1001)
    //   0xC DINO air     — "⊓" bracket shape (7'b101_1100)
    //   0xD CACTUS       — all-but-bottom    (7'b000_1000)
    //   0xE BLANK spare                      (7'b111_1111)
    //   0xF BLANK spare                      (7'b111_1111)
    // -------------------------------------------------------------------------
    function [6:0] expected_seg;
        input [3:0] nibble;
        case (nibble)
            // --- Score digits ---
            4'h0: expected_seg = 7'b100_0000;
            4'h1: expected_seg = 7'b111_1001;
            4'h2: expected_seg = 7'b010_0100;
            4'h3: expected_seg = 7'b011_0000;
            4'h4: expected_seg = 7'b001_1001;
            4'h5: expected_seg = 7'b001_0010;
            4'h6: expected_seg = 7'b000_0010;
            4'h7: expected_seg = 7'b111_1000;
            4'h8: expected_seg = 7'b000_0000;
            4'h9: expected_seg = 7'b001_0000;
            // --- Game characters (MUST match seg7_mux.v exactly) ---
            4'hA: expected_seg = 7'b111_1111;   // BLANK
            4'hB: expected_seg = 7'b100_1001;   // DINO ground
            4'hC: expected_seg = 7'b101_1100;   // DINO air
            4'hD: expected_seg = 7'b000_1000;   // CACTUS
            4'hE: expected_seg = 7'b111_1111;   // BLANK spare
            4'hF: expected_seg = 7'b111_1111;   // BLANK spare
            default: expected_seg = 7'b111_1111;
        endcase
    endfunction

    // Human-readable nibble name for display messages
    function [63:0] nibble_name;
        input [3:0] nibble;
        case (nibble)
            4'hA: nibble_name = "BLANK   ";
            4'hB: nibble_name = "DINO-GND";
            4'hC: nibble_name = "DINO-AIR";
            4'hD: nibble_name = "CACTUS  ";
            4'hE: nibble_name = "BLNK-SPA";
            4'hF: nibble_name = "BLNK-SPA";
            default: nibble_name = "SCORE   ";
        endcase
    endfunction

    integer pass, fail;
    integer i;
    integer d;
    reg [7:0] saw_anode;

    // -------------------------------------------------------------------------
    // check_seg: wait for digit 0 to be active then compare
    // -------------------------------------------------------------------------
    task check_seg;
        input [3:0] nibble;
        input [6:0] got;
        begin
            if (got === expected_seg(nibble)) begin
                $display("  PASS: 0x%X (%0s) seg=0b%07b", nibble, nibble_name(nibble), got);
                pass = pass + 1;
            end else begin
                $display("  FAIL: 0x%X (%0s) expected=0b%07b got=0b%07b",
                         nibble, nibble_name(nibble), expected_seg(nibble), got);
                fail = fail + 1;
            end
        end
    endtask

    task wait_cycles;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) @(posedge clk);
            #1;
        end
    endtask

    // Wait until digit d's anode goes LOW, with timeout
    task wait_for_digit;
        input integer dig;
        integer timeout;
        begin
            timeout = 0;
            while (an[dig] !== 1'b0 && timeout < 20*REFRESH) begin
                @(posedge clk); #1;
                timeout = timeout + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_seg7_mux.vcd");
        $dumpvars(0, tb_seg7_mux);

        pass = 0; fail = 0;

        seg_data0 = 32'h3210;   // digit3=3 digit2=2 digit1=1 digit0=0
        seg_data1 = 32'h7654;   // digit7=7 digit6=6 digit5=5 digit4=4

        // Reset (active-LOW)
        reset = 0;
        wait_cycles(3);
        reset = 1;
        wait_cycles(2);

        // -----------------------------------------------------------------
        // TEST 1: All 8 anodes cycle LOW over one full display frame
        // -----------------------------------------------------------------
        $display("=== TEST 1: All 8 digit anodes cycle through ===");
        saw_anode = 8'h00;
        repeat (8 * REFRESH + 4) begin
            @(posedge clk); #1;
            for (i = 0; i < 8; i = i + 1)
                if (!an[i]) saw_anode[i] = 1'b1;
        end
        if (saw_anode == 8'hFF) begin
            $display("PASS: All 8 anodes cycled LOW");
            pass = pass + 1;
        end else begin
            $display("FAIL: Only saw anodes 0b%08b (expected 0b11111111)", saw_anode);
            fail = fail + 1;
        end

        // -----------------------------------------------------------------
        // TEST 2: Exactly one anode LOW at any clock (no ghosting)
        // -----------------------------------------------------------------
        $display("=== TEST 2: Exactly one anode active at all times ===");
        begin : check_one_hot
            integer active_count;
            integer err_count;
            err_count = 0;
            repeat (8 * REFRESH) begin
                @(posedge clk); #1;
                active_count = 0;
                for (i = 0; i < 8; i = i + 1)
                    if (!an[i]) active_count = active_count + 1;
                if (active_count != 1) err_count = err_count + 1;
            end
            if (err_count == 0) begin
                $display("PASS: Always exactly one anode LOW over full frame");
                pass = pass + 1;
            end else begin
                $display("FAIL: %0d cycles with wrong anode count", err_count);
                fail = fail + 1;
            end
        end

        // -----------------------------------------------------------------
        // TEST 3: Score digit encoding (0–9)
        // -----------------------------------------------------------------
        $display("=== TEST 3: Score digit encoding 0-9 ===");
        for (d = 0; d <= 9; d = d + 1) begin
            seg_data0 = d[3:0];          // digit 0 = d
            wait_for_digit(0);
            @(posedge clk); #1;
            check_seg(d[3:0], seg);
            wait_cycles(REFRESH - 1);
        end

        // -----------------------------------------------------------------
        // TEST 4: Game character encoding (A=BLANK, B=DINO-gnd, C=DINO-air,
        //         D=CACTUS, E=BLANK-spare, F=BLANK-spare)
        // -----------------------------------------------------------------
        $display("=== TEST 4: Game character encoding 0xA-0xF ===");
        for (d = 10; d <= 15; d = d + 1) begin
            seg_data0 = d[3:0];
            wait_for_digit(0);
            @(posedge clk); #1;
            check_seg(d[3:0], seg);
            wait_cycles(REFRESH - 1);
        end

        // -----------------------------------------------------------------
        // TEST 5: Game layout — DINO ground at digit7, CACTUS at digit0
        //   seg_data1[15:12]=0xB (DINO-gnd)  → digit7
        //   seg_data0[3:0]  =0xD (CACTUS)    → digit0
        //   all others = 0xA (BLANK)
        // -----------------------------------------------------------------
        $display("=== TEST 5: Game layout — DINO(B) at dig7, CACTUS(D) at dig0 ===");
        seg_data0 = 32'hAAAA_AAAD;   // dig0=D, rest=A
        seg_data1 = 32'hBAAA_AAAA;   // dig7=B, rest=A
        // Check digit 0 = CACTUS
        wait_for_digit(0);
        @(posedge clk); #1;
        check_seg(4'hD, seg);
        wait_cycles(REFRESH - 1);
        // Check digit 7 = DINO ground
        wait_for_digit(7);
        @(posedge clk); #1;
        check_seg(4'hB, seg);
        wait_cycles(REFRESH - 1);

        // -----------------------------------------------------------------
        // TEST 6: Jump state — DINO air at digit7, CACTUS at digit1
        // -----------------------------------------------------------------
        $display("=== TEST 6: Jump state — DINO-AIR(C) at dig7, CACTUS(D) at dig1 ===");
        seg_data0 = 32'hAAAA_ADAA;   // dig1=D, rest=A
        seg_data1 = 32'hCAAA_AAAA;   // dig7=C, rest=A
        wait_for_digit(1);
        @(posedge clk); #1;
        check_seg(4'hD, seg);
        wait_cycles(REFRESH - 1);
        wait_for_digit(7);
        @(posedge clk); #1;
        check_seg(4'hC, seg);
        wait_cycles(REFRESH - 1);

        // -----------------------------------------------------------------
        // TEST 7: Nibble extraction correctness across both words
        //   seg_data0 = 0xDCBA_9876  dig3=D dig2=C dig1=B dig0=A
        //   seg_data1 = 0x3210_FEDC  dig7=3 dig6=2 dig5=1 dig4=0 (via low nibbles)
        //                            dig7=3 dig6=2 dig5=1 dig4=0
        // -----------------------------------------------------------------
        $display("=== TEST 7: Nibble extraction — mixed score + game chars ===");
        seg_data0 = 32'hDCBA_9876;   // dig3=D(CACTUS) dig2=C(DINO-air) dig1=B(DINO-gnd) dig0=A(BLANK)
        // Verify dig0=A (BLANK)
        wait_for_digit(0);
        @(posedge clk); #1;
        check_seg(4'hA, seg);
        wait_cycles(REFRESH - 1);
        // Verify dig1=B (DINO ground)
        wait_for_digit(1);
        @(posedge clk); #1;
        check_seg(4'hB, seg);
        wait_cycles(REFRESH - 1);
        // Verify dig2=C (DINO air)
        wait_for_digit(2);
        @(posedge clk); #1;
        check_seg(4'hC, seg);
        wait_cycles(REFRESH - 1);
        // Verify dig3=D (CACTUS)
        wait_for_digit(3);
        @(posedge clk); #1;
        check_seg(4'hD, seg);
        wait_cycles(REFRESH - 1);

        // -----------------------------------------------------------------
        // TEST 8: Decimal point always HIGH (off)
        // -----------------------------------------------------------------
        $display("=== TEST 8: Decimal point always HIGH (off) ===");
        seg_data0 = 32'hDDDD_DDDD;   // all CACTUS (busiest pattern)
        seg_data1 = 32'hBBBB_BBBB;   // all DINO ground
        begin : check_dp
            integer dp_low_count;
            dp_low_count = 0;
            repeat (8 * REFRESH) begin
                @(posedge clk); #1;
                if (!dp) dp_low_count = dp_low_count + 1;
            end
            if (dp_low_count == 0) begin
                $display("PASS: dp always HIGH (decimal point off)");
                pass = pass + 1;
            end else begin
                $display("FAIL: dp went LOW %0d times", dp_low_count);
                fail = fail + 1;
            end
        end

        // -----------------------------------------------------------------
        // TEST 9: Dynamic update — change seg_data mid-run, display follows
        // -----------------------------------------------------------------
        $display("=== TEST 9: Dynamic update follows seg_data changes ===");
        seg_data0 = 32'hAAAA_AAAA;   // all BLANK
        wait_for_digit(0);
        @(posedge clk); #1;
        check_seg(4'hA, seg);         // should still be BLANK
        // Now change to CACTUS mid-run
        seg_data0 = 32'hAAAA_AAAD;
        wait_for_digit(0);            // wait for next digit-0 window
        @(posedge clk); #1;
        check_seg(4'hD, seg);         // should now show CACTUS
        wait_cycles(REFRESH - 1);

        // -----------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------
        $display("====================================");
        $display("RESULTS: %0d PASSED, %0d FAILED", pass, fail);
        $display("====================================");
        $finish;
    end

endmodule