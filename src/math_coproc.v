`timescale 1ns/1ps
`include "opcode.vh"

module math_coproc (
    input  wire        clk,
    input  wire        reset,
    
    // Data Inputs from Execute Stage
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    
    // Control Inputs from Decode Stage
    input  wire [2:0]  mul_op,      // FUNC3 from the instruction
    input  wire        is_m_ext,    // High if instruction is standard MUL
    input  wire        is_mac,      // High if instruction is MAC
    input  wire        is_mvacc,    // High if instruction is MVACC
    input  wire        pipeline_stall, // Prevents accumulator from updating during a stall
    
    // Outputs back to Execute Stage
    output reg  [31:0] math_result,
    output wire        math_stall    // PLACEHOLDER: Will be used when we build the Divider!
);

    // Default stall to 0 for now. The pipeline will only freeze when we build the DIV state machine.
    assign math_stall = 1'b0; 

    // =================================================================
    // 1. THE MULTIPLIER (Combinational)
    // =================================================================
    
    // We must carefully extend the 32-bit inputs to 33 bits to handle signed vs unsigned math.
    // If the operation is unsigned (MULHU), we pad with a 0. Otherwise, we sign-extend.
    wire signed [32:0] op1_ext = (mul_op == MULHU) ? {1'b0, rs1_data} : {rs1_data[31], rs1_data};
    wire signed [32:0] op2_ext = (mul_op == MULHU || mul_op == MULHSU) ? {1'b0, rs2_data} : {rs2_data[31], rs2_data};

    // Calculate the full 64-bit product instantly
    wire signed [65:0] full_product = op1_ext * op2_ext;

    // =================================================================
    // 2. THE HIDDEN ACCUMULATOR (Synchronous)
    // =================================================================
    
    reg [31:0] mac_accumulator;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            mac_accumulator <= 32'h0;
        end
        // Only do the math if it's a MAC instruction AND the CPU isn't frozen
        else if (is_mac && !pipeline_stall) begin
            // Accumulator = Accumulator + (Lower 32 bits of Rs1 * Rs2)
            mac_accumulator <= mac_accumulator + full_product[31:0];
        end
    end

    // =================================================================
    // 3. OUTPUT ROUTING (Combinational)
    // =================================================================
    
    always @(*) begin
        if (is_mvacc) begin
            // MVACC Instruction: Dump the hidden accumulator out to the CPU
            math_result = mac_accumulator;
        end 
        else if (is_m_ext) begin
            // Standard RV32M Instructions: Route the correct slice of the 64-bit product
            case (mul_op)
                MUL:    math_result = full_product[31:0];  // Lower 32 bits
                MULH:   math_result = full_product[63:32]; // Upper 32 (Signed x Signed)
                MULHSU: math_result = full_product[63:32]; // Upper 32 (Signed x Unsigned)
                MULHU:  math_result = full_product[63:32]; // Upper 32 (Unsigned x Unsigned)
                default: math_result = 32'h0;
            endcase
        end 
        else begin
            math_result = 32'h0;
        end
    end

endmodule