/* Bootloader — lives in the first 4 KB of BRAM.
 * Stack grows down from 0x1000 (just below the app region). */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    BRAM_BOOT (rwx) : ORIGIN = 0x00000000, LENGTH = 4K
}

SECTIONS
{
    . = ORIGIN(BRAM_BOOT);

    .text : {
        *(.text.start)
        *(.text*)
        *(.rodata*)
    } > BRAM_BOOT

    .data : ALIGN(4) {
        _sdata = .;
        *(.data*)
        _edata = .;
    } > BRAM_BOOT

    .bss : ALIGN(4) {
        _sbss = .;
        *(.bss*)
        *(COMMON)
        _ebss = .;
    } > BRAM_BOOT

    _stack_top = ORIGIN(BRAM_BOOT) + LENGTH(BRAM_BOOT);   /* 0x1000 */
    /DISCARD/ : {
        *(.eh_frame)
        *(.comment)
        *(.note.gnu.build-id)
        *(.riscv.attributes)
    }
}
