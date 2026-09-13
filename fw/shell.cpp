// ART-OS v1 - sistema operacional com terminal interativo
// CPU RV32I + ART-VX, UART full-duplex 8N1 (bare-metal, sem libc).
// Boot mostra banner do art; shell com prompt "art> ".
// Comandos: help whoami ver echo clear uptime add vec ps demo reboot shutdown
#include "uart.h"
#include "artvx.h"
#include "os.h"

extern "C" void _start(void);

// ---------- utilidades (sem libc) ----------
static int str_eq(const char *a, const char *b) {
    while (*a && *a == *b) {
        a++;
        b++;
    }
    return *a == *b;
}

// Inteiro decimal com sinal. ok=1 se valido.
static int parse_int(const char *s, int *ok) {
    int neg = 0;
    int v = 0;
    int digits = 0;
    *ok = 0;
    if (*s == '-') {
        neg = 1;
        s++;
    } else if (*s == '+') {
        s++;
    }
    while (*s >= '0' && *s <= '9') {
        v = v * 10 + (*s - '0');
        s++;
        digits++;
    }
    if (digits == 0 || *s != '\0') return 0;
    *ok = 1;
    return neg ? -v : v;
}

// Divide linha em argv (max 8). Retorna argc. Modifica a linha.
static int split(char *line, char *argv[], int maxargs) {
    int argc = 0;
    char *p = line;
    while (*p && argc < maxargs) {
        while (*p == ' ' || *p == '\t') p++;
        if (!*p) break;
        argv[argc++] = p;
        while (*p && *p != ' ' && *p != '\t') p++;
        if (*p) *p++ = '\0';
    }
    return argc;
}

// Le 1 linha com eco local, backspace e limite. Retorna tamanho.
static int read_line(char *buf, int max) {
    int n = 0;
    while (1) {
        char c = uart_getc();
        if (c == '\r') c = '\n';
        if (c == '\n') {
            uart_puts("\n");
            buf[n] = '\0';
            return n;
        }
        if (c == '\b' || c == 127) { // backspace / DEL
            if (n > 0) {
                n--;
                uart_puts("\b \b");
            }
            continue;
        }
        if (c >= 32 && c < 127) {
            if (n < max - 1) {
                buf[n++] = c;
                uart_putc(c);
            }
        }
    }
}

// ---------- tarefas demo (artvx-os cooperativo) ----------
static void task_a(os_tcb *t) {
    PT_BEGIN(t);
    while (1) {
        uart_puts("A tick=");
        uart_putdec((int)os_ticks);
        uart_puts("\n");
        PT_SLEEP(t, 1);
    }
    PT_END(t);
}

static void task_b(os_tcb *t) {
    int32_t v;
    PT_BEGIN(t);
    while (1) {
        v = artvx_add(artvx_pack16(1000, 2000), artvx_pack16(3000, 4000));
        uart_puts("B vec=");
        uart_putdec(artvx_hi(v));
        uart_puts(",");
        uart_putdec(artvx_lo(v));
        uart_puts("\n");
        PT_SLEEP(t, 2);
    }
    PT_END(t);
}

// ---------- comandos ----------
static uint32_t n_cmd = 0;

static void cmd_help(void) {
    uart_puts("comandos:\n");
    uart_puts("  help: ajuda\n");
    uart_puts("  whoami: dono\n");
    uart_puts("  ver: versao\n");
    uart_puts("  echo <txt>: repete\n");
    uart_puts("  clear: limpa tela\n");
    uart_puts("  uptime: ticks/cmds\n");
    uart_puts("  add <a> <b>: soma\n");
    uart_puts("  vec: demo ART-VX\n");
    uart_puts("  ps: tarefas\n");
    uart_puts("  demo: 2 tarefas x6\n");
    uart_puts("  reboot: reinicia\n");
    uart_puts("  shutdown: desliga\n");
}

static void cmd_vec(void) {
    int32_t a = artvx_pack16(1000, 2000);
    int32_t b = artvx_pack16(3000, 4000);
    int32_t s = artvx_add(a, b);
    int32_t d = artvx_sub(a, b);
    int32_t m = artvx_mul(a, b);
    uart_puts("a={1000,2000} b={3000,4000}\n");
    uart_puts("add=");
    uart_putdec(artvx_hi(s));
    uart_puts(",");
    uart_putdec(artvx_lo(s));
    uart_puts(" sub=");
    uart_putdec(artvx_hi(d));
    uart_puts(",");
    uart_putdec(artvx_lo(d));
    uart_puts(" mul=");
    uart_putdec(artvx_hi(m));
    uart_puts(",");
    uart_putdec(artvx_lo(m));
    uart_puts("\n");
}

static void cmd_ps(void) {
    uart_puts("nome vivo wake\n");
    for (int i = 0; i < os_ntasks; i++) {
        uart_puts(os_tasks[i].name);
        uart_puts("    ");
        uart_putdec(os_tasks[i].alive);
        uart_puts("    ");
        uart_putdec((int)os_tasks[i].wake);
        uart_puts("\n");
    }
}

static void cmd_demo(void) {
    uart_puts("demo: 2 tarefas, 6 rodadas\n");
    os_run(6);
    uart_puts("demo fim\n");
}

static void exec(char *line) {
    char *argv[8];
    int argc = split(line, argv, 8);
    if (argc == 0) return;
    n_cmd++;

    if (str_eq(argv[0], "help")) {
        cmd_help();
    } else if (str_eq(argv[0], "whoami")) {
        uart_puts("art\n");
    } else if (str_eq(argv[0], "ver")) {
        uart_puts("ART-OS v1.0 | RV32I + ART-VX | UART 8N1\n");
    } else if (str_eq(argv[0], "echo")) {
        for (int i = 1; i < argc; i++) {
            if (i > 1) uart_putc(' ');
            uart_puts(argv[i]);
        }
        uart_puts("\n");
    } else if (str_eq(argv[0], "clear")) {
        for (int i = 0; i < 24; i++) uart_putc('\n');
    } else if (str_eq(argv[0], "uptime")) {
        uart_puts("ticks=");
        uart_putdec((int)os_ticks);
        uart_puts(" cmds=");
        uart_putdec((int)n_cmd);
        uart_puts("\n");
    } else if (str_eq(argv[0], "add")) {
        if (argc < 3) {
            uart_puts("uso: add <a> <b>\n");
        } else {
            int ok1, ok2;
            int a = parse_int(argv[1], &ok1);
            int b = parse_int(argv[2], &ok2);
            if (!ok1 || !ok2) {
                uart_puts("numero invalido\n");
            } else {
                uart_putdec(a + b);
                uart_puts("\n");
            }
        }
    } else if (str_eq(argv[0], "vec")) {
        cmd_vec();
    } else if (str_eq(argv[0], "ps")) {
        cmd_ps();
    } else if (str_eq(argv[0], "demo")) {
        cmd_demo();
    } else if (str_eq(argv[0], "reboot")) {
        uart_puts("reiniciando...\n");
        _start(); // nunca retorna (sp e bss resetados)
        while (1) {
        }
    } else if (str_eq(argv[0], "shutdown") || str_eq(argv[0], "exit") ||
               str_eq(argv[0], "poweroff") || str_eq(argv[0], "halt")) {
        uart_puts("desligando... ate logo, art!\n");
        __asm__ volatile("ecall");
        while (1) {
        }
    } else {
        uart_puts("comando desconhecido: ");
        uart_puts(argv[0]);
        uart_puts(" (digite help)\n");
    }
}

int main() {
    static char line[96];

    uart_puts("\n================================\n");
    uart_puts("  ART-OS v1.0 - terminal do art\n");
    uart_puts("  RV32I + ART-VX bare-metal\n");
    uart_puts("================================\n");
    uart_puts("'help' lista comandos.\n");

    os_task_create("A", task_a);
    os_task_create("B", task_b);

    while (1) {
        uart_puts("art> ");
        read_line(line, sizeof(line));
        os_ticks++; // cada comando = 1 tick
        exec(line);
    }
    return 0;
}
