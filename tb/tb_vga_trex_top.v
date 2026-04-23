`timescale 1ns/1ps

module tb_vga_trex_top;

    reg clk;
    reg btnR;
    reg duckButton;
    reg jumpButton;
    reg restart;
    reg [13:0] score_value_i;

    wire score_tick_o;
    wire Hsync;
    wire Vsync;
    wire [2:0] vgaRed;
    wire [2:0] vgaGreen;
    wire [1:0] vgaBlue;
    wire led;
    wire run;
    wire dead;

    reg frame_clk_fast;
    reg move_clk_fast;
    reg anim_clk_fast;

    integer pass;
    integer fail;
    integer hsync_toggles;
    integer score_ticks;
    reg last_hsync;

    TRexTop dut (
        .clk(clk),
        .btnR(btnR),
        .duckButton(duckButton),
        .jumpButton(jumpButton),
        .restart(restart),
        .score_value_i(score_value_i),
        .score_tick_o(score_tick_o),
        .Hsync(Hsync),
        .Vsync(Vsync),
        .vgaRed(vgaRed),
        .vgaGreen(vgaGreen),
        .vgaBlue(vgaBlue),
        .led(led),
        .run(run),
        .dead(dead)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial frame_clk_fast = 1'b0;
    always #40 frame_clk_fast = ~frame_clk_fast;

    initial move_clk_fast = 1'b0;
    always #20 move_clk_fast = ~move_clk_fast;

    initial anim_clk_fast = 1'b0;
    always #30 anim_clk_fast = ~anim_clk_fast;

    task check_bit;
        input [127:0] name;
        input got;
        input expected;
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

    task check_true;
        input [127:0] name;
        input cond;
        begin
            if (cond) begin
                $display("  PASS [%0s]", name);
                pass = pass + 1;
            end else begin
                $display("  FAIL [%0s]", name);
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_vga_trex_top.vcd");
        $dumpvars(0, tb_vga_trex_top);

        pass = 0;
        fail = 0;

        btnR = 1'b0;
        duckButton = 1'b0;
        jumpButton = 1'b0;
        restart = 1'b0;
        score_value_i = 14'd1234;

        // Force slow internal clocks and debounced controls to fast deterministic sources.
        force dut.pixel_clk = clk;
        force dut.Frame_Clk = frame_clk_fast;
        force dut.moveClk = move_clk_fast;
        force dut.animateClock = anim_clk_fast;
        force dut.rst = 1'b1;
        force dut.jump = 1'b0;
        force dut.duck = 1'b0;

        repeat (5) @(posedge clk);
        force dut.rst = 1'b0;
        repeat (5) @(posedge clk);

        $display("=== TEST 1: Reset state ===");
        check_bit("T1_run_LOW", run, 1'b0);
        check_bit("T1_dead_LOW", dead, 1'b0);

        $display("=== TEST 2: Jump starts game ===");
        force dut.jump = 1'b1;
        @(posedge clk);
        force dut.jump = 1'b0;
        repeat (3) @(posedge clk);
        check_bit("T2_run_HIGH", run, 1'b1);
        check_bit("T2_dead_LOW", dead, 1'b0);

        $display("=== TEST 3: Hsync toggles under pixel clock ===");
        hsync_toggles = 0;
        last_hsync = Hsync;
        repeat (5000) begin
            @(posedge clk);
            if (Hsync !== last_hsync) begin
                hsync_toggles = hsync_toggles + 1;
                last_hsync = Hsync;
            end
        end
        check_true("T3_hsync_toggles", (hsync_toggles >= 2));

        $display("=== TEST 4: Score tick pulses during run state ===");
        score_ticks = 0;
        repeat (40) begin
            @(posedge frame_clk_fast);
            if (score_tick_o)
                score_ticks = score_ticks + 1;
        end
        check_true("T4_score_tick_seen", (score_ticks > 0));

        $display("=== TEST 5: Force crash event -> dead state ===");
        force dut.crash_event = 1'b1;
        @(posedge frame_clk_fast);
        force dut.crash_event = 1'b0;
        repeat (10) @(posedge clk);
        check_bit("T5_dead_HIGH", dead, 1'b1);
        check_bit("T5_run_LOW", run, 1'b0);

        $display("=== TEST 6: Restart returns to init state ===");
        restart = 1'b1;
        repeat (2) @(posedge clk);
        restart = 1'b0;
        repeat (4) @(posedge clk);
        check_bit("T6_dead_LOW", dead, 1'b0);
        check_bit("T6_run_LOW", run, 1'b0);

        $display("=== TEST 7: RGB outputs stay known values ===");
        repeat (2000) begin
            @(posedge clk);
            if ((^vgaRed === 1'bx) || (^vgaGreen === 1'bx) || (^vgaBlue === 1'bx))
                fail = fail + 1;
        end
        check_true("T7_rgb_no_x", (fail == 0));

        release dut.crash_event;
        release dut.duck;
        release dut.jump;
        release dut.rst;
        release dut.animateClock;
        release dut.moveClk;
        release dut.Frame_Clk;
        release dut.pixel_clk;

        $display("\n==== TB SUMMARY ====");
        $display("PASS=%0d FAIL=%0d", pass, fail);

        if (fail != 0)
            $fatal(1, "tb_vga_trex_top FAILED");
        else
            $finish;
    end

endmodule
