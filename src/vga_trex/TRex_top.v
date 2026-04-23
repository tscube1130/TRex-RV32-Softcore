module TRexTop(
	       input wire 	 clk,
	       input wire 	 btnR, // Reset button
	       input wire 	 duckButton,
	       input wire 	 jumpButton,
           input wire    restart,
         input wire [13:0] score_value_i,
         output wire       score_tick_o,
	       output wire 	 Hsync,
	       output wire 	 Vsync,
	       output reg [2:0] vgaRed,
	       output reg [2:0] vgaGreen,
	       output reg [1:0] vgaBlue,
           output wire led,
          output wire run,
          output wire dead);

      localparam [3:0] GLYPH_G = 4'd0;
      localparam [3:0] GLYPH_A = 4'd1;
      localparam [3:0] GLYPH_M = 4'd2;
      localparam [3:0] GLYPH_E = 4'd3;
      localparam [3:0] GLYPH_O = 4'd4;
      localparam [3:0] GLYPH_V = 4'd5;
      localparam [3:0] GLYPH_R = 4'd6;
      localparam [3:0] GLYPH_SPACE = 4'd7;

      function [4:0] glyph_row_5x7;
        input [3:0] glyph;
        input [2:0] row;
        begin
          case (glyph)
            GLYPH_G: begin
              case (row)
                3'd0: glyph_row_5x7 = 5'b01110;
                3'd1: glyph_row_5x7 = 5'b10001;
                3'd2: glyph_row_5x7 = 5'b10000;
                3'd3: glyph_row_5x7 = 5'b10111;
                3'd4: glyph_row_5x7 = 5'b10001;
                3'd5: glyph_row_5x7 = 5'b10001;
                default: glyph_row_5x7 = 5'b01110;
              endcase
            end
            GLYPH_A: begin
              case (row)
                3'd0: glyph_row_5x7 = 5'b01110;
                3'd1: glyph_row_5x7 = 5'b10001;
                3'd2: glyph_row_5x7 = 5'b10001;
                3'd3: glyph_row_5x7 = 5'b11111;
                3'd4: glyph_row_5x7 = 5'b10001;
                3'd5: glyph_row_5x7 = 5'b10001;
                default: glyph_row_5x7 = 5'b10001;
              endcase
            end
            GLYPH_M: begin
              case (row)
                3'd0: glyph_row_5x7 = 5'b10001;
                3'd1: glyph_row_5x7 = 5'b11011;
                3'd2: glyph_row_5x7 = 5'b10101;
                3'd3: glyph_row_5x7 = 5'b10101;
                3'd4: glyph_row_5x7 = 5'b10001;
                3'd5: glyph_row_5x7 = 5'b10001;
                default: glyph_row_5x7 = 5'b10001;
              endcase
            end
            GLYPH_E: begin
              case (row)
                3'd0: glyph_row_5x7 = 5'b11111;
                3'd1: glyph_row_5x7 = 5'b10000;
                3'd2: glyph_row_5x7 = 5'b10000;
                3'd3: glyph_row_5x7 = 5'b11110;
                3'd4: glyph_row_5x7 = 5'b10000;
                3'd5: glyph_row_5x7 = 5'b10000;
                default: glyph_row_5x7 = 5'b11111;
              endcase
            end
            GLYPH_O: begin
              case (row)
                3'd0: glyph_row_5x7 = 5'b01110;
                3'd1: glyph_row_5x7 = 5'b10001;
                3'd2: glyph_row_5x7 = 5'b10001;
                3'd3: glyph_row_5x7 = 5'b10001;
                3'd4: glyph_row_5x7 = 5'b10001;
                3'd5: glyph_row_5x7 = 5'b10001;
                default: glyph_row_5x7 = 5'b01110;
              endcase
            end
            GLYPH_V: begin
              case (row)
                3'd0: glyph_row_5x7 = 5'b10001;
                3'd1: glyph_row_5x7 = 5'b10001;
                3'd2: glyph_row_5x7 = 5'b10001;
                3'd3: glyph_row_5x7 = 5'b10001;
                3'd4: glyph_row_5x7 = 5'b10001;
                3'd5: glyph_row_5x7 = 5'b01010;
                default: glyph_row_5x7 = 5'b00100;
              endcase
            end
            GLYPH_R: begin
              case (row)
                3'd0: glyph_row_5x7 = 5'b11110;
                3'd1: glyph_row_5x7 = 5'b10001;
                3'd2: glyph_row_5x7 = 5'b10001;
                3'd3: glyph_row_5x7 = 5'b11110;
                3'd4: glyph_row_5x7 = 5'b10100;
                3'd5: glyph_row_5x7 = 5'b10010;
                default: glyph_row_5x7 = 5'b10001;
              endcase
            end
            default: glyph_row_5x7 = 5'b00000;
          endcase
        end
      endfunction

   localparam ratio = 1;
   localparam ScreenH = 9'd480;
   localparam ScreenW = 10'd640;

   wire [9:0] x;       // VGA pixel scan X      
   wire [8:0] y;       // VGA pixel scan Y
   wire [8:0] GroundY; // Horizon Y coordinate

   wire [10:0] ObsX;
   
   wire  pixel_clk;     // 25Mhz pixel scan clock rate
   wire  animateClock;  // controls the animation of dino's foot step, and bird wings
   wire  Frame_Clk;     // 60 FPS
	wire  moveClk;

   wire  rst;
   wire  jump;
   wire  duck;

   localparam dx = 5'd30;
   // Initial assignments
   assign GroundY = ScreenH - (ScreenH >> 2);   // Ground Y coordinate assignment
   // 640 - 160 = 480 --> Bottom 25 %

   wire [10:0] difficulty = 11'd500; 
   // Begin of clock divider.
   // Output: pixel_clk ==> 25MHz Clock
   // wire 			 pixel_clk;
   vgaClk _vgaClk(.clk(clk), 
                  .pix_clk(pixel_clk));
   // Now pixel_clk is a 25MHz clock, hopefully.

   // wire 			 animateClock;
   ClockDivider #(.velocity(4))   
      animateClk (.clk(clk),
                  .speed(animateClock));
   
   ClockDivider #(.velocity(50))  // Period = 0.1s
      FPSClk (.clk(clk),
                 .speed(Frame_Clk));
					  
	ClockDivider #(.velocity(500))
		MoveClk (.clk(clk),
				   .speed(moveClk));
	
   // Begin of Debouncer Module

   // wire       rst;
   Debouncer resetButton (
       .button_in(btnR),
       .clk(clk),
       .button_out(rst));

   // wire       jump;
   Debouncer jumpBtn (
       .button_in(jumpButton/* Assign button */),
       .clk(clk),
       .button_out(jump));

   // wire       duck;
   Debouncer duckBtn(
       .button_in(duckButton/* Assign button */),
       .clk(clk),
       .button_out(duck));

   // End of debouncer
   


   /* Main Game Control Unit */

   /* Game Delegate is a FSM
      00 - Initial state:
           The game is frozen, everything is at there 
           initial positon:
           Obstacles X = ScreenW + someOffset
           DinoX = defaultDinoX
           DinoY = GroundY
      01 - Gaming State:
           The game starts. Triggered by the 'initial jump'
      10 - Dead State:
           The game is frozen, dead dino and game over msg displayed.
      
      (01 - restart -)-> 00 -- Jump ----> 10 ------- Collided ---> 01 (Dead)
                                     ^          |
                                     |          |
                                     |_!Collide_|
   */ 
   reg         collided;
   wire        crash_event;
   wire        dino_on_ground;
   wire [1:0]  dino_last_jump_type;
   wire        dino_inWhite;
   wire        dino_inGrey;
   wire obstacle_inWhite;
   wire obstacle_inGrey;
   
   always @(posedge Frame_Clk or posedge rst) begin
      if (rst)
        collided <= 0;
      else
        collided <= crash_event;
   end
   assign led = collided;
   
   wire [1:0] gameState;	// wire[1] is run;
   
   GameDelegate gameFSM(
          .clk(clk),
          .rst(rst),
          .jump(jump),
          .restart(restart),
          .collided(collided),
          .state(gameState));

   // Begin of VGA module

   VGA vga(.pixel_clock(pixel_clk),
           .rst(rst),
           .Hsync(Hsync),
           .Vsync(Vsync),
           .X(x),
           .Y(y));

   // End of VGA

   wire 			 BackGround_inGrey;

   BackGroundDelegate #(.ratio(ratio), .dx(dx))
       BGD (.moveClk(moveClk),
            .rst(rst),
            .GroundY(GroundY),
            .vgaX(x),
            .vgaY(y),
            .gameState(gameState),
            .inGrey(BackGround_inGrey));

   /* Horizon movement */
		
   wire ScoreBoard_inGrey;
  localparam SCORE_TICK_FRAMES = 3'd4;
  reg [2:0] score_tick_timer;
  reg score_tick_pulse;

  always @(posedge Frame_Clk or posedge rst) begin
    if (rst) begin
      score_tick_timer <= SCORE_TICK_FRAMES;
      score_tick_pulse <= 1'b0;
    end
    else begin
      score_tick_pulse <= 1'b0;
      if (gameState == 2'b00) begin
        score_tick_timer <= SCORE_TICK_FRAMES;
      end
      else if (gameState == 2'b10) begin
        if (score_tick_timer > 0)
          score_tick_timer <= score_tick_timer - 1'b1;
        else begin
          score_tick_timer <= SCORE_TICK_FRAMES;
          score_tick_pulse <= 1'b1;
        end
      end
    end
  end

  assign score_tick_o = score_tick_pulse;

  ScoreBoardDelegate SBD(.frameClk(Frame_Clk),
                          .rst(rst),
                          .gameState(gameState),
                  .score_value(score_value_i),
                          .vgaX(x),
                          .vgaY(y),
                          .inGrey(ScoreBoard_inGrey));

      

   
   TRexDelegate #(.ratio(ratio))
      TRD (.rst(rst),
           .animationClk(animateClock),
           .FrameClk(Frame_Clk),
           .jump(jump),
           .dbl_jump(jump),
           .duck(duck),
           .gameState(gameState),
           .GroundY(GroundY),
           .vgaX(x),
           .vgaY(y),
           .inGrey(dino_inGrey),
           .inWhite(dino_inWhite),
           .onGround_o(dino_on_ground),
           .last_jump_type_o(dino_last_jump_type));



   
   ObstaclesDelegate #(.ratio(ratio), .dx(dx))
    OD (.frameClk(Frame_Clk),
          .rst(rst),
          .ObstacleY(GroundY),
          .vgaX(x),
          .vgaY(y),
          .gameState(gameState),
          .onGround(dino_on_ground),
          .lastJumpType(dino_last_jump_type),
          .inGrey(obstacle_inGrey),
          .inWhite(obstacle_inWhite),
          .crash_event(crash_event),
          .X_1(ObsX));
			 
   
   
   /* Color Select */
  wire isGrey;
   wire isWhite;
   wire isBackGround;
  wire game_over_active;
  reg game_over_text_pixel;
  reg [9:0] text_x;
  reg [8:0] text_y;
  reg [6:0] text_col;
  reg [2:0] text_row;
  reg [3:0] glyph_sel;
  reg [4:0] glyph_bits;

  localparam [9:0] GO_LEFT = 10'd24;
  localparam [8:0] GO_TOP = 9'd24;
  localparam [3:0] GO_CHAR_W = 4'd6;
  localparam [2:0] GO_CHAR_H = 3'd7;
  localparam [1:0] GO_SCALE = 2'd2;
  localparam [7:0] GO_TEXT_PIX_W = 8'd108;
  localparam [5:0] GO_TEXT_PIX_H = 6'd14;

  assign game_over_active = (gameState == 2'b01) || (gameState == 2'b11);

  always @(*) begin
    game_over_text_pixel = 1'b0;
    text_x = 10'd0;
    text_y = 9'd0;
    text_col = 7'd0;
    text_row = 3'd0;
    glyph_sel = GLYPH_SPACE;
    glyph_bits = 5'b00000;

    if (game_over_active &&
       (x >= GO_LEFT) && (x < GO_LEFT + GO_TEXT_PIX_W) &&
       (y >= GO_TOP)  && (y < GO_TOP + GO_TEXT_PIX_H)) begin
      text_x = (x - GO_LEFT) >> 1;
      text_y = (y - GO_TOP) >> 1;
      text_col = text_x[6:0];
      text_row = text_y[2:0];

      case (text_col / GO_CHAR_W)
        4'd0: glyph_sel = GLYPH_G;
        4'd1: glyph_sel = GLYPH_A;
        4'd2: glyph_sel = GLYPH_M;
        4'd3: glyph_sel = GLYPH_E;
        4'd4: glyph_sel = GLYPH_SPACE;
        4'd5: glyph_sel = GLYPH_O;
        4'd6: glyph_sel = GLYPH_V;
        4'd7: glyph_sel = GLYPH_E;
        4'd8: glyph_sel = GLYPH_R;
        default: glyph_sel = GLYPH_SPACE;
      endcase

      if ((text_col % GO_CHAR_W) < 5) begin
        glyph_bits = glyph_row_5x7(glyph_sel, text_row);
        game_over_text_pixel = glyph_bits[4 - (text_col % GO_CHAR_W)];
      end
    end
  end
   
  assign isGrey = dino_inGrey | BackGround_inGrey | ScoreBoard_inGrey | obstacle_inGrey | game_over_text_pixel;
   assign isWhite = dino_inWhite | obstacle_inWhite;
   assign isBackGround = (x > 0) && (x <= ScreenW) && (y > 0) && (y <= ScreenH) && !isGrey;

   /* Assign Values to color select wires */
   always @(posedge pixel_clk) begin
     if (isWhite) begin
       vgaRed <= 3'b111;
       vgaGreen <= 3'b111;
       vgaBlue <= 2'b11;
     end

     else if (isGrey) begin
       vgaRed <= 3'b000;
       vgaGreen <= 3'b000;
       vgaBlue <= 2'b00;
     end

     else if (isBackGround) begin
       vgaRed <= 3'b111;
       vgaGreen <= 3'b111;
       vgaBlue <= 2'b11;
       end
     else   // defualt 
     begin
       vgaRed <= 3'b000;
       vgaGreen <= 3'b000;
       vgaBlue <= 2'b00;
     end
   end
   
   

  assign run = (gameState == 2'b10);
  assign dead = (gameState == 2'b01) || (gameState == 2'b11);
endmodule // top_vga
