// Startup bare-metal RV32I - ponto de entrada _start
// - sp = 0x2000 (topo DMEM 8KB)
// - zera .bss via _bss_start/_bss_end do linker
// - chama main(), depois ecall (halt na CPU) com retorno em a0
    .section .text.init, "ax"
    .globl _start
    .option norelax
    .align 2
_start:
    li sp, 0x2000
    // zera bss: t0 = start, t1 = end
    la t0, _bss_start
    la t1, _bss_end
    beq t0, t1, call_main
clear_loop:
    sw zero, 0(t0)
    addi t0, t0, 4
    blt t0, t1, clear_loop
call_main:
    call main
    // a0 = retorno de main, preservado para o sim ler x10
    ecall
halt_loop:
    j halt_loop
