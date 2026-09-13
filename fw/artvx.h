// ART-VX custom SIMD 2x16 - intrinsics C++ (RV32I + opcode custom-0)
// Cada int32 carrega 2x int16: pack16(hi, lo) = {hi[15:0], lo[15:0]}.
// Instrucoes (R-type, opcode 0x0B, funct7=1):
//   artvx.add funct3=0, artvx.sub funct3=1, artvx.mul funct3=2
// Usa `.insn` para o montador aceitar o opcode custom sem patch no GCC.
#pragma once
#include <stdint.h>

static inline int32_t artvx_add(int32_t a, int32_t b) {
    int32_t r;
    __asm__ volatile (".insn r 0x0B, 0, 1, %0, %1, %2"
                      : "=r"(r) : "r"(a), "r"(b));
    return r;
}

static inline int32_t artvx_sub(int32_t a, int32_t b) {
    int32_t r;
    __asm__ volatile (".insn r 0x0B, 1, 1, %0, %1, %2"
                      : "=r"(r) : "r"(a), "r"(b));
    return r;
}

static inline int32_t artvx_mul(int32_t a, int32_t b) {
    int32_t r;
    __asm__ volatile (".insn r 0x0B, 2, 1, %0, %1, %2"
                      : "=r"(r) : "r"(a), "r"(b));
    return r;
}

// Empacota 2x16 (com wrap) e extrai com sinal
static inline int32_t artvx_pack16(int hi, int lo) {
    return (int32_t)(((uint32_t)(hi & 0xFFFF) << 16) | (uint32_t)(lo & 0xFFFF));
}
static inline int artvx_hi(int32_t v) { return (int16_t)(v >> 16); }
static inline int artvx_lo(int32_t v) { return (int16_t)(v & 0xFFFF); }
