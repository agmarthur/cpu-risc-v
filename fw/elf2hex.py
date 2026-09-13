#!/usr/bin/env python3
"""Converte ELF RISC-V em program.hex (1 word LE por linha) p/ $readmemh."""
import struct
import sys

def main(elf_bin_path, hex_out_path, max_words=1024):
    with open(elf_bin_path, "rb") as f:
        data = f.read()
    # pad para multiplo de 4
    while len(data) % 4 != 0:
        data += b"\x00"
    words = len(data) // 4
    if words > max_words:
        print(f"ERRO: programa tem {words} words, IMEM so tem {max_words}",
              file=sys.stderr)
        sys.exit(1)
    # completa com NOPs (addi x0,x0,0 = 0x13) ate max? Nao: so escreve o usado.
    # O imem.v ja preenche o resto com NOP.
    with open(hex_out_path, "w") as out:
        for i in range(words):
            w, = struct.unpack_from("<I", data, i * 4)
            out.write(f"{w:08x}\n")
    print(f"OK: {words} words ({len(data)} bytes) -> {hex_out_path}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"uso: {sys.argv[0]} <fw.bin> <program.hex>", file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1], sys.argv[2])
