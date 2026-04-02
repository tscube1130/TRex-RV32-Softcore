`timescale 1ns / 1ps

module top_fpga #(
	parameter IMEMSIZE = 4096,
	parameter DMEMSIZE = 4096
)(
	input  wire clk,    	// fast board clock (e.g. 100 MHz)
	input  wire reset,  	// active-low reset
  
 
output [15:0] led 
     
); 
wire [31:0] pc_out;
wire [15:0] pc_disp = pc_out[15:0]; 
wire exception;
	////////////////////////////////////////////////////////////
	// Slow clock generator (clock divider)
	////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////
// 100 MHz → 1 Hz clock divider (Nexys A7)
////////////////////////////////////////////////////////////
reg [25:0] clk_cnt;   	// enough for 50 million
reg    	slow_clk;

always @(posedge clk or negedge reset) begin
	if (!reset) begin
    	clk_cnt  <= 26'd0;
    	slow_clk <= 1'b0;
	end else begin
    	if (clk_cnt == 26'd49_999_999) begin
        	clk_cnt  <= 26'd0;
        	slow_clk <= ~slow_clk;   // toggle every 0.5 sec
    	end else begin
        	clk_cnt <= clk_cnt + 1'b1;
    	end
	end
end


	////////////////////////////////////////////////////////////
	// PIPE ↔ MEMORY WIRES
	////////////////////////////////////////////////////////////
	wire [31:0] inst_mem_read_data;
	wire    	inst_mem_is_valid;

	wire [31:0] dmem_read_data;
	wire    	dmem_write_valid;
	wire    	dmem_read_valid;

	assign inst_mem_is_valid = 1'b1;
	assign dmem_write_valid  = 1'b1;
	assign dmem_read_valid   = 1'b1;

	wire dmem_re,dmem_we;
	wire [31:0] dmem_raddr,dmem_waddr,dmem_wdata;
	wire [3:0] dmem_wstrb;
assign led = pc_disp;

////////////////////////////////////////////////////////////
// PIPELINE CPU
////////////////////////////////////////////////////////////
pipe pipe_u (
	.clk(slow_clk),
	.reset(reset),
	.stall(1'b0),// stall is always 0
	.exception(exception),
     
	.inst_mem_is_valid(inst_mem_is_valid),
	.inst_mem_read_data(inst_mem_read_data),
    .dmem_re(dmem_re),
	.dmem_raddr(dmem_raddr),
	.dmem_we           (dmem_we),
    .dmem_waddr        (dmem_waddr),
    .dmem_wdata        (dmem_wdata),
    .dmem_wstrb        (dmem_wstrb),
	.dmem_read_data_temp(dmem_read_data),
	.dmem_write_valid(dmem_write_valid),
	.dmem_read_valid(dmem_read_valid)
	,.pc_out(pc_out)

);


////////////////////////////////////////////////////////////
// INSTRUCTION MEMORY  (matches instr_mem.v)
////////////////////////////////////////////////////////////
instr_mem IMEM (
	.clk(slow_clk),
	.pc(pc_out),
	.instr(inst_mem_read_data)
);


////////////////////////////////////////////////////////////
// DATA MEMORY  (matches data_mem.v)
////////////////////////////////////////////////////////////
data_mem DMEM (
	.clk(slow_clk),

	.re(dmem_re),
	.raddr (dmem_raddr),   
    .rdata (dmem_read_data),

	.we    (dmem_we),    
    .waddr (dmem_waddr),  
    .wdata (dmem_wdata),     
    .wstrb (dmem_wstrb)
);



endmodule
