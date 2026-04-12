// =============================================================================
// tb_mmio_decoder.v — Testbench for mmio_decoder.v (updated for dual-switch game)
// =============================================================================
// Game context:
//   Switch 1 (sw_jump)        → single jump (Dino clears normal cactus)
//   Switch 2 (sw_double_jump) → double jump (Dino clears pair of cactus)
//   LFSR bit[0]               → 0=single cactus, 1=pair cactus (C code decides)
//
// Tests:
//   1.  Write to BRAM addr     → dmem_we_bram HIGH, no MMIO side-effects
//   2.  Write MMIO_LED_W       → led_we HIGH, dmem_we_bram LOW
//   3.  Write MMIO_SEG_W0      → seg_data0 registered, BRAM off
//   4.  Write MMIO_SEG_W1      → seg_data1 registered, BRAM off
//   5.  Write MMIO_SW_CLR=1    → only jump_clear fires (dbl_jump_clear stays LOW)
//   6.  Write MMIO_SW_CLR=2    → only dbl_jump_clear fires
//   7.  Write MMIO_SW_CLR=3    → both clears fire simultaneously
//   8.  Read BRAM addr         → mmio_sel LOW, re_bram HIGH
//   9.  Read MMIO_SW_R (jump=1, dbl=0) → rdata = 32'h0000_0001
//   10. Read MMIO_SW_R (jump=0, dbl=1) → rdata = 32'h0000_0002
//   11. Read MMIO_SW_R (both=1)        → rdata = 32'h0000_0003
//   12. Read MMIO_LFSR_R               → rdata = {16'b0, lfsr_out}
//   13. LFSR cactus type: bit[0]=0 → single, bit[0]=1 → pair
// =============================================================================
`timescale 1ns/1ps

module tb_mmio_decoder;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg  clk, reset;

    // Pipeline → decoder
    reg        dmem_re;
    reg [31:0] dmem_raddr;
    reg        dmem_we;
    reg [31:0] dmem_waddr;
    reg [31:0] dmem_wdata;

    // Decoder → BRAM
    wire        dmem_re_bram;
    wire        dmem_we_bram;

    // Decoder → pipeline (read data mux)
    wire [31:0] mmio_rdata_o;
    wire        mmio_sel;

    // Decoder → debouncer 1 (single jump, Switch 1)
    wire        jump_clear;
    // Decoder → debouncer 2 (double jump, Switch 2)
    wire        dbl_jump_clear;

    // Decoder → LED controller
    wire [15:0] led_wdata;
    wire        led_we;

    // Decoder → 7-seg mux
    wire [31:0] seg_data0;
    wire [31:0] seg_data1;

    // Peripherals → decoder (inputs to read mux)
    reg [15:0] lfsr_out;
    reg        jump_sticky;
    reg        dbl_jump_sticky;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    mmio_decoder dut (
        .clk            (clk),
        .reset          (reset),
        .dmem_re        (dmem_re),
        .dmem_raddr     (dmem_raddr),
        .dmem_we        (dmem_we),
        .dmem_waddr     (dmem_waddr),
        .dmem_wdata     (dmem_wdata),
        .dmem_re_bram   (dmem_re_bram),
        .dmem_we_bram   (dmem_we_bram),
        .mmio_rdata_o   (mmio_rdata_o),
        .mmio_sel       (mmio_sel),
        .jump_clear     (jump_clear),
        .dbl_jump_clear (dbl_jump_clear),
        .led_wdata      (led_wdata),
        .led_we         (led_we),
        .seg_data0      (seg_data0),
        .seg_data1      (seg_data1),
        .lfsr_out       (lfsr_out),
        .jump_sticky    (jump_sticky),
        .dbl_jump_sticky(dbl_jump_sticky)
    );

    // -------------------------------------------------------------------------
    // Clock: 10 ns period (100 MHz sim)
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Test helpers
    // -------------------------------------------------------------------------
    integer pass, fail;

    task check_bit;
        input [127:0] name;
        input         got;
        input         expected;
        begin
            if (got === expected) begin
                $display("  PASS [%0s] = %b", name, got);
                pass = pass + 1;
            end else begin
                $display("  FAIL [%0s] expected=%b got=%b", name, expected, got);
                fail = fail + 1;
            end
        end
    endtask

    task check_32;
        input [127:0] name;
        input [31:0] got;
        input [31:0] expected;
        begin
            if (got === expected) begin
                $display("  PASS [%0s] = 0x%08X", name, got);
                pass = pass + 1;
            end else begin
                $display("  FAIL [%0s] expected=0x%08X got=0x%08X", name, expected, got);
                fail = fail + 1;
            end
        end
    endtask

    task bus_idle;
        begin
            dmem_re    = 0; dmem_we    = 0;
            dmem_raddr = 0; dmem_waddr = 0; dmem_wdata = 0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_mmio_decoder.vcd");
        $dumpvars(0, tb_mmio_decoder);

        pass = 0; fail = 0;

        // Initial peripheral values
        lfsr_out        = 16'hBEEF;
        jump_sticky     = 1'b0;
        dbl_jump_sticky = 1'b0;
        bus_idle();

        // Reset
        reset = 0; repeat(3) @(negedge clk);
        reset = 1; @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 1: BRAM write (0x0100) — only BRAM gets it
        // ------------------------------------------------------------------
        $display("=== TEST 1: BRAM write 0x0100 ===");
        dmem_we = 1; dmem_waddr = 32'h0000_0100; dmem_wdata = 32'hDEAD_BEEF; #1;
        check_bit("T1_we_bram_HIGH",      dmem_we_bram,   1'b1);
        check_bit("T1_led_we_LOW",        led_we,          1'b0);
        check_bit("T1_jump_clear_LOW",    jump_clear,      1'b0);
        check_bit("T1_dbl_clear_LOW",     dbl_jump_clear,  1'b0);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 2: LED write (0x200C)
        // ------------------------------------------------------------------
        $display("=== TEST 2: LED write 0x200C ===");
        dmem_we = 1; dmem_waddr = 32'h0000_200C; dmem_wdata = 32'h0000_F0F0; #1;
        check_bit("T2_led_we_HIGH",       led_we,          1'b1);
        check_bit("T2_we_bram_LOW",       dmem_we_bram,    1'b0);
        check_32 ("T2_led_wdata",         {16'b0,led_wdata}, 32'h0000_F0F0);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 3: SEG_W0 write (0x2010)
        // ------------------------------------------------------------------
        $display("=== TEST 3: SEG_W0 write 0x2010 ===");
        dmem_we = 1; dmem_waddr = 32'h0000_2010; dmem_wdata = 32'h1234_5678; #1;
        check_bit("T3_we_bram_LOW",       dmem_we_bram,    1'b0);
        @(posedge clk); #1;
        check_32 ("T3_seg_data0",         seg_data0, 32'h1234_5678);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 4: SEG_W1 write (0x2014)
        // ------------------------------------------------------------------
        $display("=== TEST 4: SEG_W1 write 0x2014 ===");
        dmem_we = 1; dmem_waddr = 32'h0000_2014; dmem_wdata = 32'hABCD_EF01; #1;
        check_bit("T4_we_bram_LOW",       dmem_we_bram,    1'b0);
        @(posedge clk); #1;
        check_32 ("T4_seg_data1",         seg_data1, 32'hABCD_EF01);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 5: Clear ONLY jump sticky (write 0x2004 with data=32'h1)
        // ------------------------------------------------------------------
        $display("=== TEST 5: MMIO_SW_CLR write=32'h1 → only jump_clear fires ===");
        dmem_we = 1; dmem_waddr = 32'h0000_2004; dmem_wdata = 32'h0000_0001; #1;
        check_bit("T5_jump_clear_HIGH",   jump_clear,      1'b1);  // bit[0]
        check_bit("T5_dbl_clear_LOW",     dbl_jump_clear,  1'b0);  // bit[1] NOT set
        check_bit("T5_we_bram_LOW",       dmem_we_bram,    1'b0);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 6: Clear ONLY dbl_jump sticky (write data=32'h2)
        // ------------------------------------------------------------------
        $display("=== TEST 6: MMIO_SW_CLR write=32'h2 → only dbl_jump_clear fires ===");
        dmem_we = 1; dmem_waddr = 32'h0000_2004; dmem_wdata = 32'h0000_0002; #1;
        check_bit("T6_jump_clear_LOW",    jump_clear,      1'b0);  // bit[0] NOT set
        check_bit("T6_dbl_clear_HIGH",    dbl_jump_clear,  1'b1);  // bit[1]
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 7: Clear BOTH at once (write data=32'h3)
        // ------------------------------------------------------------------
        $display("=== TEST 7: MMIO_SW_CLR write=32'h3 → BOTH clears fire ===");
        dmem_we = 1; dmem_waddr = 32'h0000_2004; dmem_wdata = 32'h0000_0003; #1;
        check_bit("T7_jump_clear_HIGH",   jump_clear,      1'b1);
        check_bit("T7_dbl_clear_HIGH",    dbl_jump_clear,  1'b1);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 8: BRAM read (0x0200) — mmio_sel LOW
        // ------------------------------------------------------------------
        $display("=== TEST 8: BRAM read 0x0200 ===");
        dmem_re = 1; dmem_raddr = 32'h0000_0200; #1;
        check_bit("T8_mmio_sel_LOW",      mmio_sel,        1'b0);
        check_bit("T8_re_bram_HIGH",      dmem_re_bram,    1'b1);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 9: Switch read — only jump pressed (bit[0]=1, bit[1]=0)
        // ------------------------------------------------------------------
        $display("=== TEST 9: Read 0x2000 — only jump_sticky=1 ===");
        jump_sticky = 1'b1; dbl_jump_sticky = 1'b0;
        dmem_re = 1; dmem_raddr = 32'h0000_2000; #1;
        check_bit("T9_mmio_sel_HIGH",     mmio_sel,        1'b1);
        check_bit("T9_re_bram_LOW",       dmem_re_bram,    1'b0);
        check_32 ("T9_rdata",             mmio_rdata_o, 32'h0000_0001);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 10: Switch read — only double jump pressed (bit[0]=0, bit[1]=1)
        // ------------------------------------------------------------------
        $display("=== TEST 10: Read 0x2000 — only dbl_jump_sticky=1 ===");
        jump_sticky = 1'b0; dbl_jump_sticky = 1'b1;
        dmem_re = 1; dmem_raddr = 32'h0000_2000; #1;
        check_32 ("T10_rdata", mmio_rdata_o, 32'h0000_0002);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 11: Both switches active simultaneously (bit[1:0]=11)
        // ------------------------------------------------------------------
        $display("=== TEST 11: Read 0x2000 — both switches active ===");
        jump_sticky = 1'b1; dbl_jump_sticky = 1'b1;
        dmem_re = 1; dmem_raddr = 32'h0000_2000; #1;
        check_32 ("T11_rdata_both", mmio_rdata_o, 32'h0000_0003);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 12: LFSR read (0x2008)
        // ------------------------------------------------------------------
        $display("=== TEST 12: LFSR read 0x2008 ===");
        lfsr_out = 16'hBEEF;
        dmem_re = 1; dmem_raddr = 32'h0000_2008; #1;
        check_bit("T12_mmio_sel_HIGH",    mmio_sel,        1'b1);
        check_bit("T12_re_bram_LOW",      dmem_re_bram,    1'b0);
        check_32 ("T12_rdata",            mmio_rdata_o, 32'h0000_BEEF);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 13: LFSR cactus type — bit[0] selects cactus kind
        // ------------------------------------------------------------------
        $display("=== TEST 13: Cactus type from LFSR bit[0] ===");
        // LFSR even (bit[0]=0) → single cactus
        lfsr_out = 16'h1234;   // bit[0] = 0
        dmem_re = 1; dmem_raddr = 32'h0000_2008; #1;
        check_bit("T13_single_cactus_bit0=0", mmio_rdata_o[0], 1'b0);
        bus_idle(); @(posedge clk); #1;

        // LFSR odd (bit[0]=1) → pair of cactus
        lfsr_out = 16'h1235;   // bit[0] = 1
        dmem_re = 1; dmem_raddr = 32'h0000_2008; #1;
        check_bit("T13_pair_cactus_bit0=1",   mmio_rdata_o[0], 1'b1);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------------
        $display("====================================");
        $display("RESULTS: %0d PASSED, %0d FAILED", pass, fail);
        $display("====================================");
        $finish;
    end

endmodule
