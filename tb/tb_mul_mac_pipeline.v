`timescale 1ns / 1ps

module tb_pipeline;
 
    // 1. CLOCK & RESET
    reg clk;
    reg reset; 
     
    initial begin 
        clk = 0; 
        forever #5 clk = ~clk;
    end
    
    initial begin
        $dumpfile("pipeline.vcd");
        $dumpvars(0, tb_pipeline);
        reset = 0;
       #10;
        reset = 1; 
    end
    
    // 2. MEMORY WIRES
    wire [31:0] inst_mem_read_data;
    wire        inst_mem_is_valid = 1'b1;
    
    wire [31:0] dmem_read_data;
    wire        dmem_write_valid = 1'b1;
    wire        dmem_read_valid  = 1'b1;
    
    wire        exception;
    wire [31:0] pc_out;
    
    // 3. DUT: THE CPU PIPELINE
    // Notice we only connect the ports that ACTUALLY exist in your pipe.v!
    pipe DUT (
        .clk(clk),
        .reset(reset),
        .stall(1'b0),
        .exception(exception),
        .pc_out(pc_out),
        .inst_mem_is_valid(inst_mem_is_valid),
        .inst_mem_read_data(inst_mem_read_data),
        .dmem_read_data_temp(dmem_read_data),
        .dmem_write_valid(dmem_write_valid),
        .dmem_read_valid(dmem_read_valid)
    );
    
    // 4. INSTRUCTION MEMORY  
    instr_mem IMEM (
        .clk(clk),
        .pc(pc_out),
        .instr(inst_mem_read_data)
    );
    
    // 5. DATA MEMORY 
    // We use hierarchical paths (DUT.wire_name) to reach inside the pipeline
    // and grab the memory signals that don't have external ports!
    data_mem DMEM (
        .clk(clk),
        .re(DUT.dmem_read_ready),         // Reaching inside pipe.v
        .raddr(DUT.dmem_read_address),    // Reaching inside pipe.v
        .rdata(dmem_read_data),           // Goes to dmem_read_data_temp
        .we(DUT.dmem_write_ready),        // Reaching inside pipe.v
        .waddr(DUT.dmem_write_address),   // Reaching inside pipe.v
        .wdata(DUT.dmem_write_data),      // Reaching inside pipe.v
        .wstrb(DUT.dmem_write_byte)       // Reaching inside pipe.v
    );
    
    // 6. TERMINAL OUTPUT (The Coprocessor Spy)
    always @(posedge clk) begin
        if (reset) begin
            $display("Time: %3t | PC: %h | Op1: %2d | Op2: %2d | EX Result: %2d | MAC Acc: %2d | Reg[5]: %2d", 
                     $time, 
                     pc_out, 
                     $signed(DUT.execute.alu_operand1), 
                     $signed(DUT.execute.alu_operand2), 
                     $signed(DUT.execute.final_ex_result), 
                     $signed(DUT.execute.u_math.mac_accumulator), 
                     $signed(DUT.regs[5])); 
        end
    end
    
    // 7. SIMULATION RUN TIME
    initial begin
        #250;   
        $display("==================================================");
        $display("   SIMULATION FINISHED ");
        $display("==================================================");
        $finish;
    end

endmodule

/* imem.hex
00500093 // ADDI x1, x0, 5    | Loads the number 5 into register x1
00600113 // ADDI x2, x0, 6    | Loads the number 6 into register x2
022081b3 // MUL  x3, x1, x2   | Standard Math: x3 = 5 * 6. (x3 becomes 30)
04208033 // MAC  x0, x1, x2   | Coprocessor: Acc = Acc + (5 * 6). (Acc becomes 30)
00200213 // ADDI x4, x0, 2    | Loads the number 2 into register x4
04408033 // MAC  x0, x1, x4   | Coprocessor: Acc = Acc + (5 * 2). (Acc becomes 30 + 10 = 40)
040012b3 // MVACC x5          | Coprocessor: Pulls the 40 out of the accumulator and saves it to x5
00000013 // NOP               | No operation (Pipeline flush)
00000013 // NOP               | No operation (Pipeline flush)
00000013 // NOP               | No operation (Pipeline flush) 
*/