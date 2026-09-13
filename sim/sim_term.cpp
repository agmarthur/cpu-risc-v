// Terminal p/ ART-OS: decodifica TX (tela) e injeta RX (teclado ou script).
// Uso interativo:  ./Vcpu                  (digite; Ctrl-D sai)
// Uso com script:   ./Vcpu +script=arq.txt  (teste automatizado)
// Opcoes: +trace (gera sim_term.vcd), +max=N (timeout em ciclos).
// Saida UART vai p/ stdout; log do harness vai p/ stderr.
#include "Vcpu.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#include <csignal>
#include <cstdio>
#include <cstring>
#include <string>
#include <fcntl.h>
#include <unistd.h>
#include <termios.h>

static const int CLKS_PER_BIT = 10;
static const int IDLE_BEFORE_TX = 300; // so injeta com TX parado ha N ciclos
static const int BYTE_GAP = 50;        // pausa minima entre bytes injetados

static struct termios saved_term;
static bool term_raw = false;

static void term_restore(void) {
    if (term_raw) {
        tcsetattr(STDIN_FILENO, TCSANOW, &saved_term);
        term_raw = false;
    }
}

static void on_sig(int) {
    term_restore();
    _exit(130);
}

// Receptor TX (tela): 1 chamada por ciclo com tx atual.
struct UartRx {
    int state = 0;      // 0=idle, 1=start, 2=data, 3=stop
    int cnt = 0;
    int bit = 0;
    unsigned byte = 0;
    int idle_cnt = 1000000; // ciclos desde o ultimo byte completo
    // Retorna byte (0-255) quando completa, senao -1.
    int run(Vcpu *dut, std::string &out) {
        int tx = dut->tx_o & 1;
        idle_cnt++;
        switch (state) {
        case 0:
            if (tx == 0) { state = 1; cnt = CLKS_PER_BIT / 2; }
            break;
        case 1:
            if (--cnt <= 0) {
                if (tx != 0) { state = 0; break; }
                state = 2; cnt = CLKS_PER_BIT; bit = 0; byte = 0;
            }
            break;
        case 2:
            if (--cnt <= 0) {
                cnt = CLKS_PER_BIT;
                byte |= (unsigned)(tx & 1) << bit;
                if (++bit >= 8) state = 3;
            }
            break;
        case 3:
            if (--cnt <= 0) {
                state = 0;
                idle_cnt = 0;
                out.push_back((char)byte);
                putchar((char)byte);
                fflush(stdout);
                return (int)byte;
            }
            break;
        }
        return -1;
    }
};

// Transmissor RX (teclado): gera rx_i serial a partir de fila de bytes.
// So inicia um frame quando a tela esta quieta (evita overrun da FIFO).
struct UartTx {
    std::string fifo;
    int bit_idx = -1;   // -1=idle, 0..9 transmitindo
    int cnt = 0;
    int gap = 0;
    int val = 1;
    bool dbg = false;
    int *dbg_cyc = nullptr;
    void push(char c) { fifo.push_back(c); }
    bool busy() const { return bit_idx >= 0; }
    int step(UartRx &rx) {
        if (bit_idx < 0) {
            val = 1;
            if (!fifo.empty()) {
                if (gap > 0) {
                    gap--;
                } else if (rx.idle_cnt >= IDLE_BEFORE_TX) {
                    bit_idx = 0;
                    cnt = CLKS_PER_BIT;
                }
            }
            return val;
        }
        unsigned char b = (unsigned char)fifo[0];
        int bit;
        if (bit_idx == 0) bit = 0;                    // start
        else if (bit_idx <= 8) bit = (b >> (bit_idx - 1)) & 1;
        else bit = 1;                                 // stop
        val = bit;
        if (--cnt <= 0) {
            cnt = CLKS_PER_BIT;
                if (++bit_idx > 9) {
                    bit_idx = -1;
                    if (dbg) fprintf(stderr, "[inj cyc=%d char=%02x '%c']\n",
                                     *dbg_cyc, fifo[0] & 0xFF,
                                     (fifo[0] >= 32 && fifo[0] < 127) ? fifo[0] : '.');
                    fifo.erase(0, 1);
                    gap = BYTE_GAP;
                }
        }
        return val;
    }
};

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);

    const char *script = nullptr;
    bool trace = false;
    bool debug = false;
    int max_cycles = 500000;
    for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], "+script=", 8) == 0) script = argv[i] + 8;
        else if (strcmp(argv[i], "+trace") == 0) trace = true;
        else if (strcmp(argv[i], "+debug") == 0) debug = true;
        else if (strncmp(argv[i], "+max=", 5) == 0) max_cycles = atoi(argv[i] + 5);
    }

    // Script: carrega bytes de uma vez (converte \r\n -> \n).
    std::string keys;
    if (script) {
        FILE *f = fopen(script, "rb");
        if (!f) { fprintf(stderr, "ERRO: nao abriu %s\n", script); return 2; }
        int ch, prev = 0;
        while ((ch = fgetc(f)) != EOF) {
            if (ch == '\n' && prev == '\r') { keys.back() = '\n'; }
            else keys.push_back((char)ch);
            prev = ch;
        }
        fclose(f);
        fprintf(stderr, "[artos-term] script %s (%lu bytes)\n",
                script, (unsigned long)keys.size());
    }

    // Stdin nao-bloqueante; modo raw (sem eco local) se for terminal.
    bool interactive = (script == nullptr);
    if (interactive) {
        int fl = fcntl(STDIN_FILENO, F_GETFL, 0);
        fcntl(STDIN_FILENO, F_SETFL, fl | O_NONBLOCK);
        if (isatty(STDIN_FILENO)) {
            struct termios raw;
            tcgetattr(STDIN_FILENO, &saved_term);
            raw = saved_term;
            raw.c_lflag &= (unsigned)~(ICANON | ECHO | ISIG);
            raw.c_iflag &= (unsigned)~(ICRNL | IXON);
            raw.c_cc[VMIN] = 0;
            raw.c_cc[VTIME] = 0;
            tcsetattr(STDIN_FILENO, TCSANOW, &raw);
            term_raw = true;
            signal(SIGINT, on_sig);
            signal(SIGTERM, on_sig);
            fprintf(stderr, "[artos-term] interativo (Ctrl-D sai)\n");
        }
    }

    Vcpu *dut = new Vcpu;

    VerilatedVcdC *tfp = nullptr;
    if (trace) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        dut->trace(tfp, 99);
        tfp->open("sim_term.vcd");
    }

    vluint64_t time = 0;
    dut->dbg_rs = 0;
    dut->dbg_mem_addr = 0;
    dut->rx_i = 1;
    dut->rst = 1;
    for (int i = 0; i < 4; i++) {
        dut->clk = 0; dut->eval(); if (tfp) tfp->dump(time++);
        dut->clk = 1; dut->eval(); if (tfp) tfp->dump(time++);
    }
    dut->rst = 0;

    UartRx rx;
    UartTx tx;
    std::string uart_out;
    for (char c : keys) tx.push(c);

    int cycle = 0;
    bool quit_key = false;
    tx.dbg = debug;
    tx.dbg_cyc = &cycle;
    while (cycle < max_cycles && !dut->halted_o && !quit_key) {
        // Teclado: drena stdin p/ a fila (raw: Enter vem como \r).
        if (interactive) {
            char buf[64];
            ssize_t n = read(STDIN_FILENO, buf, sizeof(buf));
            for (ssize_t i = 0; i < n; i++) {
                char c = buf[i];
                if (term_raw && c == '\r') c = '\n';
                if (term_raw && c == 0x04) { quit_key = true; break; } // Ctrl-D
                tx.push(c);
            }
        } else if (tx.fifo.empty() && !tx.busy()) {
            // Script esgotado: nada mais a injetar, so esperar halt.
        }
        dut->rx_i = tx.step(rx) & 1;
        dut->clk = 0; dut->eval(); if (tfp) tfp->dump(time++);
        dut->clk = 1; dut->eval(); if (tfp) tfp->dump(time++);
        rx.run(dut, uart_out);
        cycle++;
    }

    term_restore();
    fprintf(stderr, "\n[artos-term] ciclos=%d halted=%d pc=0x%08x bytes_rx=%lu\n",
            cycle, (int)dut->halted_o, dut->pc_o, (unsigned long)uart_out.size());
    if (tfp) tfp->close();
    delete dut;

    if (quit_key) { fprintf(stderr, "[artos-term] saida (Ctrl-D)\n"); return 0; }
    if (!dut->halted_o) { fprintf(stderr, "[artos-term] TIMEOUT sem halt\n"); return 1; }
    fprintf(stderr, "[artos-term] halt por ecall\n");
    return 0;
}
