//////////////// Including Stages ////////////////////////////
`include "IF_ID.v"
`include "execute.v"
`include "wb.v"

 module pipe
#(
	parameter [31:0]         	RESET = 32'h0000_0000
)
(
	input               	clk,
	input                 	reset,
	input               	stall,
	output          	exception,
	output [31:0] pc_out,
	// interface of instruction Memory
	input               	inst_mem_is_valid,
	input       	[31: 0] inst_mem_read_data,

	output dmem_re,
	output[31:0] dmem_raddr,
	input       	[31: 0] dmem_read_data_temp,
	output        dmem_we,
    output [31:0] dmem_waddr,
    output [31:0] dmem_wdata,
    output [ 3:0] dmem_wstrb,
	input               	dmem_write_valid,
	input               	dmem_read_valid,
	output [15:0] led_reg5
);
	reg       	[31: 0] regs [31: 1];
    assign led_reg5 = regs[5][15:0];

	//Declaring Wires and Registers

	//Data Memory Wires

	wire      	[31: 0] dmem_read_data;
	wire              	dmem_write_ready;
	wire              	dmem_read_ready;
	wire      	[31: 0] dmem_write_address;
	wire      	[31: 0] dmem_read_address;
	wire        	[1:0]  dmem_read_offset;
	wire      	[31: 0] dmem_write_data;
	wire      	[ 3: 0] dmem_write_byte;
	wire              	inst_mem_is_ready;
	wire              	dmem_read_valid_checker;

	//Instruction Fetch/Decode Stage

	reg       	[31: 0] immediate;
	wire               	immediate_sel;
	wire       	[ 4: 0] src1_select;
	wire       	[ 4: 0] src2_select;
	wire       	[ 4: 0] dest_reg_sel;
	wire       	[ 2: 0] alu_operation;
	wire               	arithsubtype;
	wire               	mem_write;
	wire               	mem_to_reg;
	wire               	illegal_inst;
	wire       	[31: 0] execute_immediate;
	wire               	alu;
	wire               	lui;
	wire               	jal;
	wire               	jalr;
	wire               	branch;
	reg               	stall_read;
	wire        is_m_ext_w;
    wire        is_mac_w;
    wire        is_mvacc_w;
	wire      	[31: 0] instruction;
	wire      	[31: 0] reg_rdata2;
	wire      	[31: 0] reg_rdata1;

	// PC

	wire        	[31: 0] pc;
	wire        	[31: 0] inst_fetch_pc;
	reg        	[31: 0] fetch_pc;

	//Stalls

	wire 	wb_stall_first;
	wire 	wb_stall_second;
	wire	wb_stall;

	//Execute Stage
	wire         	[31: 0] next_pc;
	wire        	[31: 0] write_address;
	wire                 	branch_taken;
	wire                	branch_stall;
	wire        	[31:0] alu_operand1;
	wire        	[31:0] alu_operand2;

	// Write Back

	wire                	wb_alu_to_reg;
	wire        	[31: 0] wb_result;
	wire        	[ 2: 0] wb_alu_operation;
	wire                	wb_mem_write;
	wire                	wb_mem_to_reg;
	wire        	[ 4: 0] wb_dest_reg_sel;
	wire                	wb_branch;
	wire                	wb_branch_nxt;
	wire        	[31: 0] wb_write_address;
	wire        	[ 1: 0] wb_read_address;
	wire        	[ 3: 0] wb_write_byte;
	wire        	[31: 0] wb_write_data;
	wire        	[31: 0] wb_read_data;
	wire       	[31: 0] inst_mem_address;

    // ============================================================
    // DIV STALL — pipeline freeze logic
    //
    // stall_read  : registered external stall (existing, unchanged)
    // div_stall_w : synchronous signal from math_coproc FSM (HIGH during iteration)
    //
    // pipeline_freeze = stall_read | div_stall_w
    //   → replaces bare stall_read everywhere the pipeline must freeze.
    //   → stall_read still gates external stall (boot bubble, etc.)
    //   → div_stall_w is already synchronous (FSM output) — no loop risk.
    //
    // What pipeline_freeze gates:
    //   1. fetch_pc advance
    //   2. id_ex_reg update  (instruction in decode stays put)
    //   3. execute's stall_read → ex_mem_wb_reg (result not captured until done)
    //   4. wb's stall_read_i  → inst_fetch_pc not advanced
    //   5. register file write
    // ============================================================
    wire        div_stall_w;     // from execute.div_stall
    wire        pipeline_freeze = stall_read | div_stall_w;

//------------------------------------------------------//
assign dmem_write_address       	= wb_write_address;
assign dmem_read_address        	= write_address;
assign dmem_read_offset = write_address[1:0];
assign dmem_read_ready          	= mem_to_reg;
assign dmem_write_ready         	= wb_mem_write;
assign dmem_write_data          	= wb_write_data;
assign dmem_write_byte          	= wb_write_byte;
assign dmem_read_data           	= dmem_read_data_temp;
assign dmem_read_valid_checker  	= 1'b1;
assign dmem_re    = dmem_read_ready;
assign dmem_raddr = dmem_read_address;
assign dmem_we    = dmem_write_ready;
assign dmem_waddr = dmem_write_address;
assign dmem_wdata = dmem_write_data;
assign dmem_wstrb = dmem_write_byte;
// -----------------------------------------------------//

// instantiating Instruction fetch module -----------------------
IF_ID IF_ID_stage (
	.clk            	(clk),
	.reset          	(reset),
	.stall          	(stall),
	.exception      	(exception),

	// Instruction memory interface
	.inst_mem_is_valid  (inst_mem_is_valid),
	.inst_mem_read_data (inst_mem_read_data),

	// [FREEZE] Use pipeline_freeze so a running DIV also freezes the ID stage
	.stall_read_i   	(pipeline_freeze),   // ← was stall_read
	.inst_fetch_pc  	(inst_fetch_pc),
	.instruction_i  	(instruction),

	// WB-stage signals
	.wb_stall       	(wb_stall),
	.wb_alu_to_reg  	(wb_alu_to_reg),
	.wb_mem_to_reg  	(wb_mem_to_reg),
	.wb_dest_reg_sel	(wb_dest_reg_sel),
	.wb_result      	(wb_result),
	.wb_read_data   	(wb_read_data),

	// Instruction memory address offset
	.inst_mem_offset	(inst_mem_address[1:0]),

	// Output wires
	.execute_immediate_w (execute_immediate),
	.immediate_sel_w	(immediate_sel),
	.alu_w          	(alu),
	.lui_w          	(lui),
	.jal_w          	(jal),
	.jalr_w         	(jalr),
	.branch_w       	(branch),
	.mem_write_w    	(mem_write),
	.mem_to_reg_w   	(mem_to_reg),
	.arithsubtype_w 	(arithsubtype),
	.pc_w           	(pc),
	.src1_select_w  	(src1_select),
	.src2_select_w  	(src2_select),
	.dest_reg_sel_w 	(dest_reg_sel),
	.alu_operation_w	(alu_operation),
	.illegal_inst_w 	(illegal_inst),
	.instruction_o  	(instruction),
	.is_m_ext_w     (is_m_ext_w),
    .is_mac_w       (is_mac_w),
    .is_mvacc_w     (is_mvacc_w)
);


////////////////////////////////////////////////////////////
// Register File Forwarding
////////////////////////////////////////////////////////////

assign reg_rdata1 =
	(src1_select == 5'd0) ? 0 :
	(!wb_stall && wb_alu_to_reg && (wb_dest_reg_sel == src1_select))
    	? (wb_mem_to_reg ? wb_read_data : wb_result)
    	: regs[src1_select];

assign reg_rdata2 = (src2_select == 5'd0) ? 0 :
	(!wb_stall && wb_alu_to_reg && (wb_dest_reg_sel == src2_select))
    	? (wb_mem_to_reg ? wb_read_data : wb_result)
    	: regs[src2_select];

////////////////////////////////////////////////////////////
// Register File Writeback
////////////////////////////////////////////////////////////

integer i;
always @(posedge clk or negedge reset) begin
	if (!reset) begin
    	for (i = 1; i < 32; i = i + 1)
        	regs[i] <= 32'b0;
	end
	// [FREEZE] Block regfile write during div stall too
	else if (wb_alu_to_reg && !pipeline_freeze && !wb_stall) begin  // ← was !stall_read
    	regs[wb_dest_reg_sel] <=
        	wb_mem_to_reg ? wb_read_data : wb_result;
	end
end


////////////////////////////////////////////////////////////
// Stall register
// (external stall only — div_stall added separately in pipeline_freeze)
////////////////////////////////////////////////////////////

always @(posedge clk or negedge reset) begin
	if (!reset)
	    // Boot bubble: hold stall_read=1 for one cycle after reset so the
        // pipeline registers latch NOP while instruction memory initialises.
    	stall_read <= 1'b1;
	else
    	stall_read <= stall;
end


// instantiating execute module -----------------------------------
execute execute (
	.clk          	(clk),
	.reset        	(reset),

    .reg_rdata1        (reg_rdata1),
    .reg_rdata2        (reg_rdata2),
    .execute_imm       (execute_immediate),
    .pc                (pc),
    .fetch_pc          (fetch_pc),

    .immediate_sel     (immediate_sel),
    .mem_write         (mem_write),
    .jal               (jal),
    .jalr              (jalr),
    .lui               (lui),
    .alu               (alu),
    .branch            (branch),
    .arithsubtype      (arithsubtype),
    .mem_to_reg        (mem_to_reg),
    // [FREEZE] Pass pipeline_freeze so ex_mem_wb_reg also freezes during DIV
    .stall_read        (pipeline_freeze),    // ← was stall_read

    .dest_reg_sel      (dest_reg_sel),
    .alu_op            (alu_operation),
    .dmem_raddr        (write_address[1:0]),

	.is_m_ext       (is_m_ext_w),
    .is_mac         (is_mac_w),
    .is_mvacc       (is_mvacc_w),

	.wb_branch_i  	(wb_branch),
	.wb_branch_nxt_i  (wb_branch_nxt),

	.alu_operand1 	(alu_operand1),
	.alu_operand2 	(alu_operand2),
	.write_address	(write_address),
	.branch_stall 	(branch_stall),
	.next_pc      	(next_pc),
	.branch_taken 	(branch_taken),
    // [NEW] Collect div stall from execute
    .div_stall      (div_stall_w),           // ← new port

	.wb_result         (wb_result),
    .wb_mem_write      (wb_mem_write),
    .wb_alu_to_reg     (wb_alu_to_reg),
    .wb_dest_reg_sel   (wb_dest_reg_sel),
    .wb_branch         (wb_branch),
    .wb_branch_nxt     (wb_branch_nxt),
    .wb_mem_to_reg     (wb_mem_to_reg),
    .wb_read_address   (wb_read_address),
    .mem_alu_operation (wb_alu_operation)
);



////////////////////////////////////////////////////////////
// PC Update Logic
////////////////////////////////////////////////////////////

always @(posedge clk or negedge reset) begin
	if (!reset)
    	fetch_pc <= RESET;
	// [FREEZE] Don't advance PC during DIV stall
	else if (!pipeline_freeze)                           // ← was !stall_read
    	fetch_pc <= branch_stall ? fetch_pc + 4 : next_pc;
end


// instantiating Writeback module ----------------------------------
wb wb_stage (
   .clk(clk),
   .reset(reset),
   // [FREEZE] Freeze wb's inst_fetch_pc during DIV stall
   .stall_read_i       (pipeline_freeze),               // ← was stall_read
   .fetch_pc_i         (fetch_pc),
   .wb_branch_i        (wb_branch),
   .wb_mem_to_reg_i    (wb_mem_to_reg),
   .mem_write_i        (mem_write && !branch_stall),
   .write_address_i    (write_address),
   .alu_operand2_i     (alu_operand2),
   .alu_operation_i    (alu_operation),
   .wb_alu_operation_i (wb_alu_operation),
   .wb_read_address_i  (wb_read_address),
   .dmem_read_data_i   (dmem_read_data),
   .dmem_write_valid_i (dmem_write_valid),
   .inst_mem_address_o (inst_mem_address),
   .inst_mem_is_ready_o(inst_mem_is_ready),
   .wb_stall_o         (wb_stall),
   .wb_write_address_o (wb_write_address),
   .wb_write_data_o    (wb_write_data),
   .wb_write_byte_o    (wb_write_byte),
   .wb_read_data_o     (wb_read_data),
   .inst_fetch_pc_o    (inst_fetch_pc),
   .wb_stall_first_o   (wb_stall_first),
   .wb_stall_second_o  (wb_stall_second)
);

assign pc_out = fetch_pc;

endmodule
