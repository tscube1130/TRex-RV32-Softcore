module GameDelegate(
		    input wire clk,
		    input wire rst,
					input wire jump,
					input wire restart,
					input wire collided,
		    output reg [1:0] state); // what if we use wire ?? 

  localparam InitState = 2'b00;
  localparam InGameState = 2'b10;
  localparam DeadState = 2'b01;
  localparam ShowScoreState = 2'b11;
  localparam GAME_OVER_HOLD_FRAMES = 6'd60;

  reg [5:0] dead_hold_ctr;
  
  always @(posedge clk) begin
		if (rst) begin
			state <= InitState;
			dead_hold_ctr <= 6'd0;
		end
		else begin
			case (state)
				InitState: begin
					dead_hold_ctr <= 6'd0;
					if (jump)
						state <= InGameState;
					else
						state <= InitState;
				end

				InGameState: begin
					dead_hold_ctr <= 6'd0;
					if (collided)
						state <= DeadState;
					else
						state <= InGameState;
				end

				DeadState: begin
					if (restart)
						state <= InitState;
					else if (dead_hold_ctr >= GAME_OVER_HOLD_FRAMES)
						state <= ShowScoreState;
					else begin
						dead_hold_ctr <= dead_hold_ctr + 1'b1;
						state <= DeadState;
					end
				end

				ShowScoreState: begin
					dead_hold_ctr <= dead_hold_ctr;
					if (restart)
						state <= InitState;
					else
						state <= ShowScoreState;
				end

				default: begin
					state <= InitState;
					dead_hold_ctr <= 6'd0;
				end
			endcase
		end
  end

endmodule // gameDelegate
