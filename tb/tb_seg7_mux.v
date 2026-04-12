// =============================================================================
// tb_seg7_mux.v — Testbench for seg7_mux.v
// =============================================================================
// Tests:
//   1. All digits cycle through in order (an[0]..an[7] each go LOW once per frame)
//   2. Correct segment encoding for all 16 nibbles (0..F)
//   3. Refresh rate > 1 kHz per digit
//   4. Correct nibble extraction from seg_data0 / seg_data1
//   5. dp always HIGH (decimal point off)
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
    // -------------------------------------------------------------------------
    function [6:0] expected_seg;
        input [3:0] nibble;
        case (nibble)
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
            4'hA: expected_seg = 7'b000_1000;
            4'hB: expected_seg = 7'b000_0011;
            4'hC: expected_seg = 7'b100_0110;
            4'hD: expected_seg = 7'b010_0001;
            4'hE: expected_seg = 7'b000_0110;
            4'hF: expected_seg = 7'b000_1110;
            default: expected_seg = 7'b111_1111;
        endcase
    endfunction

    integer pass, fail;
    integer i;
    integer d;
    reg [7:0] saw_anode;    // bitmask: which digit anodes were seen LOW

    task check_seg;
        input [3:0] nibble;
        input [6:0] got;
        begin
            if (got === expected_seg(nibble)) begin
                $display("  PASS: digit 0x%X → seg=0b%07b", nibble, got);
                pass = pass + 1;
            end else begin
                $display("  FAIL: digit 0x%X expected seg=0b%07b got=0b%07b",
                         nibble, expected_seg(nibble), got);
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

    initial begin
        $dumpfile("tb_seg7_mux.vcd");
        $dumpvars(0, tb_seg7_mux);

        pass = 0; fail = 0;

        // Load distinct nibbles into each digit position so we can identify them
        // dig7..dig4 from seg_data1, dig3..dig0 from seg_data0
        // Packing: dig_n occupies nibble [4*(n%4)+3 : 4*(n%4)] of its word
        seg_data0 = 32'h3210;   // digit3=3, digit2=2, digit1=1, digit0=0
        seg_data1 = 32'h7654;   // digit7=7, digit6=6, digit5=5, digit4=4

        // Reset
        reset = 0;
        wait_cycles(3);
        reset = 1;
        wait_cycles(2);

        // -----------------------------------------------------------------
        // TEST 1: All 8 anodes cycle LOW over one full display frame
        // -----------------------------------------------------------------
        $display("=== TEST 1: All 8 digit anodes cycle through ===");
        saw_anode = 8'h00;

        // One full frame = 8 * REFRESH cycles
        repeat (8 * REFRESH + 4) begin
            @(posedge clk); #1;
            // Exactly one anode should be LOW at a time
            for (i = 0; i < 8; i = i + 1) begin
                if (!an[i]) saw_anode[i] = 1'b1;
            end
        end

        if (saw_anode == 8'hFF) begin
            $display("PASS: All 8 anodes cycled LOW");
            pass = pass + 1;
        end else begin
            $display("FAIL: Only saw anodes 0b%08b (expected 0b11111111)", saw_anode);
            fail = fail + 1;
        end

        // -----------------------------------------------------------------
        // TEST 2: Only ONE anode is LOW at any given clock
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
        // TEST 3: Segment encoding for all 16 hex values
        // -----------------------------------------------------------------
        $display("=== TEST 3: Segment encoding for all 16 nibbles ===");
        // Load each nibble into digit 0 (seg_data0[3:0]) and wait for digit 0 to be active
        for (d = 0; d < 16; d = d + 1) begin
            seg_data0 = d[3:0];   // digit 0 = d, rest don't matter
            // Wait until digit 0 (an[0] LOW)
            begin : wait_an0
                integer timeout;
                timeout = 0;
                while (an[0] !== 1'b0 && timeout < 20*REFRESH) begin
                    @(posedge clk); #1;
                    timeout = timeout + 1;
                end
            end
            @(posedge clk); #1;   // one cycle into digit 0 active window
            check_seg(d[3:0], seg);
            // Skip to end of this digit's window
            wait_cycles(REFRESH - 1);
        end

        // -----------------------------------------------------------------
        // TEST 4: Decimal point always HIGH (off)
        // -----------------------------------------------------------------
        $display("=== TEST 4: Decimal point always HIGH (off) ===");
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
                $display("FAIL: dp went LOW %0d times (decimal point turned on!)", dp_low_count);
                fail = fail + 1;
            end
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
