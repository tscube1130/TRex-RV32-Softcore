`timescale 1ns/1ps

module math_coproc (
    input  wire        clk,
    input  wire        reset,

    // Data Inputs from Execute Stage
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,

    // Control Inputs from Decode Stage
    input  wire [2:0]  mul_op,         // FUNC3 from the instruction
    input  wire        is_m_ext,       // High if instruction is standard MUL/DIV (funct7=0000001)
    input  wire        is_mac,         // High if instruction is MAC
    input  wire        is_mvacc,       // High if instruction is MVACC
    input  wire        pipeline_stall, // Prevents accumulator from updating during any stall

    // Outputs back to Execute Stage
    output reg  [31:0] math_result,
    output wire        math_stall      // HIGH during iterative division — freeze the pipeline
);

`include "opcode.vh"

// =================================================================
// INTERNAL: Detect which class of M-extension instruction this is
// =================================================================
wire is_div_op = is_m_ext && (mul_op == DIV  || mul_op == DIVU ||
                               mul_op == REM  || mul_op == REMU);
wire is_mul_op = is_m_ext && !is_div_op;

// =================================================================
// 1. THE MULTIPLIER (Combinational, maps to DSP slices)
// =================================================================

// Sign-extend to 33 bits for correct signed/unsigned handling.
// MULHU: both unsigned (zero-extend both)
// MULHSU: rs1 signed, rs2 unsigned
// Everything else: both signed
wire signed [32:0] op1_ext = (mul_op == MULHU)
                             ? {1'b0, rs1_data}
                             : {rs1_data[31], rs1_data};

wire signed [32:0] op2_ext = (mul_op == MULHU || mul_op == MULHSU)
                             ? {1'b0, rs2_data}
                             : {rs2_data[31], rs2_data};

(* use_dsp = "yes" *) wire signed [65:0] full_product = op1_ext * op2_ext;

// =================================================================
// 2. THE MAC ACCUMULATOR (Synchronous, DSP slice)
// =================================================================
(* use_dsp = "yes" *) reg [31:0] mac_accumulator;

always @(posedge clk or negedge reset) begin
    if (!reset)
        mac_accumulator <= 32'h0;
    // Update only when it's a MAC instruction AND pipeline is not frozen
    else if (is_mac && !pipeline_stall)
        mac_accumulator <= mac_accumulator + full_product[31:0];
end

// =================================================================
// 3. ITERATIVE DIVIDER FSM — shift-subtract, 32 iterations
//
//  Timing:
//    - Cycle 0    : DIV enters EX. is_div_op=1, div_busy=0 → div_start fires.
//                   FSM latches operands, moves to RUNNING. math_stall → 1.
//    - Cycles 1-32: RUNNING. Pipeline frozen. math_stall=1.
//    - Cycle 33   : FSM moves to DONE. math_stall=0.
//                   pipeline_freeze drops → ex_mem_wb_reg captures result.
//                   FSM moves to IDLE next clock.
//
//  Edge cases (handled combinationally in the result mux — no stall needed):
//    - Divisor == 0         : quotient = 0xFFFF_FFFF, remainder = dividend
//    - INT_MIN / -1 (signed): quotient = 0x8000_0000, remainder = 0
// =================================================================

localparam [1:0] DIV_IDLE    = 2'd0,
                 DIV_RUNNING = 2'd1,
                 DIV_DONE    = 2'd2;

reg [1:0]  div_state;
reg [4:0]  div_count;    // counts 0..31
reg [31:0] div_q;        // accumulates quotient (also used as dividend shift-register)
reg [31:0] div_r;        // partial remainder
reg [31:0] div_d;        // stored divisor magnitude
reg        div_sign_q;   // 1 = negate final quotient
reg        div_sign_r;   // 1 = negate final remainder
reg        div_is_rem;   // 1 = output remainder instead of quotient

// math_stall is HIGH only while iterating — not during DONE (result is ready)
assign math_stall = (div_state == DIV_RUNNING);

// Detect edge cases combinationally (these bypass the FSM)
wire div_by_zero     = (rs2_data == 32'd0);
wire signed_overflow = (rs1_data == 32'h8000_0000) &&
                       (rs2_data == 32'hFFFF_FFFF) &&
                       (mul_op == DIV || mul_op == REM);

// Start signal: fires for exactly 1 cycle when a new DIV enters EX
// and there are no edge cases (edge cases are answered immediately)
wire div_start = is_div_op && !div_by_zero && !signed_overflow &&
                 (div_state == DIV_IDLE) && !pipeline_stall;

always @(posedge clk or negedge reset) begin
    if (!reset) begin
        div_state  <= DIV_IDLE;
        div_count  <= 5'd0;
        div_q      <= 32'd0;
        div_r      <= 32'd0;
        div_d      <= 32'd0;
        div_sign_q <= 1'b0;
        div_sign_r <= 1'b0;
        div_is_rem <= 1'b0;
    end
    else case (div_state)

        // ----------------------------------------------------------
        DIV_IDLE: begin
            if (div_start) begin
                div_is_rem <= (mul_op == REM || mul_op == REMU);

                if (mul_op == DIV || mul_op == REM) begin
                    // Signed: work with unsigned magnitudes, track signs
                    div_q      <= rs1_data[31] ? (~rs1_data + 1'b1) : rs1_data;
                    div_d      <= rs2_data[31] ? (~rs2_data + 1'b1) : rs2_data;
                    div_sign_q <= rs1_data[31] ^ rs2_data[31]; // quotient negative?
                    div_sign_r <= rs1_data[31];                  // remainder sign = dividend sign
                end
                else begin
                    // Unsigned: use directly
                    div_q      <= rs1_data;
                    div_d      <= rs2_data;
                    div_sign_q <= 1'b0;
                    div_sign_r <= 1'b0;
                end

                div_r     <= 32'd0;
                div_count <= 5'd0;
                div_state <= DIV_RUNNING;
            end
        end

        // ----------------------------------------------------------
        // Each cycle: shift {div_r, div_q} left by 1 bit,
        // then try to subtract div_d from the new div_r.
        // If div_r >= div_d: subtract and set LSB of div_q to 1.
        // After 32 cycles: div_q = unsigned quotient, div_r = unsigned remainder.
        // ----------------------------------------------------------
        DIV_RUNNING: begin
            if ({div_r[30:0], div_q[31]} >= div_d) begin
                div_r <= {div_r[30:0], div_q[31]} - div_d;
                div_q <= {div_q[30:0], 1'b1};
            end
            else begin
                div_r <= {div_r[30:0], div_q[31]};
                div_q <= {div_q[30:0], 1'b0};
            end

            if (div_count == 5'd31)
                div_state <= DIV_DONE;
            else
                div_count <= div_count + 1'b1;
        end

        // ----------------------------------------------------------
        // DONE: math_stall=0, result mux is valid.
        // Pipeline resumes this cycle; ex_mem_wb_reg captures on next posedge.
        // Unconditionally return to IDLE.
        // ----------------------------------------------------------
        DIV_DONE: begin
            div_state <= DIV_IDLE;
        end

        default: div_state <= DIV_IDLE;

    endcase
end

// Sign-corrected outputs (only valid in DONE state)
wire [31:0] div_quotient  = div_sign_q ? (~div_q + 1'b1) : div_q;
wire [31:0] div_remainder = div_sign_r ? (~div_r + 1'b1) : div_r;

// =================================================================
// 4. OUTPUT ROUTING (Combinational)
// =================================================================
always @(*) begin
    if (is_mvacc) begin
        // Read the hidden accumulator back to the register file
        math_result = mac_accumulator;
    end
    else if (is_m_ext) begin
        case (mul_op)
            // ---- Single-cycle multiplies ----
            MUL:    math_result = full_product[31:0];   // Lower 32 bits
            MULH:   math_result = full_product[63:32];  // Upper 32, signed × signed
            MULHSU: math_result = full_product[63:32];  // Upper 32, signed × unsigned
            MULHU:  math_result = full_product[63:32];  // Upper 32, unsigned × unsigned

            // ---- Multi-cycle divides ----
            // Edge case: divide by zero
            DIV:  math_result = div_by_zero ? 32'hFFFF_FFFF :
                                signed_overflow ? 32'h8000_0000 :
                                div_quotient;

            DIVU: math_result = div_by_zero ? 32'hFFFF_FFFF : div_quotient;

            REM:  math_result = div_by_zero ? rs1_data :
                                signed_overflow ? 32'h0000_0000 :
                                div_remainder;

            REMU: math_result = div_by_zero ? rs1_data : div_remainder;

            default: math_result = 32'h0;
        endcase
    end
    else begin
        math_result = 32'h0;
    end
end

endmodule