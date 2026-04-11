`timescale 1ns / 1ps

module top_nexys #(
    parameter IMEMSIZE = 4096,
    parameter DMEMSIZE = 4096
)(
    input  wire       clk,      // 100 MHz board clock
    input  wire       reset,    // active-high reset (Nexys A7 button)
    output wire [15:0] led      // LEDs (shows lower 16 bits of register 5)
);

    // -------------------------------------------------------------
    // 1. Clock divider: 100 MHz → ~1 Hz
    // -------------------------------------------------------------
    reg  [25:0] clk_cnt;
    reg         slow_clk;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            clk_cnt  <= 26'd0;
            slow_clk <= 1'b0;
        end else begin
            if (clk_cnt == 26'd49_999_999) begin
                clk_cnt  <= 26'd0;
                slow_clk <= ~slow_clk;
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------
    // 2. Memory interface wires
    // -------------------------------------------------------------
    wire [31:0] inst_mem_read_data;
    wire        inst_mem_is_valid = 1'b1;   // always ready

    wire [31:0] dmem_read_data;
    wire        dmem_write_valid = 1'b1;
    wire        dmem_read_valid  = 1'b1;

    // -------------------------------------------------------------
    // 3. Pipeline CPU (with all ports, including data memory ports)
    // -------------------------------------------------------------
    wire        exception;
    wire [31:0] pc_out;
    wire [15:0] led_reg5;          // from pipe (lower 16 bits of regs[5])

    // Data memory ports (outputs from pipe)
    wire        dmem_re;
    wire [31:0] dmem_raddr;
    wire        dmem_we;
    wire [31:0] dmem_waddr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;

    pipe pipe_u (
        .clk                (slow_clk),
        .reset              (~reset),
        .stall              (1'b0),
        .exception          (exception),
        .pc_out             (pc_out),
        .inst_mem_is_valid  (inst_mem_is_valid),
        .inst_mem_read_data (inst_mem_read_data),
        .dmem_read_data_temp(dmem_read_data),
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

    // -------------------------------------------------------------
    // 4. Instruction memory (ROM)
    // -------------------------------------------------------------
    instr_mem IMEM (
        .clk  (slow_clk),
        .pc   (pc_out),
        .instr(inst_mem_read_data)
    );

    // -------------------------------------------------------------
    // 5. Data memory (RAM)
    // -------------------------------------------------------------
    data_mem DMEM (
        .clk   (slow_clk),
        .re    (dmem_re),
        .raddr (dmem_raddr),
        .rdata (dmem_read_data),
        .we    (dmem_we),
        .waddr (dmem_waddr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

    // -------------------------------------------------------------
    // 6. Connect LEDs to lower 16 bits of register 5
    // -------------------------------------------------------------
    assign led = led_reg5;

endmodule