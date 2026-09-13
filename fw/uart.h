// Driver UART TX bare-metal (header-only, RV32I)
// MMIO: base 0x10000000, TXDATA+0x0 (W), STATUS+0x4 (R, bit0 READY)
#pragma once
#include <stdint.h>

#define UART_BASE   (0x10000000UL)
#define UART_TXDATA ((volatile uint32_t *)0x10000000UL)
#define UART_STATUS ((volatile uint32_t *)0x10000004UL)
#define UART_RXDATA ((volatile uint32_t *)0x10000008UL)
#define UART_READY  (1U) // STATUS bit0: TX livre
#define UART_RXVALID (2U) // STATUS bit1: byte recebido disponivel

static inline void uart_wait(void) {
    while (!(*UART_STATUS & UART_READY)) {
        // polling: a CPU trava aqui ate o byte anterior sair
    }
}

static inline void uart_putc(char c) {
    uart_wait();
    *UART_TXDATA = (uint32_t)(unsigned char)c;
}

// ---------- RX (teclado via UART) ----------
// 1 = tem byte esperando em RXDATA
static inline int uart_available(void) {
    return ((*UART_STATUS & UART_RXVALID) != 0);
}

// Bloqueante: espera ate chegar 1 byte (polling). Leitura consome.
static inline char uart_getc(void) {
    while (!uart_available()) {
        // polling
    }
    return (char)(*UART_RXDATA & 0xFF);
}

// Nao-bloqueante: retorna -1 se nao ha dado, senao o byte (0-255).
static inline int uart_trygetc(void) {
    if (!uart_available()) return -1;
    return (int)(*UART_RXDATA & 0xFF);
}

// Nota: puts/putdec/puthex sao noinline de proposito — como ficam em
// header, o inline agressivo do -O2 duplicaria o corpo em cada chamada
// e estouraria a IMEM de 4KB. putc/wait/getc continuam inline (baratos).
static __attribute__((noinline)) void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

static __attribute__((noinline)) void uart_puthex32(uint32_t v) {
    uart_puts("0x");
    for (int i = 7; i >= 0; --i) {
        uint32_t n = (v >> (i * 4)) & 0xF;
        uart_putc((char)(n < 10 ? '0' + n : 'A' + n - 10));
    }
}

static __attribute__((noinline)) void uart_putdec(int v) {
    char buf[12];
    int i = 0;
    int neg = 0;
    if (v < 0) {
        neg = 1;
        v = -v;
    }
    if (v == 0) {
        uart_putc('0');
        return;
    }
    while (v > 0 && i < 11) {
        buf[i++] = (char)('0' + (v % 10));
        v /= 10;
    }
    if (neg) uart_putc('-');
    while (i > 0) uart_putc(buf[--i]);
}
