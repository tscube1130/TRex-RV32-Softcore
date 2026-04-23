module ScoreBoardDelegate #(parameter ratio=1)(
        input wire frameClk,
        input wire rst,
    input wire [1:0] gameState,
    input wire [13:0] score_value,
        input wire [10:0] vgaX,
        input wire [8:0] vgaY,
        output wire inGrey);

   localparam ScreenH = 9'd480;

   localparam ScreenW = 10'd640;



   wire [10:0]       Num1_x;
   wire [8:0]       Num1_y;
   wire [10:0]       Num2_x;
   wire [8:0]       Num2_y;
   wire [10:0]       Num3_x;
   wire [8:0]       Num3_y;
   wire [10:0]       Num4_x;
   wire [8:0]       Num4_y;
   
   localparam Num_W = 20;
   localparam Num_H = 21;

   wire        Num1_inGrey;
   wire        Num2_inGrey;
   wire        Num3_inGrey;
   wire        Num4_inGrey;

   /* Assign Number Position */
   localparam num_top_right_x = ScreenW - 30 - Num_W;
   localparam num_top_y = 30 + Num_H;
   localparam num_gap = 10;

   assign Num4_x = num_top_right_x;
   assign Num3_x = Num4_x - Num_W - num_gap;
   assign Num2_x = Num3_x - Num_W - num_gap;
   assign Num1_x = Num2_x - Num_W - num_gap;
   assign Num4_y = num_top_y;
   assign Num3_y = Num4_y;
   assign Num2_y = Num3_y;
   assign Num1_y = Num2_y;

   reg [3:0]       Num1_SEL;
   reg [3:0]       Num2_SEL;
   reg [3:0]       Num3_SEL;
   reg [3:0]       Num4_SEL;

   wire [13:0] score_display = score_value % 14'd10000;
   wire [3:0] score_thousands = score_display / 14'd1000;
   wire [3:0] score_hundreds = (score_display % 14'd1000) / 14'd100;
   wire [3:0] score_tens = (score_display % 14'd100) / 14'd10;
   wire [3:0] score_ones = score_display % 14'd10;

   always @(*) begin
      if (rst || (gameState == 2'b00)) begin
         Num1_SEL = 4'd0;
         Num2_SEL = 4'd0;
         Num3_SEL = 4'd0;
         Num4_SEL = 4'd0;
      end
      else begin
         Num1_SEL = score_thousands;
         Num2_SEL = score_hundreds;
         Num3_SEL = score_tens;
         Num4_SEL = score_ones;
      end
   end

   drawNumber #(.ratio(ratio))
      Num1 (.rst(rst),
            .ox(Num1_x),
            .oy(Num1_y),
            .X(vgaX),
            .Y(vgaY),
            .select(Num1_SEL),
            .inGrey(Num1_inGrey));

   drawNumber #(.ratio(ratio))
      Num2 (.rst(rst),
            .ox(Num2_x),
            .oy(Num2_y),
            .X(vgaX),
            .Y(vgaY),
            .select(Num2_SEL),
            .inGrey(Num2_inGrey));

   drawNumber #(.ratio(ratio))
      Num3 (.rst(rst),
            .ox(Num3_x),
            .oy(Num3_y),
            .X(vgaX),
            .Y(vgaY),
            .select(Num3_SEL),
            .inGrey(Num3_inGrey));

   drawNumber #(.ratio(ratio))
      Num4 (.rst(rst),
            .ox(Num4_x),
            .oy(Num4_y),
            .X(vgaX),
            .Y(vgaY),
            .select(Num4_SEL),
            .inGrey(Num4_inGrey));


    assign inGrey = Num1_inGrey | Num2_inGrey | Num3_inGrey | Num4_inGrey;

endmodule


