`timescale 1ns / 1ps
// =============================================================================
// top_fpga.v — FPGA Top-Level Module (Goal System)
// Project T-Rex: Hardware-Accelerated Chrome Dino
// =============================================================================
// Integrates:
//   1. 3-stage RV32IM pipeline (pipe)
//   2. Instruction memory (instr_mem) and Data memory (data_mem)
//   3. MMIO decoder (mmio_decoder) — routes CPU memory ops to peripherals
//   4. Peripherals: lfsr16, debouncer ×2, led_ctrl, seg7_mux
//
// Clock domains:
//   clk       — 100 MHz board clock  (peripherals, seg7, debounce, LFSR)
//   slow_clk  — CPU pipeline clock   (divided from clk via clk_div)
//
// Reset: active-LOW btnCpuReset on Nexys A7
//
// Maintained by: Surbhi Kumari (FPGA & Hardware Integration)
// =============================================================================

module top_fpga #(
    parameter IMEMSIZE  = 4096,
    parameter DMEMSIZE  = 4096,
    // CPU clock divider: 100 MHz / (2 × DIV_COUNT) → CPU clock
    // DIV_COUNT = 50_000_000 → 1 Hz (slow debug); set lower for faster execution
    parameter DIV_COUNT = 26'd50_000_000
)(
    input  wire        clk,             // 100 MHz board clock
    input  wire        reset,           // active-LOW (btnCpuReset)
    input  wire        btn_jump,        // BTNC — single jump
    input  wire        btn_double_jump, // BTNU — double jump

    // 7-segment display (active-LOW)
    output wire [6:0]  seg,
    output wire [7:0]  an,
    output wire        dp,

    // LEDs (active-HIGH)
    output wire [15:0] led
);

    // =========================================================================
    // Clock Divider — 100 MHz → slow_clk for CPU pipeline
    // =========================================================================
    reg [25:0] clk_cnt;
    reg        slow_clk;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            clk_cnt  <= 26'd0;
            slow_clk <= 1'b0;
        end else begin
            if (clk_cnt == DIV_COUNT - 1) begin
                clk_cnt  <= 26'd0;
                slow_clk <= ~slow_clk;
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end
    end

    // =========================================================================
    // Pipeline ↔ Memory interface wires
    // =========================================================================
    wire [31:0] inst_mem_read_data;
    wire        inst_mem_is_valid;
    wire [31:0] pc_out;
    wire        exception;

    wire        dmem_re,   dmem_we;
    wire [31:0] dmem_raddr, dmem_waddr, dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire [31:0] dmem_read_data;      // mux output back to pipeline

    // Memory validity — always ready (synchronous BRAM, 1-cycle latency)
    assign inst_mem_is_valid = 1'b1;

    // =========================================================================
    // MMIO Decoder
    // =========================================================================
    // BRAM-gated signals
    wire        dmem_re_bram, dmem_we_bram;
    // MMIO read path
    wire [31:0] mmio_rdata;
    wire        mmio_sel;
    // BRAM read data
    wire [31:0] bram_rdata;
    // Peripheral control
    wire        jump_clear, dbl_jump_clear;
    wire [15:0] led_wdata;
    wire        led_we;
    wire [31:0] seg_data0, seg_data1;
    // Peripheral outputs → decoder
    wire [15:0] lfsr_out;
    wire        jump_sticky, dbl_jump_sticky;

    mmio_decoder mmio_dec (
        .clk             (clk),
        .reset           (reset),
        // From pipeline
        .dmem_re         (dmem_re),
        .dmem_raddr      (dmem_raddr),
        .dmem_we         (dmem_we),
        .dmem_waddr      (dmem_waddr),
        .dmem_wdata      (dmem_wdata),
        // To BRAM
        .dmem_re_bram    (dmem_re_bram),
        .dmem_we_bram    (dmem_we_bram),
        // Read data back to pipeline
        .mmio_rdata_o    (mmio_rdata),
        .mmio_sel        (mmio_sel),
        // Peripheral control
        .jump_clear      (jump_clear),
        .dbl_jump_clear  (dbl_jump_clear),
        .led_wdata       (led_wdata),
        .led_we          (led_we),
        .seg_data0       (seg_data0),
        .seg_data1       (seg_data1),
        // Peripheral inputs
        .lfsr_out        (lfsr_out),
        .jump_sticky     (jump_sticky),
        .dbl_jump_sticky (dbl_jump_sticky)
    );

    // Read data mux: MMIO takes priority over BRAM
    assign dmem_read_data = mmio_sel ? mmio_rdata : bram_rdata;

    // =========================================================================
    // Peripheral Instantiations
    // =========================================================================

    // -- LFSR (runs on fast clock for maximum entropy) ----------------------
    lfsr16 lfsr_inst (
        .clk      (clk),
        .reset    (reset),
        .lfsr_out (lfsr_out)
    );

    // -- Debouncer: single jump (BTNC) -------------------------------------
    debouncer #(.SETTLE_CYCLES(1_000_000)) dbnc_jump (
        .clk        (clk),
        .reset      (reset),
        .btn_raw    (btn_jump),
        .clear      (jump_clear),
        .btn_stable (),            // unused — only sticky needed by game
        .btn_sticky (jump_sticky)
    );

    // -- Debouncer: double jump (BTNU) -------------------------------------
    debouncer #(.SETTLE_CYCLES(1_000_000)) dbnc_dbl (
        .clk        (clk),
        .reset      (reset),
        .btn_raw    (btn_double_jump),
        .clear      (dbl_jump_clear),
        .btn_stable (),
        .btn_sticky (dbl_jump_sticky)
    );

    // -- LED controller ----------------------------------------------------
    led_ctrl led_ctrl_inst (
        .clk     (clk),
        .reset   (reset),
        .we      (led_we),
        .wdata   (led_wdata),
        .led_out (led)
    );

    // -- 7-Segment multiplexer (fast clock for flicker-free refresh) -------
    seg7_mux #(.REFRESH_COUNT(100_000)) seg7_inst (
        .clk       (clk),
        .reset     (reset),
        .seg_data0 (seg_data0),
        .seg_data1 (seg_data1),
        .seg       (seg),
        .an        (an),
        .dp        (dp)
    );

    // =========================================================================
    // Pipeline CPU (runs on slow_clk)
    // =========================================================================
    wire        math_stall;   // from math_coproc → hazard_unit → pipeline
    wire        stall_out;    // combined stall to pipeline

    pipe pipe_u (
        .clk                  (slow_clk),
        .reset                (reset),
        .stall                (stall_out),
        .exception            (exception),
        .inst_mem_is_valid    (inst_mem_is_valid),
        .inst_mem_read_data   (inst_mem_read_data),
        .dmem_re              (dmem_re),
        .dmem_raddr           (dmem_raddr),
        .dmem_we              (dmem_we),
        .dmem_waddr           (dmem_waddr),
        .dmem_wdata           (dmem_wdata),
        .dmem_wstrb           (dmem_wstrb),
        .dmem_read_data_temp  (dmem_read_data),
        .dmem_write_valid     (1'b1),
        .dmem_read_valid      (1'b1),
        .pc_out               (pc_out)
    );

    // stall_out: driven by hazard_unit; tie low until hazard_unit integrated
    assign stall_out = 1'b0;

    // =========================================================================
    // Instruction Memory (BRAM, slow_clk domain)
    // =========================================================================
    instr_mem IMEM (
        .clk   (slow_clk),
        .pc    (pc_out),
        .instr (inst_mem_read_data)
    );

    // =========================================================================
    // Data Memory (BRAM, slow_clk domain — MMIO-gated)
    // =========================================================================
    data_mem DMEM (
        .clk   (slow_clk),
        .re    (dmem_re_bram),
        .raddr (dmem_raddr),
        .rdata (bram_rdata),
        .we    (dmem_we_bram),
        .waddr (dmem_waddr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

endmodule

