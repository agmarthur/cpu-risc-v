// Testbench Verilog (iverilog / verilator --timing)
// Roda o programa em prog/program.hex e confere registradores
`timescale 1ns/1ps

module tb_cpu;
    reg clk = 0;
    reg rst = 1;
    reg rx_i = 1; // UART RX idle (sem teclado no tb)
    reg [4:0] dbg_rs = 0;
    reg [31:0] dbg_mem_addr = 0;
    wire [31:0] dbg_data;
    wire [31:0] dbg_mem_data;

    wire [31:0] pc, instr, alu_result, wd;
    wire halted;
    wire tx_o;

    cpu #(
        .IMEM_DEPTH(1024),
        .INIT_FILE("prog/program.hex")
    ) dut (
        .clk(clk),
        .rst(rst),
        .dbg_rs(dbg_rs),
        .dbg_mem_addr(dbg_mem_addr),
        .rx_i(rx_i),
        .tx_o(tx_o),
        .pc_o(pc),
        .instr_o(instr),
        .alu_result_o(alu_result),
        .wd_o(wd),
        .dbg_data(dbg_data),
        .dbg_mem_data(dbg_mem_data),
        .halted_o(halted)
    );

    // Log UART imediato (funcional; timing serial ver via VCD em tx_o)
    always @(posedge clk) begin
        if (!rst && dut.u_uart.wr)
            $write("%c", dut.u_uart.data_in);
    end

    always #5 clk = ~clk;

    integer cycles;
    initial begin
        $dumpfile("tb_cpu.vcd");
        $dumpvars(0, tb_cpu);
        cycles = 0;
        #12 rst = 0;
        // roda ate halt ou timeout
        while (cycles < 200 && !halted) begin
            @(posedge clk);
            cycles = cycles + 1;
            $display("ciclo=%0d pc=0x%08h instr=0x%08h", cycles, pc, instr);
        end
        #10;
        $display("=== FIM: ciclos=%0d halted=%0d pc=0x%08h ===", cycles, halted, pc);
        $display("x1 =%0d (esp 10)  x2 =%0d (esp 20)  x3 =%0d (esp 30)",
                 dut.u_regfile.regs[1], dut.u_regfile.regs[2], dut.u_regfile.regs[3]);
        $display("x4 =%0d (esp 10)  x5 =%0d (esp 0)   x6 =%0d (esp 30)",
                 dut.u_regfile.regs[4], dut.u_regfile.regs[5], dut.u_regfile.regs[6]);
        $display("x7 =%0d (esp 30)  x8 =%0d (esp 1)   x9 =%0d (esp 30)",
                 dut.u_regfile.regs[7], dut.u_regfile.regs[8], dut.u_regfile.regs[9]);
        $display("x10=%0d (esp 2)   x11=0x%08h (esp 0x38) x12=%0d (esp 42)",
                 dut.u_regfile.regs[10], dut.u_regfile.regs[11], dut.u_regfile.regs[12]);
        $display("x13=0x%08h (esp 0x12345000) x14=0x%08h (esp 0x1044)",
                 dut.u_regfile.regs[13], dut.u_regfile.regs[14]);
        $display("x15=0x%08h (esp 0x4c) x16=%0d (esp 88)",
                 dut.u_regfile.regs[15], dut.u_regfile.regs[16]);

        if (dut.u_regfile.regs[1]  == 10 &&
            dut.u_regfile.regs[2]  == 20 &&
            dut.u_regfile.regs[3]  == 30 &&
            dut.u_regfile.regs[4]  == 10 &&
            dut.u_regfile.regs[9]  == 30 &&
            dut.u_regfile.regs[10] == 2  &&
            dut.u_regfile.regs[12] == 42 &&
            dut.u_regfile.regs[16] == 88 &&
            halted) begin
            $display("PASS: CPU RV32I funcional");
        end else begin
            $display("FAIL: verifique o programa ou o datapath");
        end
        $finish;
    end
endmodule
