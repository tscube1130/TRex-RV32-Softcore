`timescale 1ns / 1ps
module ClockDivider#(parameter velocity = 1)
    (input wire clk,
     output wire speed);
    
    reg [31:0] counter;
    reg clock;
    localparam threashold = 50000000 / velocity;
    
    initial begin
        counter <= 0;
        clock <= 0;
    end
    
    always @(posedge clk) begin
        if (counter == threashold - 1) begin
            counter <= 0;
            clock <= ~clock;
        end
        else begin
            counter <= counter + 1;
            clock <= clock;
        end
    end
    
    assign speed = clock;
endmodule
