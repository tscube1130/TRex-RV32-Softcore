`timescale 1ns / 1ps

module tb_math_coproc;

    // ---------------------------------------------------------
    // 1. Inputs (Registers) and Outputs (Wires)
    // ---------------------------------------------------------
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

`include "opcode.vh"
    // ---------------------------------------------------------
    // 2. Instantiate the Unit Under Test (UUT)
    // ---------------------------------------------------------
    math_coproc UUT (
        .clk(clk),
        .reset(reset),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .mul_op(mul_op),
        .is_m_ext(is_m_ext),
        .is_mac(is_mac),
        .is_mvacc(is_mvacc),
        .pipeline_stall(pipeline_stall),
        .math_result(math_result),
        .math_stall(math_stall)
    );

    // ---------------------------------------------------------
    // 3. Clock Generation (10ns period)
    // ---------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ---------------------------------------------------------
    // 4. The Test Sequence
    // ---------------------------------------------------------
    initial begin
        // Setup Waveform Dump
        $dumpfile("math_coproc.vcd");
        $dumpvars(0, tb_math_coproc);

        // Initialize Inputs
        reset = 0;
        rs1_data = 0; rs2_data = 0; mul_op = 0;
        is_m_ext = 0; is_mac = 0; is_mvacc = 0; pipeline_stall = 0;

        // Apply Reset
        #10;
        reset = 1;
        #10;

        $display("==================================================");
        $display("   STARTING MATH COPROCESSOR UNIT TEST   ");
        $display("==================================================");

        // -----------------------------------------------------
        // TEST 1: Standard Multiplication (5 * 6 = 30)
        // -----------------------------------------------------
        $display("-> Executing: MUL (5 * 6)");
        rs1_data = 32'd5;
        rs2_data = 32'd6;
        mul_op   = MUL;
        is_m_ext = 1; is_mac = 0; is_mvacc = 0;
        #10; 
        $display("   Result: %0d (Expected: 30)", $signed(math_result));

        // -----------------------------------------------------
        // TEST 2: First MAC Instruction (Acc = 0 + (4 * 5))
        // -----------------------------------------------------
        $display("\n-> Executing: MAC (4 * 5)");
        rs1_data = 32'd4;
        rs2_data = 32'd5;
        mul_op   = MAC;
        is_m_ext = 0; is_mac = 1; is_mvacc = 0;
        #10; // Wait a cycle for the accumulator to update
        
        // -----------------------------------------------------
        // TEST 3: Second MAC Instruction (Acc = 20 + (2 * 3))
        // -----------------------------------------------------
        $display("-> Executing: MAC (2 * 3)");
        rs1_data = 32'd2;
        rs2_data = 32'd3;
        mul_op   = MAC;
        is_m_ext = 0; is_mac = 1; is_mvacc = 0;
        #10; // Wait a cycle for the accumulator to update
        
        // -----------------------------------------------------
        // TEST 4: MVACC (Retrieve the Accumulator)
        // -----------------------------------------------------
        $display("\n-> Executing: MVACC (Retrieving Accumulator)");
        rs1_data = 32'd0; // Doesn't matter
        rs2_data = 32'd0; // Doesn't matter
        mul_op   = MVACC;
        is_m_ext = 0; is_mac = 0; is_mvacc = 1;
        #10;
        $display("   Result: %0d (Expected: 26)", $signed(math_result));

        // -----------------------------------------------------
        // TEST 5: Pipeline Stall Block Test
        // -----------------------------------------------------
        $display("\n-> Executing: MAC (10 * 10) with PIPELINE STALL");
        rs1_data = 32'd10;
        rs2_data = 32'd10;
        mul_op   = MAC;
        is_m_ext = 0; is_mac = 1; is_mvacc = 0; 
        pipeline_stall = 1; // Simulate a CPU freeze!
        #10;
        
        // Check if it ignored the math because of the stall
        is_m_ext = 0; is_mac = 0; is_mvacc = 1; pipeline_stall = 0;
        #10;
        $display("   Result: %0d (Expected: 26, because stall blocked the 100)", $signed(math_result));

        $display("==================================================");
        // -----------------------------------------------------
        // TEST 6: Negative Multiplication (MUL)
        // -----------------------------------------------------
        $display("\n-> Executing: MUL (-5 * 6)");
        rs1_data = -32'd5;
        rs2_data = 32'd6;
        mul_op   = MUL;
        is_m_ext = 1; is_mac = 0; is_mvacc = 0; pipeline_stall = 0;
        #10;
        $display("   Result: %0d (Expected: -30)", $signed(math_result));

        // -----------------------------------------------------
        // TEST 7: Negative MAC Accumulation
        // -----------------------------------------------------
        // The accumulator is currently sitting at 26 (from Test 4). 
        // Let's add -20 to it.
        $display("\n-> Executing: MAC (-4 * 5) [Acc is currently 26]");
        rs1_data = -32'd4;
        rs2_data = 32'd5;
        mul_op   = MAC;
        is_m_ext = 0; is_mac = 1; is_mvacc = 0;
        #10; // Wait a cycle for accumulator to latch
        
        $display("-> Executing: MVACC (Retrieving Accumulator)");
        mul_op   = MVACC;
        is_m_ext = 0; is_mac = 0; is_mvacc = 1;
        #10;
        $display("   Result: %0d (Expected: 6, because 26 - 20 = 6)", $signed(math_result));

        // -----------------------------------------------------
        // TEST 8: Signed vs Unsigned 64-bit Boundaries (MULH vs MULHU)
        // -----------------------------------------------------
        // We will multiply 0xFFFFFFFF by 2.
        // In Signed math: this is (-1 * 2) = -2.
        // In Unsigned math: this is (4,294,967,295 * 2) = 8,589,934,590.
        $display("\n-> Executing: High Multiplication Bound Test");
        rs1_data = 32'hFFFFFFFF; 
        rs2_data = 32'h00000002; 
        
        // Test MULH (Signed x Signed)
        mul_op   = MULH;
        is_m_ext = 1; is_mac = 0; is_mvacc = 0;
        #10;
        $display("   MULH  Result: %h (Expected: ffffffff, the upper 32 bits of -2)", math_result);
        
        // Test MULHU (Unsigned x Unsigned)
        mul_op   = MULHU;
        #10;
        $display("   MULHU Result: %h (Expected: 00000001, the upper 32 bits of 8,589,934,590)", math_result);

        // -----------------------------------------------------
        // TEST 9: Hardware Reset
        // -----------------------------------------------------
        // The accumulator is currently at 6. If we hit the reset button, it should wipe to 0.
        $display("\n-> Executing: Hardware Reset Test");
        reset = 0; // Trigger Active-Low Reset
        #10;
        reset = 1; // Release Reset
        
        // Read the accumulator again
        mul_op   = MVACC;
        is_m_ext = 0; is_mac = 0; is_mvacc = 1;
        #10;
        $display("   Result after reset: %0d (Expected: 0)", $signed(math_result));
        $finish;
    end

endmodule