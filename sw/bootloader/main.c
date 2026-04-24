/* UART bootloader for MiniRV SoC.
 *
 * Flash layout:
 *   0x0000_0000 - 0x0000_0FFF : bootloader (this program)   —  4 KB
 *   0x0000_1000 - 0x0000_3FFF : loaded application area    — 12 KB
 *
 * Protocol (little-endian, no checksum — simulator domain):
 *   host → BRAM:
 *     1 byte  sync    0xA5
 *     4 bytes length  program size in bytes (<= 0x3000)
 *     N bytes program
 *   BRAM → host:
 *     "BOOT\n"     on startup (ready marker)
 *     "ERR_LEN\n"  if length > 12 KB
 *     "LOAD\n"     once all bytes received, just before jumping
 */
#include <stdint.h>

#define UART_BASE    0x10000000u
#define REG(o)       (*(volatile uint32_t *)(UART_BASE + (o)))
#define UART_DATA    REG(0x00)
#define UART_STATUS  REG(0x04)
#define UART_CTRL    REG(0x08)

#define S_TX_FULL    (1u << 1)
#define S_RX_EMPTY   (1u << 2)

#define APP_BASE     0x00001000u
#define APP_MAX      0x00003000u     /* 12 KB */

static void put(char c) {
    while (UART_STATUS & S_TX_FULL) { /* spin */ }
    UART_DATA = (uint32_t)(unsigned char)c;
}

static void puts_(const char *s) {
    while (*s) put(*s++);
}

static unsigned char get(void) {
    while (UART_STATUS & S_RX_EMPTY) { /* spin */ }
    return (unsigned char)(UART_DATA & 0xFF);
}

int main(void) {
    UART_CTRL = 0x3;   /* TX_EN | RX_EN */
    puts_("BOOT\n");

    /* Sync */
    while (get() != 0xA5) { /* swallow junk */ }

    /* Length (little-endian) */
    uint32_t len = 0;
    len |= (uint32_t)get() <<  0;
    len |= (uint32_t)get() <<  8;
    len |= (uint32_t)get() << 16;
    len |= (uint32_t)get() << 24;

    if (len == 0 || len > APP_MAX) {
        puts_("ERR_LEN\n");
        for (;;) { /* halt */ }
    }

    /* Payload into BRAM */
    volatile unsigned char *dst = (volatile unsigned char *)APP_BASE;
    for (uint32_t i = 0; i < len; i++) dst[i] = get();

    puts_("LOAD\n");

    /* Jump to loaded app.  GCC won't emit a return. */
    ((void (*)(void))APP_BASE)();

    for (;;) { /* unreachable */ }
    return 0;
}
