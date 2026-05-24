// audio_driver.v - Generates square wave tones for the Nexys A7
module audio_driver(
    input clk,             // 100MHz Nexys A7 Clock
    input [1:0] sound_ev,    // 01: Jump, 10: Crash, 11: Score
    output audio_out,      // Connects to AUD_PWM (Pin A11)
    output audio_en        // Connects to AUD_SD (Pin D12)
);

    reg [17:0] counter;
    reg [17:0] limit;
    reg [24:0] duration;
    reg pwm_reg;

    assign audio_out = pwm_reg;
    assign audio_en = (duration > 0); 

    always @(posedge clk) begin
        // If a new sound event is triggered and no sound is currently playing
        if (sound_ev != 2'b00 && duration == 0) begin
            case(sound_ev)
                2'b01: begin limit <= 83333; duration <= 5000000; end  // Jump (~600Hz)
                2'b10: begin limit <= 250000; duration <= 25000000; end // Crash (~200Hz)
                2'b11: begin limit <= 55555; duration <= 10000000; end  // Score (~900Hz)
                default: duration <= 0;
            endcase
        end 
        else if (duration > 0) begin
            duration <= duration - 1;
            if (counter >= limit) begin
                counter <= 0;
                pwm_reg <= ~pwm_reg;
            end else begin
                counter <= counter + 1;
            end
        end 
        else begin
            pwm_reg <= 0;
            counter <= 0;
        end
    end
endmodule