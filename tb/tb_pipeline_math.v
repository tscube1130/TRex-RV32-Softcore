`timescale 1ns / 1ps

module tb_pipeline_math;

    // -------------------------------------------------------------
    // 1. Clock & Reset
    // -------------------------------------------------------------
    reg clk;
    reg reset;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;   // 100 MHz
    end

    initial begin
        reset = 0;
        #10;
        reset = 1;
    end

    // -------------------------------------------------------------
    // 2. Memory interface wires
    // -------------------------------------------------------------
    wire [31:0] inst_mem_read_data;
    wire        inst_mem_is_valid = 1'b1;

    wire [31:0] dmem_read_data;
    wire        dmem_write_valid = 1'b1;
    wire        dmem_read_valid  = 1'b1;

    // Ports from pipe (now all are outputs, except dmem_read_data_temp is input)
    wire        dmem_re;
    wire [31:0] dmem_raddr;
    wire        dmem_we;
    wire [31:0] dmem_waddr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;

    wire        exception;
    wire [31:0] pc_out;
    wire        led_reg5;   // just lower bits of regs[5]

    // -------------------------------------------------------------
    // 3. Pipeline DUT (using your modified pipe with memory ports)
    // -------------------------------------------------------------
    pipe DUT (
        .clk                (clk),
        .reset              (reset),
        .stall              (1'b0),
        .exception          (exception),
        .pc_out             (pc_out),
        .inst_mem_is_valid  (inst_mem_is_valid),
        .inst_mem_read_data (inst_mem_read_data),
        .dmem_read_data_temp(dmem_read_data),
        .dmem_re            (dmem_re),
        .dmem_raddr         (dmem_raddr),
        .dmem_we            (dmem_we),
        .dmem_waddr         (dmem_waddr),
        .dmem_wdata         (dmem_wdata),
        .dmem_wstrb         (dmem_wstrb),
        .dmem_write_valid   (dmem_write_valid),
        .dmem_read_valid    (dmem_read_valid),
        .led_reg5           (led_reg5)
    );

    // -------------------------------------------------------------
    // 4. Instruction Memory
    // -------------------------------------------------------------
    instr_mem IMEM (
        .clk  (clk),
        .pc   (pc_out),
        .instr(inst_mem_read_data)
    );

    // -------------------------------------------------------------
    // 5. Data Memory (now connected directly to DUT's memory ports)
    // -------------------------------------------------------------
    data_mem DMEM (
        .clk   (clk),
        .re    (dmem_re),
        .raddr (dmem_raddr),
        .rdata (dmem_read_data),
        .we    (dmem_we),
        .waddr (dmem_waddr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

    // -------------------------------------------------------------
    // 6. Monitor: print pipeline state every cycle
    // -------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            $display("Time %3t | PC=%h | ALU op1=%2d op2=%2d | EX res=%2d | MAC acc=%2d | reg[5]=%2d",
                     $time,
                     pc_out,
                     $signed(DUT.execute.alu_operand1),
                     $signed(DUT.execute.alu_operand2),
                     $signed(DUT.execute.final_ex_result),
                     $signed(DUT.execute.u_math.mac_accumulator),
                     $signed(DUT.regs[5]));
        end
    end

    // -------------------------------------------------------------
    // 7. Simulation control & self‑checking
    // -------------------------------------------------------------
    initial begin
        // Dump waveform
        $dumpfile("tb_pipeline_math.vcd");
        $dumpvars(0, tb_pipeline_math);

        // Wait for program to finish (adjust if needed)
        #500;

        // Check final result: register x5 should contain 40
        if (DUT.regs[5] === 32'd40) begin
            $display("\n==================================================");
            $display("                    TEST PASSED");
            $display("   Final register x5 = %0d (expected 40)", DUT.regs[5]);
            $display("==================================================\n");
        end else begin
            $display("\n==================================================");
            $display("                    TEST FAILED");
            $display("   Final register x5 = %0d (expected 40)", DUT.regs[5]);
            $display("==================================================\n");
        end

        $finish;
    end

endmodule