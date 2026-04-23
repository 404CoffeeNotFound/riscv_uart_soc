/* Linker script for MiniRV SoC: 16 KB BRAM at 0x0, stack at top. */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    BRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 16K
}

SECTIONS
{
    . = ORIGIN(BRAM);

    .text : {
        *(.text.start)     /* crt0 _start must be first */
        *(.text*)
        *(.rodata*)
    } > BRAM

    .data : ALIGN(4) {
        _sdata = .;
        *(.data*)
        _edata = .;
    } > BRAM

    .bss : ALIGN(4) {
        _sbss = .;
        *(.bss*)
        *(COMMON)
        _ebss = .;
    } > BRAM

    _stack_top = ORIGIN(BRAM) + LENGTH(BRAM);
    /DISCARD/ : {
        *(.eh_frame)
        *(.comment)
        *(.note.gnu.build-id)   /* keep _start at 0x0 (PicoRV32 PROGADDR_RESET) */
        *(.riscv.attributes)
    }
}
