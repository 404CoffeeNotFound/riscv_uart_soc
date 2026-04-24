/* Loadable app — lives in BRAM starting at 0x1000 (immediately after the
 * bootloader region).  Stack grows down from the top of BRAM (0x4000). */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    BRAM_APP (rwx) : ORIGIN = 0x00001000, LENGTH = 12K
}

SECTIONS
{
    . = ORIGIN(BRAM_APP);

    .text : {
        *(.text.start)
        *(.text*)
        *(.rodata*)
    } > BRAM_APP

    .data : ALIGN(4) {
        _sdata = .;
        *(.data*)
        _edata = .;
    } > BRAM_APP

    .bss : ALIGN(4) {
        _sbss = .;
        *(.bss*)
        *(COMMON)
        _ebss = .;
    } > BRAM_APP

    _stack_top = 0x00004000;    /* top of BRAM (16 KB) */
    /DISCARD/ : {
        *(.eh_frame)
        *(.comment)
        *(.note.gnu.build-id)
        *(.riscv.attributes)
    }
}
