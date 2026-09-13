// Harness Verilator para firmware UART puro (fw/main.cpp)
// So decodifica tx_o serial (8N1) e exige halt. Sem checks de a0/MEM.
#include "Vcpu.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#include <cstdio>
#include <string>

static const int CLKS_PER_BIT = 10;

// Receptor UART serial simples: chamar 1x por ciclo com tx atual.
struct UartRx {
    int state = 0;      // 0=idle, 1=start, 2=data, 3=stop
    int cnt = 0;
    int bit = 0;
    unsigned byte = 0;
    int run(Vcpu *dut, std::string &out) {
        int tx = dut->tx_o & 1;
        switch (state) {
        case 0: // idle, espera falling
            if (tx == 0) { state = 1; cnt = CLKS_PER_BIT / 2; }
            break;
        case 1: // meio do start
            if (--cnt <= 0) {
                if (tx != 0) { state = 0; break; } // glitch
                state = 2; cnt = CLKS_PER_BIT; bit = 0; byte = 0;
            }
            break;
        case 2: // data bits
            if (--cnt <= 0) {
                cnt = CLKS_PER_BIT;
                byte |= (unsigned)(tx & 1) << bit;
                if (++bit >= 8) state = 3;
            }
            break;
        case 3: // stop
            if (--cnt <= 0) {
                state = 0;
                out.push_back((char)byte);
                printf("%c", (char)byte);
                fflush(stdout);
                return (int)byte;
            }
            break;
        }
        return -1;
    }
};

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vcpu *dut = new Vcpu;

    Verilated::traceEverOn(true);
    VerilatedVcdC *tfp = new VerilatedVcdC;
    dut->trace(tfp, 99);
    tfp->open("sim_cpp.vcd");

    vluint64_t time = 0;
    const int MAX_CYCLES = 50000;
    int fails = 0;
    std::string uart_out;
    UartRx rx;

    dut->dbg_rs = 0;
    dut->dbg_mem_addr = 0;
    dut->rx_i = 1; // sem teclado neste teste (só TX)
    dut->rst = 1;
    for (int i = 0; i < 4; i++) {
        dut->clk = 0; dut->eval(); tfp->dump(time++);
        dut->clk = 1; dut->eval(); tfp->dump(time++);
    }
    dut->rst = 0;

    printf("--- UART ---\n");
    int cycle = 0;
    while (cycle < MAX_CYCLES && !dut->halted_o) {
        dut->clk = 0; dut->eval(); tfp->dump(time++);
        dut->clk = 1; dut->eval(); tfp->dump(time++);
        rx.run(dut, uart_out);
        cycle++;
    }
    printf("\n--- FIM UART (%lu bytes) ---\n", (unsigned long)uart_out.size());
    printf("=== FIM: ciclos=%d halted=%d pc=0x%08x ===\n",
           cycle, (int)dut->halted_o, dut->pc_o);

    if (!dut->halted_o) { printf("FAIL halt\n"); fails++; }
    else printf("OK   halt por ecall\n");

    bool has_boot = uart_out.find("artvx-os v0 boot") != std::string::npos;
    bool has_down = uart_out.find("SHUTDOWN") != std::string::npos;
    if (!has_boot) { printf("FAIL UART sem 'artvx-os v0 boot'\n"); fails++; }
    else printf("OK   OS boot\n");
    if (!has_down) { printf("FAIL UART sem 'SHUTDOWN'\n"); fails++; }
    else printf("OK   OS shutdown\n");

    if (fails == 0) printf("PASS: artvx-os v0 funcional\n");
    else printf("FAIL: %d checagens falharam\n", fails);

    tfp->close();
    delete dut;
    return fails;
}
