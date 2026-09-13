// artvx-os v0 - micro-OS cooperativo p/ RV32I (single stack, sem trap)
// - Sem preempcao: tarefas cedem via PT_YIELD/PT_SLEEP (protothreads).
// - Tick = 1 rodada do scheduler (sem timer HW; v1 tera CLINT).
// - Cada PT_* deve ficar em LINHA PROPRIA (usa __LINE__ como estado).
// - ecall continua = halt/poweroff (tratado na cpu.v).
#pragma once
#include <stdint.h>

#define OS_MAX_TASKS 4

struct os_tcb {
    const char *name;
    void (*step)(os_tcb *t);
    int pc;           // estado da protothread
    uint32_t wake;    // tick p/ acordar
    int alive;
};

static os_tcb os_tasks[OS_MAX_TASKS];
static int os_ntasks = 0;
static uint32_t os_ticks = 0;

static inline int os_task_create(const char *name, void (*step)(os_tcb *)) {
    if (os_ntasks >= OS_MAX_TASKS) return -1;
    os_tcb *t = &os_tasks[os_ntasks++];
    t->name = name;
    t->step = step;
    t->pc = 0;
    t->wake = 0;
    t->alive = 1;
    return 0;
}

static inline void os_sleep(os_tcb *t, uint32_t n) {
    t->wake = os_ticks + n;
}

// Roda N rodadas: cada rodada incrementa o tick e chama tarefas prontas.
static inline void os_run(uint32_t rounds) {
    for (uint32_t r = 0; r < rounds; r++) {
        os_ticks++;
        for (int i = 0; i < os_ntasks; i++) {
            os_tcb *t = &os_tasks[i];
            if (t->alive && os_ticks >= t->wake)
                t->step(t);
        }
    }
}

#define PT_BEGIN(t) switch ((t)->pc) { case 0:
#define PT_YIELD(t) do { (t)->pc = __LINE__; return; case __LINE__:; } while (0)
#define PT_SLEEP(t, n) do { os_sleep((t), (n)); (t)->pc = __LINE__; return; case __LINE__:; } while (0)
#define PT_END(t) do { (t)->alive = 0; } while (0); }
