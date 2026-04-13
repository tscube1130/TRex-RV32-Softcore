// =============================================================================
// tb_mmio_decoder.v — Testbench for mmio_decoder.v
// =============================================================================
// Tests (original 13 preserved, 4 new added):
//   1.  BRAM write (0x0100)   → dmem_we_bram HIGH, no MMIO effects
//   2.  LED write 0x200C       → led_we HIGH, bram LOW
//   3.  SEG_W0 write 0x2010   → seg_data0 registered
//   4.  SEG_W1 write 0x2014   → seg_data1 registered
//   5.  SW_CLR=1               → only jump_clear fires
//   6.  SW_CLR=2               → only dbl_jump_clear fires
//   7.  SW_CLR=3               → both clears fire
//   8.  BRAM read (0x0200)     → mmio_sel LOW
//   9.  SW_R jump=1 dbl=0      → rdata=0x00000001
//   10. SW_R jump=0 dbl=1      → rdata=0x00000002
//   11. SW_R both=1            → rdata=0x00000003
//   12. LFSR read 0x2008       → rdata={16'b0, lfsr_out}
//   13. LFSR cactus type bit[0]
//   14. wstrb=0 write → NO mmio effect (BRAM write also blocked)
//   15. write_valid=0 → seg_data NOT latched
//   16. Reset initialises seg to 0xAAAA_AAAA (all BLANK)
//   17. MMIO write with wstrb=0xF to BRAM addr → bram gets it, mmio ignores
// =============================================================================
`timescale 1ns/1ps

module tb_mmio_decoder;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg  clk, reset;

    reg        dmem_re;
    reg [31:0] dmem_raddr;
    reg        dmem_we;
    reg [31:0] dmem_waddr;
    reg [31:0] dmem_wdata;
    reg [3:0]  dmem_wstrb;        // NEW — byte-lane enables
    reg        dmem_write_valid;  // NEW — pipeline write handshake

    wire        dmem_re_bram;
    wire        dmem_we_bram;
    wire [31:0] mmio_rdata_o;
    wire        mmio_sel;
    wire        jump_clear;
    wire        dbl_jump_clear;
    wire [15:0] led_wdata;
    wire        led_we;
    wire [31:0] seg_data0;
    wire [31:0] seg_data1;

    reg [15:0] lfsr_out;
    reg        jump_sticky;
    reg        dbl_jump_sticky;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    mmio_decoder dut (
        .clk            (clk),
        .reset          (reset),
        .dmem_re        (dmem_re),
        .dmem_raddr     (dmem_raddr),
        .dmem_we        (dmem_we),
        .dmem_waddr     (dmem_waddr),
        .dmem_wdata     (dmem_wdata),
        .dmem_wstrb     (dmem_wstrb),
        .dmem_write_valid(dmem_write_valid),
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
    // Clock
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Helpers
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

    // Standard word-write helper (wstrb=0xF, write_valid=1)
    task bus_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            dmem_we          = 1;
            dmem_waddr       = addr;
            dmem_wdata       = data;
            dmem_wstrb       = 4'hF;
            dmem_write_valid = 1;
        end
    endtask

    task bus_read;
        input [31:0] addr;
        begin
            dmem_re    = 1;
            dmem_raddr = addr;
        end
    endtask

    task bus_idle;
        begin
            dmem_re    = 0; dmem_we    = 0;
            dmem_raddr = 0; dmem_waddr = 0;
            dmem_wdata = 0; dmem_wstrb = 4'h0;
            dmem_write_valid = 0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_mmio_decoder.vcd");
        $dumpvars(0, tb_mmio_decoder);

        pass = 0; fail = 0;

        lfsr_out        = 16'hBEEF;
        jump_sticky     = 1'b0;
        dbl_jump_sticky = 1'b0;
        bus_idle();

        reset = 0; repeat(3) @(negedge clk);
        reset = 1; @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 1: BRAM write — only BRAM side-effects
        // ------------------------------------------------------------------
        $display("=== TEST 1: BRAM write 0x0100 ===");
        bus_write(32'h0000_0100, 32'hDEAD_BEEF); #1;
        check_bit("T1_we_bram_HIGH",   dmem_we_bram,   1'b1);
        check_bit("T1_led_we_LOW",     led_we,          1'b0);
        check_bit("T1_jump_clr_LOW",   jump_clear,      1'b0);
        check_bit("T1_dbl_clr_LOW",    dbl_jump_clear,  1'b0);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 2: LED write 0x200C
        // ------------------------------------------------------------------
        $display("=== TEST 2: LED write 0x200C ===");
        bus_write(32'h0000_200C, 32'h0000_F0F0); #1;
        check_bit("T2_led_we_HIGH",    led_we,          1'b1);
        check_bit("T2_we_bram_LOW",    dmem_we_bram,    1'b0);
        check_32 ("T2_led_wdata",      {16'b0,led_wdata}, 32'h0000_F0F0);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 3: SEG_W0 write 0x2010 — latched on posedge
        // ------------------------------------------------------------------
        $display("=== TEST 3: SEG_W0 write 0x2010 ===");
        bus_write(32'h0000_2010, 32'h1234_5678); #1;
        check_bit("T3_we_bram_LOW",    dmem_we_bram,    1'b0);
        @(posedge clk); #1;
        check_32 ("T3_seg_data0",      seg_data0, 32'h1234_5678);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 4: SEG_W1 write 0x2014
        // ------------------------------------------------------------------
        $display("=== TEST 4: SEG_W1 write 0x2014 ===");
        bus_write(32'h0000_2014, 32'hABCD_EF01); #1;
        @(posedge clk); #1;
        check_32 ("T4_seg_data1",      seg_data1, 32'hABCD_EF01);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 5: SW_CLR=1 → only jump_clear fires
        // ------------------------------------------------------------------
        $display("=== TEST 5: SW_CLR=0x1 → jump_clear only ===");
        bus_write(32'h0000_2004, 32'h0000_0001); #1;
        check_bit("T5_jump_clr_HIGH",  jump_clear,      1'b1);
        check_bit("T5_dbl_clr_LOW",    dbl_jump_clear,  1'b0);
        check_bit("T5_we_bram_LOW",    dmem_we_bram,    1'b0);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 6: SW_CLR=2 → only dbl_jump_clear fires
        // ------------------------------------------------------------------
        $display("=== TEST 6: SW_CLR=0x2 → dbl_jump_clear only ===");
        bus_write(32'h0000_2004, 32'h0000_0002); #1;
        check_bit("T6_jump_clr_LOW",   jump_clear,      1'b0);
        check_bit("T6_dbl_clr_HIGH",   dbl_jump_clear,  1'b1);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 7: SW_CLR=3 → both clears fire
        // ------------------------------------------------------------------
        $display("=== TEST 7: SW_CLR=0x3 → BOTH clears ===");
        bus_write(32'h0000_2004, 32'h0000_0003); #1;
        check_bit("T7_jump_clr_HIGH",  jump_clear,      1'b1);
        check_bit("T7_dbl_clr_HIGH",   dbl_jump_clear,  1'b1);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 8: BRAM read → mmio_sel LOW
        // ------------------------------------------------------------------
        $display("=== TEST 8: BRAM read 0x0200 ===");
        bus_read(32'h0000_0200); #1;
        check_bit("T8_mmio_sel_LOW",   mmio_sel,        1'b0);
        check_bit("T8_re_bram_HIGH",   dmem_re_bram,    1'b1);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 9: SW_R — jump only
        // ------------------------------------------------------------------
        $display("=== TEST 9: SW_R jump_sticky=1 dbl=0 ===");
        jump_sticky = 1; dbl_jump_sticky = 0;
        bus_read(32'h0000_2000); #1;
        check_bit("T9_mmio_sel_HIGH",  mmio_sel,        1'b1);
        check_32 ("T9_rdata",          mmio_rdata_o, 32'h0000_0001);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 10: SW_R — double jump only
        // ------------------------------------------------------------------
        $display("=== TEST 10: SW_R jump=0 dbl_jump=1 ===");
        jump_sticky = 0; dbl_jump_sticky = 1;
        bus_read(32'h0000_2000); #1;
        check_32 ("T10_rdata",         mmio_rdata_o, 32'h0000_0002);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 11: SW_R — both
        // ------------------------------------------------------------------
        $display("=== TEST 11: SW_R both=1 ===");
        jump_sticky = 1; dbl_jump_sticky = 1;
        bus_read(32'h0000_2000); #1;
        check_32 ("T11_rdata_both",    mmio_rdata_o, 32'h0000_0003);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 12: LFSR read
        // ------------------------------------------------------------------
        $display("=== TEST 12: LFSR read 0x2008 ===");
        lfsr_out = 16'hBEEF;
        bus_read(32'h0000_2008); #1;
        check_bit("T12_mmio_sel_HIGH", mmio_sel,        1'b1);
        check_32 ("T12_rdata",         mmio_rdata_o, 32'h0000_BEEF);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 13: LFSR bit[0] cactus type
        // ------------------------------------------------------------------
        $display("=== TEST 13: LFSR bit[0] cactus type ===");
        lfsr_out = 16'h1234;  // bit[0]=0 → single cactus
        bus_read(32'h0000_2008); #1;
        check_bit("T13_single_cactus", mmio_rdata_o[0], 1'b0);
        bus_idle(); @(posedge clk); #1;
        lfsr_out = 16'h1235;  // bit[0]=1 → pair
        bus_read(32'h0000_2008); #1;
        check_bit("T13_pair_cactus",   mmio_rdata_o[0], 1'b1);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 14: wstrb=0 write to MMIO → NO effect (LED/seg must not fire)
        // ------------------------------------------------------------------
        $display("=== TEST 14: wstrb=0 write → MMIO ignores, BRAM also blocked ===");
        dmem_we = 1; dmem_waddr = 32'h0000_200C; dmem_wdata = 32'h0000_FFFF;
        dmem_wstrb = 4'h0; dmem_write_valid = 1; #1;
        check_bit("T14_led_we_LOW",    led_we,          1'b0);
        check_bit("T14_we_bram_LOW",   dmem_we_bram,    1'b0);
        bus_idle(); @(posedge clk); #1;

        // TEST 14b: wstrb=0 write to BRAM addr → BRAM also blocked
        dmem_we = 1; dmem_waddr = 32'h0000_0100; dmem_wdata = 32'hDEAD;
        dmem_wstrb = 4'h0; dmem_write_valid = 1; #1;
        check_bit("T14b_we_bram_wstrb0_LOW", dmem_we_bram, 1'b0);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 15: dmem_write_valid=0 → seg_data NOT latched
        // ------------------------------------------------------------------
        $display("=== TEST 15: write_valid=0 → seg NOT latched ===");
        // seg_data0 is currently 0x12345678 from TEST 3
        dmem_we = 1; dmem_waddr = 32'h0000_2010; dmem_wdata = 32'hDEAD_BEEF;
        dmem_wstrb = 4'hF; dmem_write_valid = 0; #1;
        @(posedge clk); #1;
        check_32("T15_seg_data0_unchanged", seg_data0, 32'h1234_5678);
        bus_idle(); @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 16: Reset initialises seg_data to 0xAAAA_AAAA (all BLANK)
        // ------------------------------------------------------------------
        $display("=== TEST 16: Reset → seg_data = 0xAAAA_AAAA (all BLANK) ===");
        reset = 0; @(negedge clk); #1;
        reset = 1; @(posedge clk); #1;
        check_32("T16_seg_data0_blank", seg_data0, 32'hAAAA_AAAA);
        check_32("T16_seg_data1_blank", seg_data1, 32'hAAAA_AAAA);

        // ------------------------------------------------------------------
        // TEST 17: Normal BRAM write (wstrb=0xF) reaches bram, not MMIO
        // ------------------------------------------------------------------
        $display("=== TEST 17: BRAM write wstrb=0xF reaches bram only ===");
        bus_write(32'h0000_0200, 32'hCAFE_BABE); #1;
        check_bit("T17_we_bram_HIGH",  dmem_we_bram,    1'b1);
        check_bit("T17_mmio_sel_LOW",  mmio_sel,        1'b0);
        check_bit("T17_led_we_LOW",    led_we,           1'b0);
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