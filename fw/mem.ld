/* Linker script bare-metal RV32I - Harvard 8KB DMEM (compat von-Neumann 0x0) */
OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
    . = 0x0;

    .text.init : {
        *(.text.init)
    }

    .text : {
        *(.text*)
    }

    .rodata : {
        *(.rodata*)
        . = ALIGN(4);
    }

    .data : {
        . = ALIGN(4);
        *(.data*)
        *(.sdata*)
    }

    _bss_start = .;
    .bss : {
        . = ALIGN(4);
        *(.bss*)
        *(COMMON)
        *(.sbss*)
    }
    _bss_end = .;
    _end = .;

    /* Stack no topo da DMEM 8KB */
    _stack_top = 0x2000;

    /DISCARD/ : {
        *(.eh_frame*)
        *(.comment*)
        *(.riscv.attributes*)
    }
}
