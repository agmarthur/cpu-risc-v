// artvx-os v0 - kernel demo: boot + 2 tarefas cooperativas + shutdown
// Tarefa A: contador alliance (acorda toda rodada).
// Tarefa B: soma vetorial ART-VX (acorda a cada 2 rodadas).
#include "uart.h"
#include "artvx.h"
#include "os.h"

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
    int32_t v; // antes do PT_BEGIN: case nao pode pular inicializacao
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

int main() {
    uart_puts("artvx-os v0 boot\n");
    os_task_create("A", task_a);
    os_task_create("B", task_b);
    uart_puts("tasks=2 run=6\n");
    os_run(6);
    uart_puts("SHUTDOWN\n");
    return 0;
}
