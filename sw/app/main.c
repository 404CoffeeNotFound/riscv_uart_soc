/* App — loaded by the bootloader into BRAM starting at 0x0000_1000.
 * Just emits a signature string so the testbench can confirm the whole
 * boot-load-jump chain worked. */
#include <stdint.h>

#define UART_BASE    0x10000000u
#define REG(o)       (*(volatile uint32_t *)(UART_BASE + (o)))
#define UART_DATA    REG(0x00)
#define UART_STATUS  REG(0x04)
#define S_TX_FULL    (1u << 1)

static void put(char c) {
    while (UART_STATUS & S_TX_FULL) { /* spin */ }
    UART_DATA = (uint32_t)(unsigned char)c;
}
static void puts_(const char *s) {
    while (*s) put(*s++);
}

int main(void) {
    puts_("APP_OK\n");
    for (;;) { /* halt */ }
    return 0;
}
