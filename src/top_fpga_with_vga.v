`timescale 1ns / 1ps
// =============================================================================
// top_fpga_with_vga.v
// Dual-output top level:
//   1) Existing CS224 CPU/MMIO game path (7-seg + LEDs)
//   2) VGA T-Rex graphics path (Hsync/Vsync/RGB)
//
// This keeps the existing game path unchanged while adding VGA controls
// and output as a separate subsystem.
// =============================================================================

module top_fpga_with_vga #(
    parameter IMEMSIZE = 4096,
    parameter DMEMSIZE = 4096,
    parameter IMEM_INIT_FILE = "imem.hex",
    parameter DMEM_INIT_FILE = "dmem.hex"
)(
    input  wire        clk,
    input  wire        reset,

    // Existing CPU game controls
    input  wire        sw_jump,
    input  wire        sw_double_jump,

    // Separate VGA game controls
    input  wire        vga_duck,
    input  wire        vga_restart,

    // Existing outputs (blanked in VGA mode)
    output wire [6:0]  seg,
    output wire [7:0]  an,
    output wire        dp,
    output wire [15:0] led,

    // Audio output from existing CPU game path
    output wire        audio_out,
    output wire        audio_en,

    // VGA outputs (separate path)
    output wire        Hsync,
    output wire        Vsync,
    output wire [2:0]  vgaRed,
    output wire [2:0]  vgaGreen,
    output wire [1:0]  vgaBlue,
    output wire        vga_run,
    output wire        vga_dead,
    output wire        vga_collision_led
);

    wire [6:0] seg_cpu;
    wire [7:0] an_cpu;
    wire       dp_cpu;
    wire       vga_score_tick;
    wire [13:0] vga_score_value;

    vga_score_cpu_side u_vga_cpu_score (
        .clk(clk),
        .rst(reset),
        .game_run(vga_run),
        .game_dead(vga_dead),
        .score_tick_i(vga_score_tick),
        .score_value_o(vga_score_value)
    );

    // -------------------------------------------------------------------------
    // Existing project top (kept instantiated for compatibility)
    // -------------------------------------------------------------------------
    top_fpga #(
        .IMEMSIZE(IMEMSIZE),
        .DMEMSIZE(DMEMSIZE),
        .IMEM_INIT_FILE(IMEM_INIT_FILE),
        .DMEM_INIT_FILE(DMEM_INIT_FILE)
    ) u_existing_top (
        .clk(clk),
        .reset(reset),
        .sw_jump(sw_jump),
        .sw_double_jump(sw_double_jump),
        .seg(seg_cpu),
        .an(an_cpu),
        .dp(dp_cpu),
        .led(led),
        .audio_out(audio_out),
        .audio_en(audio_en)
    );

    // -------------------------------------------------------------------------
    // VGA T-Rex top (separate controls and outputs)
    // -------------------------------------------------------------------------
    TRexTop u_vga_trex (
        .clk(clk),
        .btnR(reset),
        .duckButton(vga_duck),
        .jumpButton(sw_jump),
        .restart(vga_restart),
        .score_value_i(vga_score_value),
        .score_tick_o(vga_score_tick),
        .Hsync(Hsync),
        .Vsync(Vsync),
        .vgaRed(vgaRed),
        .vgaGreen(vgaGreen),
        .vgaBlue(vgaBlue),
        .led(vga_collision_led),
        .run(vga_run),
        .dead(vga_dead)
    );

    // Disable 7-seg display when the VGA-integrated top is used.
    assign seg = 7'b1111111;
    assign an = 8'b11111111;
    assign dp = 1'b1;

endmodule
