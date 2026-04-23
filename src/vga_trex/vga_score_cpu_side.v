module vga_score_cpu_side(
    input  wire        clk,
    input  wire        rst,
    input  wire        game_run,
    input  wire        game_dead,
    input  wire        score_tick_i,
    output wire [13:0] score_value_o
);

    reg tick_sync_0;
    reg tick_sync_1;
    reg tick_sync_2;

    reg [31:0] score_base;

    wire in_init_state = !game_run && !game_dead;
    wire score_tick_rise = tick_sync_1 & ~tick_sync_2;

    wire [31:0] mac_score_raw;
    wire        mac_stall_unused;
    wire [31:0] score_delta = mac_score_raw - score_base;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tick_sync_0 <= 1'b0;
            tick_sync_1 <= 1'b0;
            tick_sync_2 <= 1'b0;
            score_base <= 32'd0;
        end
        else begin
            tick_sync_0 <= score_tick_i;
            tick_sync_1 <= tick_sync_0;
            tick_sync_2 <= tick_sync_1;

            if (in_init_state)
                score_base <= mac_score_raw;
        end
    end

    // Reuse the shared math_coproc MAC accumulator path from the CPU subsystem.
    math_coproc u_cpu_side_score_math (
        .clk            (clk),
        .reset          (~rst),
        .rs1_data       (32'd1),
        .rs2_data       (32'd1),
        .mul_op         (3'b000),
        .is_m_ext       (1'b0),
        .is_mac         (score_tick_rise && game_run),
        .is_mvacc       (1'b1),
        .pipeline_stall (1'b0),
        .math_result    (mac_score_raw),
        .math_stall     (mac_stall_unused)
    );

    assign score_value_o = score_delta[13:0] % 14'd10000;

endmodule
