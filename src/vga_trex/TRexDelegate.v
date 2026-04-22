module TRexDelegate #(parameter ratio=1)(
    input wire rst,
    input wire animationClk,
    input wire FrameClk,
    input wire jump,
    input wire dbl_jump,
    input wire duck,
    input wire [1:0] gameState,
    input wire [10:0] GroundY,
    input wire [10:0] vgaX,
    input wire [10:0] vgaY,
    output wire inGrey,
    output wire inWhite,
    output wire onGround_o,
    output wire [1:0] last_jump_type_o);
	
    reg [5:0]	DinoX;
    reg signed [10:0]	DinoY;

    wire [5:0] defaultX;
    assign defaultX = 6'd50;


    wire	Airborne;
    wire	isDuck;
    wire	isDead;
    wire	onGround;
    reg [1:0]	last_jump_type;
    wire signed [10:0] GroundY_s;
    reg jump_d;
    reg dbl_jump_d;
    wire jump_rise;
    wire dbl_jump_rise;

    
    assign GroundY_s = $signed({1'b0, GroundY});
    assign onGround = (DinoY >= GroundY_s);
    assign isDuck = duck;
    assign isDead = (gameState == 2'b01);
    wire	dino_inWhite;
    wire	dino_inGrey;
    wire [3:0]	dinoSEL; 
   /*
      Dino Movement
   */
    reg isJumping;
    reg can_double_jump;
    reg signed [10:0] velocity_y;
    localparam signed [10:0] GRAVITY_STEP = 11'sd8;
    localparam signed [10:0] JUMP_VELOCITY = -11'sd36;
    localparam signed [10:0] DOUBLE_JUMP_VELOCITY = -11'sd32;

    assign jump_rise = jump & ~jump_d;
    assign dbl_jump_rise = dbl_jump & ~dbl_jump_d;
    
    always @(posedge FrameClk or posedge rst) begin
        if (rst) begin
            DinoX <= defaultX;
            DinoY <= GroundY;
            isJumping <= 0;
            can_double_jump <= 1'b1;
            velocity_y <= 11'sd0;
            last_jump_type <= 2'd0;
            jump_d <= 1'b0;
            dbl_jump_d <= 1'b0;
        end
        else begin
            jump_d <= jump;
            dbl_jump_d <= dbl_jump;

            case (gameState)
                2'b00: begin
                    DinoY <= GroundY;
                    isJumping <= 1'b0;
                    can_double_jump <= 1'b1;
                    velocity_y <= 11'sd0;
                    last_jump_type <= 2'd0;
                end
                    
                2'b10: begin
                    if (onGround) begin
                        DinoY <= GroundY_s;
                        velocity_y <= 11'sd0;
                        isJumping <= 1'b0;
                        can_double_jump <= 1'b1;

                        if (jump_rise) begin
                            isJumping <= 1'b1;
                            velocity_y <= JUMP_VELOCITY;
                            DinoY <= GroundY_s + JUMP_VELOCITY;
                            last_jump_type <= 2'd1;
                        end
                    end
                    else begin
                        isJumping <= 1'b1;

                        if (can_double_jump && dbl_jump_rise) begin
                            velocity_y <= DOUBLE_JUMP_VELOCITY;
                            can_double_jump <= 1'b0;
                            last_jump_type <= 2'd2;
                        end
                        else begin
                            velocity_y <= velocity_y + GRAVITY_STEP;
                        end

                        DinoY <= DinoY + velocity_y;
                        if ((DinoY + velocity_y) >= GroundY_s) begin
                            DinoY <= GroundY_s;
                            velocity_y <= 11'sd0;
                            isJumping <= 1'b0;
                            can_double_jump <= 1'b1;
                        end
                    end
                end
                
                2'b01: begin
                    DinoY <= DinoY;
                    isJumping <= isJumping;
                    can_double_jump <= can_double_jump;
                    velocity_y <= velocity_y;
                    last_jump_type <= last_jump_type;
                end

                2'b11: begin
                    DinoY <= DinoY;
                    isJumping <= isJumping;
                    can_double_jump <= can_double_jump;
                    velocity_y <= velocity_y;
                    last_jump_type <= last_jump_type;
                end
            endcase   
		end
    end

    DinoFSM fsm(
        .rst(rst),
        .animationClk(animationClk),
        .gameState(gameState),
        .Airborne(~onGround),
        .onGround(onGround),
        .isDuck(isDuck),
        .DinoMovementSelect(dinoSEL));
   
    drawDino #(.ratio(ratio))
      dino (
        .rst(rst),
        .ox(DinoX),
        .oy(DinoY),
        .X(vgaX),
        .Y(vgaY),
        .select(dinoSEL),
        .inWhite(dino_inWhite),
        .inGrey(dino_inGrey));

    assign inGrey = dino_inGrey;
    assign inWhite = dino_inWhite;
    assign onGround_o = onGround;
    assign last_jump_type_o = last_jump_type;

endmodule
