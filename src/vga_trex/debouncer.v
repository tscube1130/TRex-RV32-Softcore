`timescale 1ns / 1ps
module Debouncer(
		 input 	button_in,
		 input 	clk,
		 output reg button_out);
   
   reg 			sync_0;
   reg 			sync_1;
   reg [15:0] 		tmpCounter;

   always @(posedge clk) sync_0 <= button_in;
   always @(posedge clk) sync_1 <= sync_0;

   always @(posedge clk) begin
      if (sync_1 == button_out)
	tmpCounter <= 16'b0;

      else begin
	 tmpCounter <= tmpCounter + 1;
	 if (tmpCounter == 16'hffff)
	   button_out <= ~button_out;
      end

   end // always @ (posedge clk)

endmodule
