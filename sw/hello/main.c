/* hello world — polled UART output + LED blink counter. */
#include <stdint.h>

#define UART_BASE  0x10000000u
#define GPIO_BASE  0x20000000u

#define REG(a)  (*(volatile uint32_t *)(a))
#define UART_DATA    REG(UART_BASE + 0x00)
#define UART_STATUS  REG(UART_BASE + 0x04)
#define UART_CTRL    REG(UART_BASE + 0x08)
#define UART_BAUD    REG(UART_BASE + 0x0C)
#define GPIO_LED     REG(GPIO_BASE + 0x00)

/* STATUS bits */
#define TX_EMPTY  (1u << 0)
#define TX_FULL   (1u << 1)
#define RX_EMPTY  (1u << 2)

static void uart_putc(char c) {
    while (UART_STATUS & TX_FULL) { /* spin */ }
    UART_DATA = (uint32_t)(unsigned char)c;
}

static void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

static int uart_getc_nonblock(char *out) {
    if (UART_STATUS & RX_EMPTY) return 0;
    *out = (char)(UART_DATA & 0xFF);
    return 1;
}

int main(void) {
    /* tx_en | rx_en */
    UART_CTRL = 0x3;
    uart_puts("Hello, MiniRV on Zybo Z7-20!\n");

    uint32_t tick = 0;
    for (;;) {
        tick++;
        GPIO_LED = (tick >> 18) & 0xF;   /* visible blink */
        char c;
        if (uart_getc_nonblock(&c)) {
            uart_putc(c);                 /* echo */
        }
    }
    return 0;
}
