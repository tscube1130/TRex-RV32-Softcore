`timescale 1ns/1ps
// ============================================================
// tb_math_coproc.v
// Comprehensive unit testbench for math_coproc.v
//
//==========================================
//for math_coproc.v
  //TOTAL : 51 tests
 // PASSED: 51
 // FAILED: 0
  //*** ALL TESTS PASSED ***
//==========================================

// Tests:
//   MUL / MULH / MULHSU / MULHU  — single-cycle
//   DIV / DIVU / REM / REMU      — 32-cycle FSM
//   MAC accumulation              — multi-instruction sequence
//   MVACC readback                — after MAC sequence
//
// Tricky cases specifically targeted:
//   - MUL immediately after DIV completes (timing)
//   - MVACC immediately after MAC sequence (no NOP gap)
//   - DIV by zero (spec: quotient=FFFF_FFFF, remainder=dividend)
//   - Signed overflow: INT_MIN / -1 (spec: quotient=INT_MIN, rem=0)
//   - Negative dividend / positive divisor
//   - Negative dividend / negative divisor
//   - MAC with negative operands (signed accumulation)
//   - MAC accumulation across many instructions, then verify MVACC
//   - MVACC while MAC accumulator = 0 (edge: no MACs done)
//   - Back-to-back DIV operations
//   - DIV result forwarded into next MUL (simulated by sequential ops)
//
// Expected output: "ALL TESTS PASSED" with zero failures.
// ============================================================

module tb_math_coproc;

    // ---- DUT ports ----
    reg         clk;
    reg         reset;
    reg  [31:0] rs1_data;
    reg  [31:0] rs2_data;
    reg  [2:0]  mul_op;
    reg         is_m_ext;
    reg         is_mac;
    reg         is_mvacc;
    reg         pipeline_stall;

    wire [31:0] math_result;
    wire        math_stall;

    // ---- DUT ----
    math_coproc dut (
        .clk            (clk),
        .reset          (reset),
        .rs1_data       (rs1_data),
        .rs2_data       (rs2_data),
        .mul_op         (mul_op),
        .is_m_ext       (is_m_ext),
        .is_mac         (is_mac),
        .is_mvacc       (is_mvacc),
        .pipeline_stall (pipeline_stall),
        .math_result    (math_result),
        .math_stall     (math_stall)
    );

    // ---- Clock: 10 ns period ----
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- Counters ----
    integer pass_cnt, fail_cnt, test_num;

    // ---- Opcode constants (mirror opcode.vh) ----
    localparam [2:0] MUL    = 3'b000,
                     MULH   = 3'b001,
                     MULHSU = 3'b010,
                     MULHU  = 3'b011,
                     DIV    = 3'b100,
                     DIVU   = 3'b101,
                     REM    = 3'b110,
                     REMU   = 3'b111;

    // ============================================================
    // Task: drive a single-cycle instruction and check immediately
    // ============================================================
    task check_single;
        input [31:0] a, b;
        input [ 2:0] op;
        input        m_ext, mac_i, mvacc_i;
        input [31:0] expected;
        input [255:0] label;
        begin
            @(negedge clk);
            rs1_data       = a;
            rs2_data       = b;
            mul_op         = op;
            is_m_ext       = m_ext;
            is_mac         = mac_i;
            is_mvacc       = mvacc_i;
            pipeline_stall = 0;
            #1;   // let combinational settle
            test_num = test_num + 1;
            if (math_result !== expected) begin
                $display("FAIL [%0d] %0s", test_num, label);
                $display("     got=%08h  expected=%08h  (a=%08h b=%08h op=%0b)",
                          math_result, expected, a, b, op);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS [%0d] %0s", test_num, label);
                pass_cnt = pass_cnt + 1;
            end
            // Latch this cycle (mimics pipeline register)
            @(posedge clk); #1;
            // Idle
            is_m_ext = 0; is_mac = 0; is_mvacc = 0;
        end
    endtask

    // ============================================================
    // Task: drive a DIV/REM, wait for FSM, check result
    // Returns number of cycles taken (should be exactly 33: 1 start + 32 iter + 1 done)
    // ============================================================
    task check_div;
        input [31:0] a, b;
        input [ 2:0] op;
        input [31:0] expected;
        input [255:0] label;
        integer timeout;
        begin
            @(negedge clk);
            rs1_data       = a;
            rs2_data       = b;
            mul_op         = op;
            is_m_ext       = 1;
            is_mac         = 0;
            is_mvacc       = 0;
            pipeline_stall = 0;

            // Capture start cycle
            @(posedge clk); #1;
            is_m_ext = 0;   // In a real pipeline this stays 1 because id_ex_reg is frozen.
                            // Here we deassert to prevent re-trigger once FSM is RUNNING.
                            // (The FSM checks div_state==IDLE for the start condition.)

            // Wait for math_stall to go LOW (DONE state)
            timeout = 0;
            while (math_stall && timeout < 50) begin
                @(posedge clk); #1;
                timeout = timeout + 1;
            end

            // Re-assert is_m_ext so the result mux outputs the right value
            @(negedge clk);
            is_m_ext = 1;
            mul_op   = op;
            #1;

            test_num = test_num + 1;
            if (math_result !== expected) begin
                $display("FAIL [%0d] %0s  (%0d cycles)", test_num, label, timeout);
                $display("     got=%08h  expected=%08h  (a=%08h b=%08h op=%0b)",
                          math_result, expected, a, b, op);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS [%0d] %0s  (%0d cycles)", test_num, label, timeout);
                pass_cnt = pass_cnt + 1;
            end

            @(posedge clk); #1;
            is_m_ext = 0;
        end
    endtask

    // ============================================================
    // Task: drive a MAC instruction (result goes to accumulator, not checked here)
    // ============================================================
    task do_mac;
        input [31:0] a, b;
        begin
            @(negedge clk);
            rs1_data       = a;
            rs2_data       = b;
            mul_op         = MUL;
            is_m_ext       = 0;
            is_mac         = 1;
            is_mvacc       = 0;
            pipeline_stall = 0;
            @(posedge clk); #1;
            is_mac = 0;
        end
    endtask

    // ============================================================
    // Task: do MVACC and check accumulator value
    // ============================================================
    task check_mvacc;
        input [31:0] expected;
        input [255:0] label;
        begin
            @(negedge clk);
            rs1_data       = 0;
            rs2_data       = 0;
            mul_op         = MUL;
            is_m_ext       = 0;
            is_mac         = 0;
            is_mvacc       = 1;
            pipeline_stall = 0;
            #1;
            test_num = test_num + 1;
            if (math_result !== expected) begin
                $display("FAIL [%0d] %0s", test_num, label);
                $display("     got=%08h  expected=%08h", math_result, expected);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS [%0d] %0s", test_num, label);
                pass_cnt = pass_cnt + 1;
            end
            @(posedge clk); #1;
            is_mvacc = 0;
        end
    endtask

    // ============================================================
    // MAIN TEST SEQUENCE
    // ============================================================
    initial begin
        pass_cnt = 0; fail_cnt = 0; test_num = 0;
        reset          = 0;
        is_m_ext       = 0; is_mac = 0; is_mvacc = 0;
        pipeline_stall = 0;
        rs1_data = 0; rs2_data = 0; mul_op = 0;

        repeat(3) @(posedge clk);
        reset = 1;
        @(posedge clk); #1;

        // ========================================================
        $display("\n===== MUL (lower 32) =====");
        // ========================================================
        check_single(32'd10,       32'd3,           MUL, 1,0,0, 32'd30,            "MUL 10*3=30");
        check_single(32'hFFFFFFFF, 32'd2,           MUL, 1,0,0, 32'hFFFFFFFE,      "MUL -1*2=-2");
        check_single(32'hFFFFFFFF, 32'hFFFFFFFF,    MUL, 1,0,0, 32'd1,             "MUL -1*-1=1");
        check_single(32'd0,        32'hDEADBEEF,    MUL, 1,0,0, 32'd0,             "MUL 0*anything=0");
        check_single(32'h7FFFFFFF, 32'd2,           MUL, 1,0,0, 32'hFFFFFFFE,      "MUL INT_MAX*2 (wrap)");
        check_single(32'h80000000, 32'hFFFFFFFF,    MUL, 1,0,0, 32'h80000000,      "MUL INT_MIN*-1 (wrap)");

        // ========================================================
        $display("\n===== MULH (upper 32, signed x signed) =====");
        // ========================================================
        check_single(32'd10,       32'd3,           MULH, 1,0,0, 32'd0,            "MULH 10*3 upper=0");
        check_single(32'hFFFFFFFF, 32'd1,           MULH, 1,0,0, 32'hFFFFFFFF,     "MULH -1*1 upper=-1");
        check_single(32'hFFFFFFFF, 32'hFFFFFFFF,    MULH, 1,0,0, 32'd0,            "MULH -1*-1 upper=0");
        // 0x7FFFFFFF * 0x7FFFFFFF = 0x3FFF_FFFF_0000_0001 → upper = 0x3FFFFFFF
        check_single(32'h7FFFFFFF, 32'h7FFFFFFF,    MULH, 1,0,0, 32'h3FFFFFFF,     "MULH INT_MAX^2 upper");
        // 0x80000000 * 0x80000000 = 0x40000000_00000000 → upper = 0x40000000
        check_single(32'h80000000, 32'h80000000,    MULH, 1,0,0, 32'h40000000,     "MULH INT_MIN^2 upper");

        // ========================================================
        $display("\n===== MULHSU (upper 32, signed x unsigned) =====");
        // ========================================================
        // -1 (signed) * 0xFFFFFFFF (unsigned) = -0xFFFFFFFF = 0xFFFF_FFFF_0000_0001 → upper=0xFFFFFFFF
                check_single(32'hFFFFFFFF, 32'hFFFFFFFF,    MULHSU, 1,0,0, 32'hFFFFFFFF,   "MULHSU -1*UINT_MAX upper");
        check_single(32'd1,        32'd1,            MULHSU, 1,0,0, 32'd0,          "MULHSU 1*1 upper=0");

        // ========================================================
        $display("\n===== MULHU (upper 32, unsigned x unsigned) =====");
        // ========================================================
        // 0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE_00000001 → upper = 0xFFFFFFFE
        check_single(32'hFFFFFFFF, 32'hFFFFFFFF,    MULHU, 1,0,0, 32'hFFFFFFFE,    "MULHU UINT_MAX^2 upper");
        check_single(32'd0,        32'hFFFFFFFF,    MULHU, 1,0,0, 32'd0,            "MULHU 0*anything upper=0");

        // ========================================================
        $display("\n===== DIV (signed quotient) =====");
        // ========================================================
        check_div(32'd10,        32'd3,          DIV, 32'd3,         "DIV  10/3=3");
        check_div(32'd7,         32'd7,          DIV, 32'd1,         "DIV  7/7=1");
        check_div(32'd1,         32'd2,          DIV, 32'd0,         "DIV  1/2=0 (truncate toward zero)");
        check_div(32'hFFFFFFF7,  32'd3,          DIV, 32'hFFFFFFFD,  "DIV  -9/3=-3");
        check_div(32'd9,         32'hFFFFFFFD,   DIV, 32'hFFFFFFFD,  "DIV  9/-3=-3");
        check_div(32'hFFFFFFF7,  32'hFFFFFFFD,   DIV, 32'd3,         "DIV  -9/-3=3");

        // ========================================================
        $display("\n===== DIV edge cases (combinational, no FSM) =====");
        // ========================================================

        // DIV by zero → quotient = 0xFFFF_FFFF
        @(negedge clk);
        rs1_data=32'd7; rs2_data=32'd0; mul_op=DIV; is_m_ext=1; is_mac=0; is_mvacc=0; pipeline_stall=0;
        #1; test_num=test_num+1;
        if (math_result !== 32'hFFFF_FFFF) begin
            $display("FAIL [%0d] DIV by zero: got=%08h exp=FFFFFFFF", test_num, math_result);
            fail_cnt=fail_cnt+1;
        end else begin $display("PASS [%0d] DIV by zero quotient=FFFFFFFF", test_num); pass_cnt=pass_cnt+1; end
        @(posedge clk); #1; is_m_ext=0;

        // INT_MIN / -1 → quotient = INT_MIN (overflow)
        @(negedge clk);
        rs1_data=32'h80000000; rs2_data=32'hFFFFFFFF; mul_op=DIV; is_m_ext=1; is_mac=0; is_mvacc=0; pipeline_stall=0;
        #1; test_num=test_num+1;
        if (math_result !== 32'h80000000) begin
            $display("FAIL [%0d] DIV INT_MIN/-1: got=%08h exp=80000000", test_num, math_result);
            fail_cnt=fail_cnt+1;
        end else begin $display("PASS [%0d] DIV INT_MIN/-1 overflow=INT_MIN", test_num); pass_cnt=pass_cnt+1; end
        @(posedge clk); #1; is_m_ext=0;

        // ========================================================
        $display("\n===== DIVU (unsigned quotient) =====");
        // ========================================================
        check_div(32'd10,        32'd3,          DIVU, 32'd3,         "DIVU 10/3=3");
        check_div(32'hFFFFFFFF,  32'd2,          DIVU, 32'h7FFFFFFF,  "DIVU UINT_MAX/2");

        // DIVU by zero → 0xFFFF_FFFF
        @(negedge clk);
        rs1_data=32'hABCD; rs2_data=32'd0; mul_op=DIVU; is_m_ext=1; is_mac=0; is_mvacc=0; pipeline_stall=0;
        #1; test_num=test_num+1;
        if (math_result !== 32'hFFFF_FFFF) begin
            $display("FAIL [%0d] DIVU by zero: got=%08h exp=FFFFFFFF", test_num, math_result);
            fail_cnt=fail_cnt+1;
        end else begin $display("PASS [%0d] DIVU by zero=FFFFFFFF", test_num); pass_cnt=pass_cnt+1; end
        @(posedge clk); #1; is_m_ext=0;

        // ========================================================
        $display("\n===== REM (signed remainder) =====");
        // ========================================================
        check_div(32'd10,        32'd3,          REM, 32'd1,          "REM  10%3=1");
        // Sign follows dividend: -7 % 3 = -1
        check_div(32'hFFFFFFF9,  32'd3,          REM, 32'hFFFFFFFF,   "REM  -7%3=-1");
        //  7 % -3 = 1 (sign of dividend)
        check_div(32'd7,         32'hFFFFFFFD,   REM, 32'd1,          "REM  7%-3=1");
        // -7 % -3 = -1
        check_div(32'hFFFFFFF9,  32'hFFFFFFFD,   REM, 32'hFFFFFFFF,   "REM  -7%-3=-1");

        // REM by zero → remainder = dividend
        @(negedge clk);
        rs1_data=32'd7; rs2_data=32'd0; mul_op=REM; is_m_ext=1; is_mac=0; is_mvacc=0; pipeline_stall=0;
        #1; test_num=test_num+1;
        if (math_result !== 32'd7) begin
            $display("FAIL [%0d] REM by zero: got=%08h exp=00000007", test_num, math_result);
            fail_cnt=fail_cnt+1;
        end else begin $display("PASS [%0d] REM by zero=dividend", test_num); pass_cnt=pass_cnt+1; end
        @(posedge clk); #1; is_m_ext=0;

        // REM INT_MIN / -1 → remainder = 0
        @(negedge clk);
        rs1_data=32'h80000000; rs2_data=32'hFFFFFFFF; mul_op=REM; is_m_ext=1; is_mac=0; is_mvacc=0; pipeline_stall=0;
        #1; test_num=test_num+1;
        if (math_result !== 32'd0) begin
            $display("FAIL [%0d] REM INT_MIN/-1: got=%08h exp=00000000", test_num, math_result);
            fail_cnt=fail_cnt+1;
        end else begin $display("PASS [%0d] REM INT_MIN/-1 overflow=0", test_num); pass_cnt=pass_cnt+1; end
        @(posedge clk); #1; is_m_ext=0;

        // ========================================================
        $display("\n===== REMU (unsigned remainder) =====");
        // ========================================================
        check_div(32'd10,        32'd3,          REMU, 32'd1,         "REMU 10%3=1");
        check_div(32'hFFFFFFFF,  32'd2,          REMU, 32'd1,         "REMU UINT_MAX%2=1");

        // REMU by zero → remainder = dividend
        @(negedge clk);
        rs1_data=32'hDEAD; rs2_data=32'd0; mul_op=REMU; is_m_ext=1; is_mac=0; is_mvacc=0; pipeline_stall=0;
        #1; test_num=test_num+1;
        if (math_result !== 32'hDEAD) begin
            $display("FAIL [%0d] REMU by zero: got=%08h exp=0000DEAD", test_num, math_result);
            fail_cnt=fail_cnt+1;
        end else begin $display("PASS [%0d] REMU by zero=dividend", test_num); pass_cnt=pass_cnt+1; end
        @(posedge clk); #1; is_m_ext=0;

        // ========================================================
        $display("\n===== MAC + MVACC =====");
        // ========================================================

        // MVACC on a fresh reset → accumulator should be 0
        check_mvacc(32'd0, "MVACC after reset = 0");

        // Simple accumulation: 3*4=12, 5*2=10 → acc=22
        do_mac(32'd3, 32'd4);
        do_mac(32'd5, 32'd2);
        check_mvacc(32'd22, "MVACC after 3*4+5*2 = 22");

        // MAC does NOT reset between MVACC calls — acc persists.
        // Continue: 1*1=1 → acc = 22+1 = 23
        do_mac(32'd1, 32'd1);
        check_mvacc(32'd23, "MVACC acc still accumulates after read = 23");

        // Immediate MVACC again (no new MACs) → same accumulator
        check_mvacc(32'd23, "MVACC twice in a row = still 23");

        // MAC with negative operands: acc=23 + (-2)*5 = 23-10 = 13
        do_mac(32'hFFFFFFFE, 32'd5);
        check_mvacc(32'd13, "MVACC with negative MAC (-2*5): 23-10=13");

        // Overflow wrapping: add a large value
        // acc=13, then + (0x7FFFFFFF * 2) = 13 + 0xFFFFFFFE = 0x0000000B (wraps)
        do_mac(32'h7FFFFFFF, 32'd2);
        check_mvacc(32'h0000000B, "MVACC accumulator overflow wraps correctly: 13+0xFFFFFFFE=0xB");

        // ========================================================
        $display("\n===== Tricky: MUL immediately after DIV completes =====");
        // ========================================================
        // Run a DIV (20/4=5), then immediately drive a MUL (3*3=9) in the same
        // clock cycle after DIV_DONE. Verify MUL result is correct.
        check_div(32'd20, 32'd4, DIV, 32'd5, "DIV 20/4=5 (pre-MUL test)");
        check_single(32'd3, 32'd3, MUL, 1,0,0, 32'd9, "MUL 3*3=9 immediately after DIV");

        // ========================================================
        $display("\n===== Tricky: Back-to-back DIV operations =====");
        // ========================================================
        check_div(32'd100, 32'd7,   DIV,  32'd14,        "DIV  100/7=14");
        check_div(32'd100, 32'd7,   REM,  32'd2,          "REM  100%7=2  (back-to-back)");
        check_div(32'hFFFFFF9C, 32'd7, DIV, 32'hFFFFFFF2, "DIV  -100/7=-14");

        // ========================================================
        $display("\n===== Tricky: MAC accumulation inside a simulated loop =====");
        // ========================================================
        // Simulate: for(i=1;i<=5;i++) acc += i*i  → acc = 1+4+9+16+25 = 55
        // Accumulator currently = 0x0000000B from above, so first reset it via reset pulse.
        @(negedge clk); reset=0; @(posedge clk); #1;
        @(negedge clk); reset=1; @(posedge clk); #1;   // re-reset (clears accumulator)

        do_mac(32'd1, 32'd1);   // 1*1=1
        do_mac(32'd2, 32'd2);   // 2*2=4
        do_mac(32'd3, 32'd3);   // 3*3=9
        do_mac(32'd4, 32'd4);   // 4*4=16
        do_mac(32'd5, 32'd5);   // 5*5=25
        check_mvacc(32'd55, "MVACC sum-of-squares 1..5 = 55");

        // ========================================================
        $display("\n===== Tricky: pipeline_stall blocks MAC update =====");
        // ========================================================
        // Current acc = 55. Drive a MAC with pipeline_stall=1.
        // Accumulator must NOT update.
        @(negedge clk);
        rs1_data=32'd10; rs2_data=32'd10; mul_op=MUL; is_m_ext=0; is_mac=1; is_mvacc=0;
        pipeline_stall=1;     // stall asserted — accumulator must NOT change
        @(posedge clk); #1;
        pipeline_stall=0; is_mac=0;
        // Verify accumulator is still 55
        check_mvacc(32'd55, "MVACC unchanged when MAC fires during pipeline_stall");

        // ========================================================
        $display("\n===== math_stall timing check =====");
        // ========================================================
        // Start a DIV. math_stall must go HIGH within 1 cycle, then LOW after exactly 32.
        @(negedge clk);
        rs1_data=32'd1000; rs2_data=32'd13; mul_op=DIV;
        is_m_ext=1; is_mac=0; is_mvacc=0; pipeline_stall=0;
        @(posedge clk); #1;
        is_m_ext=0;
        test_num=test_num+1;
        if (!math_stall) begin
            $display("FAIL [%0d] math_stall should be HIGH after DIV start", test_num);
            fail_cnt=fail_cnt+1;
        end else begin $display("PASS [%0d] math_stall HIGH after DIV start", test_num); pass_cnt=pass_cnt+1; end

        // Count cycles until math_stall drops
        begin : stall_count_block
            integer cyc;
            cyc = 0;
            while (math_stall && cyc < 40) begin @(posedge clk); #1; cyc=cyc+1; end
            test_num=test_num+1;
            if (cyc !== 32) begin
                $display("FAIL [%0d] DIV took %0d cycles, expected 32", test_num, cyc);
                fail_cnt=fail_cnt+1;
            end else begin $display("PASS [%0d] DIV took exactly 32 cycles", test_num); pass_cnt=pass_cnt+1; end
        end

        // Check 1000/13=76
        @(negedge clk);
        is_m_ext=1; mul_op=DIV; rs1_data=32'd1000; rs2_data=32'd13; pipeline_stall=0;
        #1; test_num=test_num+1;
        if (math_result !== 32'd76) begin
            $display("FAIL [%0d] 1000/13: got=%0d exp=76", test_num, math_result);
            fail_cnt=fail_cnt+1;
        end else begin $display("PASS [%0d] 1000/13=76", test_num); pass_cnt=pass_cnt+1; end
        @(posedge clk); #1; is_m_ext=0;

        // ========================================================
        $display("\n==========================================");
        $display("  TOTAL : %0d tests", test_num);
        $display("  PASSED: %0d", pass_cnt);
        $display("  FAILED: %0d", fail_cnt);
        if (fail_cnt == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d FAILURES — CHECK ABOVE ***", fail_cnt);
        $display("==========================================\n");
        $finish;
    end

    // Watchdog
    initial begin
        #200000;
        $display("TIMEOUT — simulation hung");
        $finish;
    end

endmodule

