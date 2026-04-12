// =============================================================================
// mmio_decoder.v — Memory-Mapped I/O Address Decoder
// =============================================================================
// Sits between the pipeline's data memory port and:
//   (a) the BRAM data memory (addresses < MMIO_BASE)
//   (b) hardware peripherals (addresses >= MMIO_BASE)
//
// CHANGES from original:
//   - Added dmem_wstrb input (passed from pipeline) so SW/SH/SB work correctly.
//     The write enables to BRAM and MMIO are now gated by (wstrb != 0).
//   - led_we is now also gated by (|dmem_wstrb) so a SW byte-mask of 0
//     cannot accidentally clear the LED register.
//   - Added dmem_write_valid input: MMIO registers only latch when the
//     pipeline's memory stage says the write is confirmed (prevents double-
//     latching during stall drain).
//
// GAME INPUTS:
//   sw_jump        : Switch 1 — single jump (normal cactus)
//   sw_double_jump : Switch 2 — double jump (pair of cactus)
//   LFSR bit[0]   : 0 = single cactus, 1 = pair of cactus
//
// MMIO Address Map:
// ---------------------------------------------------------------------------
//  0x2000  READ   MMIO_SW_R     — bit[0] = jump sticky, bit[1] = dbl_jump sticky
//  0x2004  WRITE  MMIO_SW_CLR   — bit[0]=1 clears jump, bit[1]=1 clears dbl_jump
//                                  write 0x1=clear jump, 0x2=clear dbl, 0x3=clear both
//  0x2008  READ   MMIO_LFSR_R   — bits[15:0] = 16-bit LFSR value
//  0x200C  WRITE  MMIO_LED_W    — bits[15:0] = LED pattern (crash animation)
//  0x2010  WRITE  MMIO_SEG_W0   — 7-seg digits 3..0 packed as nibbles
//  0x2014  WRITE  MMIO_SEG_W1   — 7-seg digits 7..4 packed as nibbles
// ---------------------------------------------------------------------------
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
    input  wire [3:0]  dmem_wstrb,         // byte-lane strobes (4'b1111 for SW)
    input  wire        dmem_write_valid,   // pipeline write-stage handshake

    // -----------------------------------------------------------------------
    // To / from BRAM
    // -----------------------------------------------------------------------
    output wire        dmem_re_bram,
    output wire        dmem_we_bram,

    // -----------------------------------------------------------------------
    // Read data back to pipeline
    // -----------------------------------------------------------------------
    output reg  [31:0] mmio_rdata_o,
    output wire        mmio_sel,

    // -----------------------------------------------------------------------
    // To debouncer instances
    // -----------------------------------------------------------------------
    output wire        jump_clear,
    output wire        dbl_jump_clear,

    // -----------------------------------------------------------------------
    // To LED controller
    // -----------------------------------------------------------------------
    output wire [15:0] led_wdata,
    output wire        led_we,

    // -----------------------------------------------------------------------
    // To 7-segment mux
    // -----------------------------------------------------------------------
    output reg  [31:0] seg_data0,          // digits 3..0
    output reg  [31:0] seg_data1,          // digits 7..4

    // -----------------------------------------------------------------------
    // From peripherals (feed read mux)
    // -----------------------------------------------------------------------
    input  wire [15:0] lfsr_out,
    input  wire        jump_sticky,
    input  wire        dbl_jump_sticky
);

    // -----------------------------------------------------------------------
    // MMIO address constants (must match game_encoding.vh)
    // -----------------------------------------------------------------------
    localparam [31:0] MMIO_BASE    = 32'h0000_2000;
    localparam [31:0] MMIO_SW_R    = 32'h0000_2000;
    localparam [31:0] MMIO_SW_CLR  = 32'h0000_2004;
    localparam [31:0] MMIO_LFSR_R  = 32'h0000_2008;
    localparam [31:0] MMIO_LED_W   = 32'h0000_200C;
    localparam [31:0] MMIO_SEG_W0  = 32'h0000_2010;
    localparam [31:0] MMIO_SEG_W1  = 32'h0000_2014;

    // -----------------------------------------------------------------------
    // Region detection — qualified write requires wstrb != 0
    // -----------------------------------------------------------------------
    wire is_mmio_read  = dmem_re  && (dmem_raddr >= MMIO_BASE);
    wire is_mmio_write = dmem_we  && (dmem_waddr >= MMIO_BASE) && (|dmem_wstrb);
    wire is_bram_write = dmem_we  && (dmem_waddr <  MMIO_BASE) && (|dmem_wstrb);

    assign dmem_re_bram = dmem_re && !is_mmio_read;
    assign dmem_we_bram = is_bram_write;

    assign mmio_sel = is_mmio_read;

    // -----------------------------------------------------------------------
    // Write decode — combinational strobes (gated by wstrb)
    // -----------------------------------------------------------------------
    assign jump_clear     = is_mmio_write && (dmem_waddr == MMIO_SW_CLR) && dmem_wdata[0];
    assign dbl_jump_clear = is_mmio_write && (dmem_waddr == MMIO_SW_CLR) && dmem_wdata[1];

    assign led_we    = is_mmio_write && (dmem_waddr == MMIO_LED_W);
    assign led_wdata = dmem_wdata[15:0];

    // -----------------------------------------------------------------------
    // 7-segment registers — latch on confirmed write (dmem_write_valid)
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            seg_data0 <= 32'hAAAA_AAAA;   // all BLANK at reset (0xA per nibble)
            seg_data1 <= 32'hAAAA_AAAA;
        end else begin
            if (is_mmio_write && dmem_write_valid && (dmem_waddr == MMIO_SEG_W0))
                seg_data0 <= dmem_wdata;
            if (is_mmio_write && dmem_write_valid && (dmem_waddr == MMIO_SEG_W1))
                seg_data1 <= dmem_wdata;
        end
    end

    // -----------------------------------------------------------------------
    // Read mux — combinational
    // -----------------------------------------------------------------------
    always @(*) begin
        case (dmem_raddr)
            MMIO_SW_R:   mmio_rdata_o = {30'b0, dbl_jump_sticky, jump_sticky};
            MMIO_LFSR_R: mmio_rdata_o = {16'b0, lfsr_out};
            default:     mmio_rdata_o = 32'h0000_0000;
        endcase
    end

endmodule