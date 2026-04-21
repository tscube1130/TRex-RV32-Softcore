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

    // Existing outputs
    output wire [6:0]  seg,
    output wire [7:0]  an,
    output wire        dp,
    output wire [15:0] led,

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

    // -------------------------------------------------------------------------
    // Existing project top (unchanged behavior)
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
        .seg(seg),
        .an(an),
        .dp(dp),
        .led(led)
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
        .Hsync(Hsync),
        .Vsync(Vsync),
        .vgaRed(vgaRed),
        .vgaGreen(vgaGreen),
        .vgaBlue(vgaBlue),
        .led(vga_collision_led),
        .run(vga_run),
        .dead(vga_dead)
    );

endmodule
