// Harness C++ para Verilator (--cc --exe --build --trace)
#include "Vcpu.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#include <cstdio>

static unsigned read_reg(Vcpu *dut, int idx) {
    dut->dbg_rs = idx & 0x1F;
    dut->eval();
    return dut->dbg_data;
}

static int check_reg(Vcpu *dut, int idx, unsigned exp, const char *name) {
    unsigned got = read_reg(dut, idx);
    if (got != exp) {
        printf("FAIL %s x%d = %u (0x%08x), esperado %u (0x%08x)\n",
               name, idx, got, got, exp, exp);
        return 1;
    }
    printf("OK   %s x%d = %u (0x%08x)\n", name, idx, got, got);
    return 0;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vcpu *dut = new Vcpu;

    Verilated::traceEverOn(true);
    VerilatedVcdC *tfp = new VerilatedVcdC;
    dut->trace(tfp, 99);
    tfp->open("sim.vcd");

    vluint64_t time = 0;
    const int MAX_CYCLES = 200;
    int fails = 0;

    dut->dbg_rs = 0;
    dut->dbg_mem_addr = 0;
    dut->rx_i = 1; // UART RX idle
    // reset por 2 ciclos
    dut->rst = 1;
    for (int i = 0; i < 4; i++) {
        dut->clk = 0; dut->eval(); tfp->dump(time++);
        dut->clk = 1; dut->eval(); tfp->dump(time++);
    }
    dut->rst = 0;

    int cycle = 0;
    while (cycle < MAX_CYCLES && !dut->halted_o) {
        dut->clk = 0; dut->eval(); tfp->dump(time++);
        dut->clk = 1; dut->eval(); tfp->dump(time++);
        cycle++;
        printf("ciclo=%d pc=0x%08x instr=0x%08x alu=0x%08x\n",
               cycle, dut->pc_o, dut->instr_o, dut->alu_result_o);
    }

    printf("=== FIM: ciclos=%d halted=%d pc=0x%08x ===\n",
           cycle, (int)dut->halted_o, dut->pc_o);

    fails += check_reg(dut, 1, 10, "addi");
    fails += check_reg(dut, 2, 20, "addi");
    fails += check_reg(dut, 3, 30, "add");
    fails += check_reg(dut, 4, 10, "sub");
    fails += check_reg(dut, 5, 0, "and");
    fails += check_reg(dut, 6, 30, "or");
    fails += check_reg(dut, 7, 30, "xor");
    fails += check_reg(dut, 8, 1, "slt");
    fails += check_reg(dut, 9, 30, "lw");
    fails += check_reg(dut, 10, 2, "beq-skip");
    fails += check_reg(dut, 11, 0x38, "jal-link");
    fails += check_reg(dut, 12, 42, "jal-skip");
    fails += check_reg(dut, 13, 0x12345000u, "lui");
    fails += check_reg(dut, 14, 0x1044, "auipc");
    fails += check_reg(dut, 15, 0x4c, "jalr-link");
    fails += check_reg(dut, 16, 88, "jalr-skip");

    if (!dut->halted_o) {
        printf("FAIL halted_o=0, esperado 1 (ecall)\n");
        fails++;
    } else {
        printf("OK   halt por ecall\n");
    }

    if (fails == 0) printf("PASS: CPU RV32I funcional\n");
    else printf("FAIL: %d checagens falharam\n", fails);

    tfp->close();
    delete dut;
    return fails;
}
