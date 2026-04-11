`timescale 1ns / 1ps

// ============================================================
// tb_pipeline_div.v
//
// Pipeline-integrated testbench for DIV / DIVU / REM / REMU.
// Uses the real instr_mem and data_mem from memory.v.
// Load imem.hex into the same directory before simulating.
//
// Test groups in imem.hex:
//   A : Signed DIV   - 20/4, -20/4, 20/-4, -20/-4
//   B : DIVU         - 20/4, 0xFFFFFFFC/4
//   C : Signed REM   - 20%6, -20%6
//   D : REMU         - 20%6
//   E : Edge cases   - div-by-zero, INT_MIN/-1
//   F : DIV then BEQ - branch shadow squash check (x10 must stay 0)
// ============================================================

module tb_pipeline_div;

    // ── Clock & Reset ────────────────────────────────────────
    reg clk, reset;

    initial clk = 0;
    always  #5 clk = ~clk;          // 100 MHz

    initial begin
        reset = 1;
        #10;
        reset = 0;
        #10;
        reset = 1;
    end

    // ── Memory interface wires ───────────────────────────────
    wire [31:0] inst_mem_read_data;
    wire        inst_mem_is_valid = 1'b1;

    wire [31:0] dmem_read_data;
    wire        dmem_write_valid = 1'b1;
    wire        dmem_read_valid  = 1'b1;

    wire        exception;
    wire [31:0] pc_out;
    wire [15:0] led_reg5;

    wire        dmem_re;
    wire [31:0] dmem_raddr;
    wire        dmem_we;
    wire [31:0] dmem_waddr;
    wire [31:0] dmem_wdata;
    wire [ 3:0] dmem_wstrb;

    // ── DUT ──────────────────────────────────────────────────
    pipe pipe_u (
        .clk                (clk),
        .reset              (reset),
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

    // ── Instruction Memory (from memory.v - reads imem.hex) ─
    instr_mem IMEM (
        .clk  (clk),
        .pc   (pc_out),
        .instr(inst_mem_read_data)
    );

    // ── Data Memory (from memory.v) ──────────────────────────
    data_mem DMEM (
        .clk   (clk),
        .re    (dmem_re),
        .raddr (dmem_raddr),
        .rdata (dmem_read_data),
        .we    (dmem_we),
        .waddr (dmem_waddr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

    // ── Per-cycle monitor ────────────────────────────────────
    always @(posedge clk) begin
        $display("t=%0t | PC=%08h | IR=%08h | div_stall=%b | x1=%0d x2=%0d x5=%0d x6=%0d x10=%0d",
                 $time,
                 pc_out,
                 inst_mem_read_data,
                 pipe_u.execute.u_math.math_stall,
                 $signed(pipe_u.regs[1]),
                 $signed(pipe_u.regs[2]),
                 $signed(pipe_u.regs[5]),
                 $signed(pipe_u.regs[6]),
                 $signed(pipe_u.regs[10]));
    end

    // ── End-of-simulation checks ─────────────────────────────
    integer pass_count, fail_count;

    task check;
        input [255:0] name;
        input  [31:0] got;
        input  [31:0] expected;
        begin
            if (got === expected) begin
                $display("  PASS  %s : got=%08h", name, got);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL  %s : got=%08h  expected=%08h", name, got, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_pipeline_div.vcd");
        $dumpvars(0, tb_pipeline_div);

        pass_count = 0;
        fail_count = 0;

        // Each DIV costs 32 stall cycles + ~5 pipeline drain = ~37 cycles @ 10ns.
        // 10 multi-cycle divides x 37 x 10ns = ~3700ns. 8000ns is comfortable.
        #8000;

        $display("\n========================================");
        $display("  DIV PIPELINE INTEGRATION TEST RESULTS ");
        $display("========================================");

        // x5 final = rem(INT_MIN, -1) = 0   (last edge-case written to x5)
        check("REM INT_MIN/-1 == 0  ", pipe_u.regs[5], 32'h0000_0000);

        // x6 final = remu(20, 6) = 2        (last op written to x6)
        check("REMU 20 % 6 == 2     ", pipe_u.regs[6], 32'h0000_0002);

        // x10 must remain 0 - the addi x10,x0,99 at PC=0x120 is in the
        // branch shadow of the BEQ at 0x11C and must be squashed
        check("Branch shadow x10==0 ", pipe_u.regs[10], 32'h0000_0000);

        $display("----------------------------------------");
        $display("  Passed: %0d   Failed: %0d", pass_count, fail_count);
        $display("========================================\n");

        $finish;
    end

endmodule

/* imem.hex contents
01400093  // addi x1, x0, 20     (20)
00400113  // addi x2, x0, 4      (4)
0220c2b3  // div  x5, x1, x2     (20 / 4 = 5)
00000013  // nop
00000013  // nop
fec00093  // addi x1, x0, -20    (-20)
00400113  // addi x2, x0, 4      (4)
0220c2b3  // div  x5, x1, x2     (-20 / 4 = -5)
00000013  // nop
00000013  // nop
01400093  // addi x1, x0, 20     (20)
ffc00113  // addi x2, x0, -4     (-4)
0220c2b3  // div  x5, x1, x2     (20 / -4 = -5)
00000013  // nop
00000013  // nop
fec00093  // addi x1, x0, -20    (-20)
ffc00113  // addi x2, x0, -4     (-4)
0220c2b3  // div  x5, x1, x2     (-20 / -4 = 5)
00000013  // nop
00000013  // nop
01400093  // addi x1, x0, 20     (20)
00400113  // addi x2, x0, 4      (4)
0220d2b3  // divu x5, x1, x2     (20 / 4 = 5)
00000013  // nop
00000013  // nop
ffc00093  // addi x1, x0, -4     (0xFFFFFFFC)
00400113  // addi x2, x0, 4      (4)
0220d2b3  // divu x5, x1, x2     (0xFFFFFFFC / 4)
00000013  // nop
00000013  // nop
01400093  // addi x1, x0, 20     (20)
00600113  // addi x2, x0, 6      (6)
0220e333  // rem  x6, x1, x2     (20 % 6 = 2)
00000013  // nop
00000013  // nop
fec00093  // addi x1, x0, -20    (-20)
00600113  // addi x2, x0, 6      (6)
0220e333  // rem  x6, x1, x2     (-20 % 6 = -2)
00000013  // nop
00000013  // nop
01400093  // addi x1, x0, 20     (20)
00600113  // addi x2, x0, 6      (6)
0220f333  // remu x6, x1, x2     (20 % 6 = 2)
00000013  // nop
00000013  // nop
00500093  // addi x1, x0, 5      (5)
00000113  // addi x2, x0, 0      (0)
0220c2b3  // div  x5, x1, x2     (5 / 0 -> 0xFFFFFFFF)
00000013  // nop
00000013  // nop
0220d2b3  // divu x5, x1, x2     (5 / 0 -> 0xFFFFFFFF)
00000013  // nop
00000013  // nop
00700093  // addi x1, x0, 7      (7)
0220e2b3  // rem  x5, x1, x2     (7 % 0 -> 7)
00000013  // nop
00000013  // nop
800000b7  // lui  x1, 0x80000    (INT_MIN: 0x80000000)
fff00113  // addi x2, x0, -1     (-1: 0xFFFFFFFF)
0220c2b3  // div  x5, x1, x2     (INT_MIN / -1 -> INT_MIN)
00000013  // nop
00000013  // nop
0220e2b3  // rem  x5, x1, x2     (INT_MIN % -1 -> 0)  <-- CHECKER READS THIS x5
00000013  // nop
00000013  // nop
00c00093  // addi x1, x0, 12     (12)
00400113  // addi x2, x0, 4      (4)
0220c3b3  // div  x7, x1, x2     (12 / 4 = 3) <-- FIXED: Was writing to x5! Now x7.
00000013  // nop
00000013  // nop
00300093  // addi x1, x0, 3      (3)
00138463  // beq  x7, x1, +8     (If 3==3, skip the next instruction) <-- FIXED: Now checks x7
06300513  // addi x10, x0, 99    (Branch shadow! Pipeline must squash this so x10 stays 0)
00000013  // nop
00000013  // nop
00000013  // nop
00000013  // nop
00000013  // nop
00000013  // nop
00000013  // nop  */