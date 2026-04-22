module ObstaclesDelegate #(parameter ratio = 1, dx = 5)
    (input wire frameClk,
     input wire rst,
     input wire [8:0] ObstacleY,
     input wire [9:0] vgaX,
     input wire [8:0] vgaY,
     input wire [1:0] gameState,
     input wire onGround,
     input wire [1:0] lastJumpType,
     output wire inGrey,
     output wire inWhite,
     output wire crash_event,
     output wire [7:0] Obs1_W,
     output wire [6:0] Obs1_H,
     output reg [10:0] X_1);
 
    localparam ScreenW = 10'd640;
    localparam initOffset = 6'd40;
    localparam OBSTACLE_HIT_X = 11'd110;
    localparam CACTUS_SINGLE = 2'd1;
    localparam CACTUS_PAIR = 2'd2;
    localparam SPAWN_CHECK_FRAMES = 3'd3;

    wire Obs1_inGrey;
    wire Obs1_inWhite;
    reg [3:0] Obstacle1_SEL;
    reg [15:0] lfsr;
    reg [2:0] spawn_check_timer;
    reg obstacle_active;
    reg trailing_active;
    reg [1:0] obstacle_type;

    wire at_hit_zone = obstacle_active && (X_1 == OBSTACLE_HIT_X);
    wire trailing_hit_zone = trailing_active;

    assign crash_event =
        (at_hit_zone && (
            (onGround) ||
            (obstacle_type == CACTUS_PAIR && lastJumpType == 2'd1) ||
            (obstacle_type == CACTUS_SINGLE && lastJumpType == 2'd2)
        )) ||
        (trailing_hit_zone && (
            onGround ||
            (lastJumpType == 2'd1)
        ));

    /*
      Matches CPU-style flow:
    - periodic spawn check (every 3 frames)
    - 1-in-2 spawn chance
      - bit 3 selects single/pair cactus type
      - pair leaves a one-frame trailing hit window
    */
    always @(posedge frameClk or posedge rst) begin
        if (rst) begin
            X_1 <= ScreenW + initOffset;
            lfsr <= 16'h1ACE;
            spawn_check_timer <= SPAWN_CHECK_FRAMES;
            obstacle_active <= 1'b0;
            trailing_active <= 1'b0;
            obstacle_type <= 2'd0;
        end
        else begin
            case (gameState)
                2'b10: begin
                    lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};

                    if (spawn_check_timer > 0)
                        spawn_check_timer <= spawn_check_timer - 1'b1;
                    else begin
                        spawn_check_timer <= SPAWN_CHECK_FRAMES;
                        if (!obstacle_active && !trailing_active && (lfsr[0] == 1'b0)) begin
                            obstacle_active <= 1'b1;
                            obstacle_type <= lfsr[3] ? CACTUS_PAIR : CACTUS_SINGLE;
                            X_1 <= ScreenW + initOffset;
                        end
                    end

                    if (obstacle_active) begin
                        if (X_1 > OBSTACLE_HIT_X)
                            X_1 <= X_1 - 1'b1;
                        else begin
                            if (obstacle_type == CACTUS_PAIR)
                                trailing_active <= 1'b1;
                            obstacle_active <= 1'b0;
                            obstacle_type <= 2'd0;
                            X_1 <= OBSTACLE_HIT_X;
                        end
                    end
                    else if (trailing_active) begin
                        trailing_active <= 1'b0;
                        X_1 <= ScreenW + initOffset;
                    end
                end

                2'b00: begin
                    X_1 <= ScreenW + initOffset;
                    spawn_check_timer <= SPAWN_CHECK_FRAMES;
                    obstacle_active <= 1'b0;
                    trailing_active <= 1'b0;
                    obstacle_type <= 2'd0;
                end

                default: begin
                    X_1 <= X_1;
                    lfsr <= lfsr;
                    spawn_check_timer <= spawn_check_timer;
                    obstacle_active <= obstacle_active;
                    trailing_active <= trailing_active;
                    obstacle_type <= obstacle_type;
                end
            endcase
        end
    end

    always @(*) begin
        if (trailing_active)
            Obstacle1_SEL = 4'b0000;   // SmallA as trailing single cactus
        else if (obstacle_active && obstacle_type == CACTUS_PAIR)
            Obstacle1_SEL = 4'b0011;   // SmallC for pair cactus visual
        else
            Obstacle1_SEL = 4'b0000;   // SmallA single cactus
    end

    
    drawObstacle obs1 (
        .rst(rst),
        .ox(X_1),
        .oy(ObstacleY),
        .X(vgaX),
        .Y(vgaY),
        .select(Obstacle1_SEL),
        .inWhite(Obs1_inWhite),
        .inGrey(Obs1_inGrey));



    assign inGrey = (obstacle_active || trailing_active) ? Obs1_inGrey : 1'b0;
    assign inWhite = (obstacle_active || trailing_active) ? Obs1_inWhite : 1'b0;

endmodule