`timescale 1ns / 1ps
// =============================================================================
// top_fpga.v — Project T-Rex — Board Top Module for Nexys A7-100T
// =============================================================================
// Wires together:
//   1. pipe           — 3-stage RV32IM pipeline (slow_clk)
//   2. instr_mem      — instruction BRAM (slow_clk)
//   3. data_mem       — data BRAM (slow_clk), gated by mmio_decoder
//   4. mmio_decoder   — MMIO address router (slow_clk)
//   5. seg7_mux       — 8-digit 7-seg TDM driver (FAST clk, 100 MHz)
//   6. lfsr16         — 16-bit LFSR for cactus RNG (FAST clk, 100 MHz)
//   7. debouncer (x2) — sticky button debouncers (FAST clk, 100 MHz)
//   8. led_ctrl       — LED register (slow_clk)
//
// Clock domains:
//   clk      — 100 MHz board oscillator (seg7_mux, lfsr16, debouncer)
//   slow_clk — ~1 MHz divided clock (pipe, IMEM, DMEM, mmio_decoder, led_ctrl)
//
// Reset polarity:
//   Board BTNC is active-HIGH on press.
//   Pipeline and all peripherals use active-LOW reset.
//   Inversion: reset_n = ~reset
// =============================================================================

module top_fpga #(
    parameter IMEMSIZE = 4096,
    parameter DMEMSIZE = 4096,
    parameter IMEM_INIT_FILE = "imem.hex",
    parameter DMEM_INIT_FILE = "dmem.hex"
)(
    input  wire        clk,             // 100 MHz board oscillator
    input  wire        reset,           // BTNC — active-HIGH on board

    // Game buttons
    input  wire        sw_jump,         // BTNU — single jump
    input  wire        sw_double_jump,  // BTNL — double jump

    // 7-segment display
    output wire [6:0]  seg,             // cathodes (active-LOW)
    output wire [7:0]  an,              // anodes   (active-LOW)
    output wire        dp,              // decimal point

    // LEDs
    output wire [15:0] led              // active-HIGH
    // LEDs
    output wire [15:0] led,              // active-HIGH

    // Audio Output
    output wire        audio_out,        // AUD_PWM
    output wire        audio_en          // AUD_SD (amplifier enable)
);

    // =========================================================================
    // Reset polarity inversion
    // Board button is active-HIGH; pipeline and peripherals need active-LOW
    // =========================================================================
    wire reset_n = ~reset;

    // =========================================================================
    // Clock divider: 100 MHz -> ~1 MHz for practical on-board testing.
    // =========================================================================
    reg [25:0] clk_cnt;
    reg        slow_clk;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            clk_cnt  <= 26'd0;
            slow_clk <= 1'b0;
        end else begin
            if (clk_cnt == 26'd49) begin
                clk_cnt  <= 26'd0;
                slow_clk <= ~slow_clk;
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end
    end

    // =========================================================================
    // PIPE ↔ MEMORY WIRES
    // =========================================================================
    wire [31:0] inst_mem_read_data;
    wire        inst_mem_is_valid = 1'b1;

    wire [31:0] bram_rdata;              // raw BRAM read data
    wire [31:0] dmem_rdata_to_pipe;      // muxed: BRAM or MMIO
    wire        dmem_write_valid = 1'b1;
    wire        dmem_read_valid  = 1'b1;

    wire        exception;
    wire [31:0] pc_out;
    wire [15:0] led_reg5;

    wire        dmem_re, dmem_we;
    wire [31:0] dmem_raddr, dmem_waddr, dmem_wdata;
    wire [3:0]  dmem_wstrb;

    // =========================================================================
    // MMIO DECODER WIRES
    // =========================================================================
    wire        dmem_re_bram, dmem_we_bram;
    wire [31:0] mmio_rdata;
    wire        mmio_sel;
    wire        jump_clear, dbl_jump_clear;
    wire [15:0] led_wdata;
    wire        led_we;
    wire [31:0] seg_data0, seg_data1;
    wire [15:0] lfsr_out;
    wire        jump_sticky, dbl_jump_sticky;
    wire        jump_stable, dbl_jump_stable;   // from debouncers (unused here)
   wire [1:0]  audio_ev;
    // =========================================================================
    // MMIO READ ALIGNMENT
    // BRAM reads are synchronous (1-cycle latency). MMIO reads are combinational
    // from mmio_decoder, so register MMIO select/data by one slow_clk cycle to
    // match BRAM timing and keep load data aligned in WB.
    // =========================================================================
    reg        mmio_sel_q;
    reg [31:0] mmio_rdata_q;

    always @(posedge slow_clk or negedge reset_n) begin
        if (!reset_n) begin
            mmio_sel_q   <= 1'b0;
            mmio_rdata_q <= 32'h0000_0000;
        end else begin
            mmio_sel_q   <= mmio_sel;
            mmio_rdata_q <= mmio_rdata;
        end
    end

    assign dmem_rdata_to_pipe = mmio_sel_q ? mmio_rdata_q : bram_rdata;

    // =========================================================================
    // PIPELINE CPU (clocked on slow_clk for game-speed execution)
    // =========================================================================
    pipe pipe_u (
        .clk                (slow_clk),
        .reset              (reset_n),
        .stall              (1'b0),
        .exception          (exception),
        .pc_out             (pc_out),
        .inst_mem_is_valid  (inst_mem_is_valid),
        .inst_mem_read_data (inst_mem_read_data),
        .dmem_read_data_temp(dmem_rdata_to_pipe),
        .dmem_re            (dmem_re),
        .dmem_raddr         (dmem_raddr),
        .dmem_we            (dmem_we),
        .dmem_waddr         (dmem_waddr),
        .dmem_wdata         (dmem_wdata),
        .dmem_wstrb         (dmem_wstrb),
        .dmem_write_valid   (dmem_write_valid),
        .dmem_read_valid    (dmem_read_valid),
        .led_reg5           (led_reg5)
    );

    // =========================================================================
    // INSTRUCTION MEMORY (clocked on slow_clk)
    // =========================================================================
    instr_mem #(
        .INIT_FILE(IMEM_INIT_FILE)
    ) IMEM (
        .clk   (slow_clk),
        .pc    (pc_out),
        .instr (inst_mem_read_data)
    );

    // =========================================================================
    // DATA MEMORY — BRAM (clocked on slow_clk)
    // Read/write gated by mmio_decoder so MMIO addresses don't hit BRAM
    // =========================================================================
    data_mem #(
        .INIT_FILE(DMEM_INIT_FILE)
    ) DMEM (
        .clk   (slow_clk),
        .re    (dmem_re_bram),
        .raddr (dmem_raddr),
        .rdata (bram_rdata),
        .we    (dmem_we_bram),
        .waddr (dmem_waddr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

    // =========================================================================
    // MMIO DECODER (clocked on slow_clk — same domain as pipeline)
    // Routes addresses >= 0x2000 to peripherals instead of BRAM
    // =========================================================================
    mmio_decoder u_mmio (
        .clk              (slow_clk),
        .reset            (reset_n),
        .dmem_re          (dmem_re),
        .dmem_raddr       (dmem_raddr),
        .dmem_we          (dmem_we),
        .dmem_waddr       (dmem_waddr),
        .dmem_wdata       (dmem_wdata),
        .dmem_wstrb       (dmem_wstrb),
        .dmem_write_valid (dmem_write_valid),
        .dmem_re_bram     (dmem_re_bram),
        .dmem_we_bram     (dmem_we_bram),
        .mmio_rdata_o     (mmio_rdata),
        .mmio_sel         (mmio_sel),
        .jump_clear       (jump_clear),
        .dbl_jump_clear   (dbl_jump_clear),
        .led_wdata        (led_wdata),
        .led_we           (led_we),
        .seg_data0        (seg_data0),
        .seg_data1        (seg_data1),
        .audio_ev         (audio_ev),
        .lfsr_out         (lfsr_out),
        .jump_sticky      (jump_sticky),
        .dbl_jump_sticky  (dbl_jump_sticky)
    );

    // =========================================================================
    // 7-SEGMENT DISPLAY MUX (clocked on FAST 100 MHz for flicker-free TDM)
    // =========================================================================
    seg7_mux u_seg7 (
        .clk       (clk),              // FAST clock
        .reset     (reset_n),
        .seg_data0 (seg_data0),
        .seg_data1 (seg_data1),
        .seg       (seg),
        .an        (an),
        .dp        (dp)
    );

    // =========================================================================
    // LFSR — free-running RNG on fast clock (read by CPU via MMIO_LFSR_R)
    // =========================================================================
    lfsr16 u_lfsr (
        .clk      (clk),               // FAST clock
        .reset    (reset_n),
        .lfsr_out (lfsr_out)
    );

    // =========================================================================
    // DEBOUNCER — single jump button (BTNU)
    // Runs on fast clock for proper 10 ms debounce timing
    // =========================================================================
    debouncer u_debounce_jump (
        .clk        (clk),             // FAST clock
        .reset      (reset_n),
        .btn_raw    (sw_jump),
        .clear      (jump_clear),
        .btn_stable (jump_stable),
        .btn_sticky (jump_sticky)
    );

    // =========================================================================
    // DEBOUNCER — double jump button (BTNL)
    // =========================================================================
    debouncer u_debounce_dbl (
        .clk        (clk),             // FAST clock
        .reset      (reset_n),
        .btn_raw    (sw_double_jump),
        .clear      (dbl_jump_clear),
        .btn_stable (dbl_jump_stable),
        .btn_sticky (dbl_jump_sticky)
    );

    // =========================================================================
    // LED CONTROLLER (clocked on slow_clk — same domain as MMIO writes)
    // =========================================================================
    led_ctrl u_led (
        .clk    (slow_clk),
        .reset  (reset_n),
        .we     (led_we),
        .wdata  (led_wdata),
        .led_out(led)
    );

endmodule
