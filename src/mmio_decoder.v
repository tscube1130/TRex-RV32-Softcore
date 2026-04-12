// =============================================================================
// mmio_decoder.v — Memory-Mapped I/O Address Decoder
// =============================================================================
// Sits between the pipeline's data memory port and:
//   (a) the BRAM data memory (addresses < MMIO_BASE)
//   (b) hardware peripherals (addresses >= MMIO_BASE)
//
// GAME INPUTS:
//   sw_jump        : Switch 1 — player toggles for a SINGLE jump (normal cactus)
//   sw_double_jump : Switch 2 — player toggles for a DOUBLE jump (pair of cactus)
//   LFSR bit[0]   : Cactus type selector — 0 = single cactus, 1 = pair of cactus
//                   (C code reads LFSR and checks bit 0 to decide which cactus to spawn)
//
// MMIO Address Map (Sanjeebani uses these addresses in the C game code):
// ---------------------------------------------------------------------------
//  0x2000  READ   MMIO_SW_R     — bit[0] = jump sticky, bit[1] = double_jump sticky
//  0x2004  WRITE  MMIO_SW_CLR   — bit[0]=1 clears jump, bit[1]=1 clears double_jump
//                                  (write 32'h1 to clear jump, 32'h2 to clear dbl_jump,
//                                   32'h3 to clear both at once)
//  0x2008  READ   MMIO_LFSR_R   — bits[15:0] = 16-bit LFSR value
//                                  C code: if (lfsr & 1) → spawn cactus pair
//                                          else          → spawn single cactus
//  0x200C  WRITE  MMIO_LED_W    — bits[15:0] = 16-bit LED pattern (crash animation)
//  0x2010  WRITE  MMIO_SEG_W0   — 7-seg digits 3..0 packed as nibbles (score display)
//  0x2014  WRITE  MMIO_SEG_W1   — 7-seg digits 7..4 packed as nibbles (score display)
// ---------------------------------------------------------------------------
//
// Read path:  combinational mux — pipeline expects data same cycle as dmem_re
// Write path: registered        — peripherals latch on posedge clk
//             dmem_we_bram is gated OFF for MMIO addresses
//
// Reset polarity: active-LOW (matches pipeline.v convention)
// =============================================================================
`timescale 1ns/1ps

module mmio_decoder (
    input  wire        clk,
    input  wire        reset,              // active-LOW

    // -----------------------------------------------------------------------
    // From pipeline (data memory port)
    // -----------------------------------------------------------------------
    input  wire        dmem_re,            // read enable
    input  wire [31:0] dmem_raddr,         // read address
    input  wire        dmem_we,            // write enable
    input  wire [31:0] dmem_waddr,         // write address
    input  wire [31:0] dmem_wdata,         // write data

    // -----------------------------------------------------------------------
    // To / from BRAM (pass-through when NOT an MMIO address)
    // -----------------------------------------------------------------------
    output wire        dmem_re_bram,       // gated read  enable to BRAM
    output wire        dmem_we_bram,       // gated write enable to BRAM

    // -----------------------------------------------------------------------
    // Read data back to pipeline
    // -----------------------------------------------------------------------
    output reg  [31:0] mmio_rdata_o,       // MMIO register read result
    output wire        mmio_sel,           // HIGH = current read is in MMIO space

    // -----------------------------------------------------------------------
    // Outputs to debouncer instances
    // -----------------------------------------------------------------------
    output wire        jump_clear,         // clear sticky for Switch 1 (single jump)
    output wire        dbl_jump_clear,     // clear sticky for Switch 2 (double jump)

    // -----------------------------------------------------------------------
    // Outputs to LED controller
    // -----------------------------------------------------------------------
    output wire [15:0] led_wdata,          // 16-bit LED pattern
    output wire        led_we,             // write strobe to led_ctrl

    // -----------------------------------------------------------------------
    // Outputs to 7-segment mux (registered here, stable to seg7_mux)
    // -----------------------------------------------------------------------
    output reg  [31:0] seg_data0,          // digits 3..0 (nibble-packed)
    output reg  [31:0] seg_data1,          // digits 7..4 (nibble-packed)

    // -----------------------------------------------------------------------
    // Inputs from peripherals (feed into read mux)
    // -----------------------------------------------------------------------
    input  wire [15:0] lfsr_out,           // from lfsr16 — bit[0] = cactus type
    input  wire        jump_sticky,        // from debouncer inst 1 (Switch 1 — single jump)
    input  wire        dbl_jump_sticky     // from debouncer inst 2 (Switch 2 — double jump)
);

    // -----------------------------------------------------------------------
    // MMIO address constants
    // -----------------------------------------------------------------------
    localparam [31:0] MMIO_BASE    = 32'h0000_2000;
    localparam [31:0] MMIO_SW_R    = 32'h0000_2000;  // read both switch stickyflags
    localparam [31:0] MMIO_SW_CLR  = 32'h0000_2004;  // write to clear flags
    localparam [31:0] MMIO_LFSR_R  = 32'h0000_2008;  // read LFSR (cactus type)
    localparam [31:0] MMIO_LED_W   = 32'h0000_200C;  // write LED pattern
    localparam [31:0] MMIO_SEG_W0  = 32'h0000_2010;  // write seg digits 3..0
    localparam [31:0] MMIO_SEG_W1  = 32'h0000_2014;  // write seg digits 7..4

    // -----------------------------------------------------------------------
    // MMIO region detection
    // -----------------------------------------------------------------------
    wire is_mmio_read  = dmem_re && (dmem_raddr >= MMIO_BASE);
    wire is_mmio_write = dmem_we && (dmem_waddr >= MMIO_BASE);

    // BRAM only gets signals when NOT in MMIO space
    assign dmem_re_bram = dmem_re && !is_mmio_read;
    assign dmem_we_bram = dmem_we && !is_mmio_write;

    // mmio_sel gates the read data mux in top_fpga.v
    assign mmio_sel = is_mmio_read;

    // -----------------------------------------------------------------------
    // Write decode — combinational strobes
    // -----------------------------------------------------------------------

    // jump_clear   : fires when CPU writes 0x2004 with bit[0] = 1
    // dbl_jump_clear: fires when CPU writes 0x2004 with bit[1] = 1
    // CPU can write 32'h1 (clear jump), 32'h2 (clear dbl), or 32'h3 (clear both)
    assign jump_clear     = dmem_we && (dmem_waddr == MMIO_SW_CLR) && dmem_wdata[0];
    assign dbl_jump_clear = dmem_we && (dmem_waddr == MMIO_SW_CLR) && dmem_wdata[1];

    assign led_we    = dmem_we && (dmem_waddr == MMIO_LED_W);
    assign led_wdata = dmem_wdata[15:0];

    // 7-segment data registers — registered so seg7_mux input is always stable
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            seg_data0 <= 32'h0000_0000;
            seg_data1 <= 32'h0000_0000;
        end else begin
            if (dmem_we && (dmem_waddr == MMIO_SEG_W0))
                seg_data0 <= dmem_wdata;
            if (dmem_we && (dmem_waddr == MMIO_SEG_W1))
                seg_data1 <= dmem_wdata;
        end
    end

    // -----------------------------------------------------------------------
    // Read mux — combinational (pipeline expects data same cycle as dmem_re)
    //
    // 0x2000 → {30'b0, dbl_jump_sticky, jump_sticky}
    //   C code example:
    //     int sw = *(volatile int*)0x2000;
    //     if (sw & 1) { /* single jump */ *(volatile int*)0x2004 = 1; }
    //     if (sw & 2) { /* double jump */ *(volatile int*)0x2004 = 2; }
    //
    // 0x2008 → {16'b0, lfsr_out}
    //   C code example:
    //     int rnd = *(volatile int*)0x2008;
    //     cactus_type = (rnd & 1) ? PAIR : SINGLE;
    // -----------------------------------------------------------------------
    always @(*) begin
        case (dmem_raddr)
            MMIO_SW_R:   mmio_rdata_o = {30'b0, dbl_jump_sticky, jump_sticky};
            MMIO_LFSR_R: mmio_rdata_o = {16'b0, lfsr_out};
            default:     mmio_rdata_o = 32'h0000_0000;
        endcase
    end

endmodule
