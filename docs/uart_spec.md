# UART Specification

## Overview
- Format: **8N1** (8 data, no parity, 1 stop)
- Baud: programmable via `BAUD_DIV`, default 115200 @ 50 MHz core clock
- FIFOs: 16-deep each for TX and RX (synchronous)
- Interrupts: combined IRQ line (see STATUS for source)

## Register Map (Base = 0x1000_0000)
All registers 32-bit word-accessible.

| Offset | Name | Access | Description |
|---|---|---|---|
| 0x00 | DATA | R/W | Write → push to TX FIFO. Read → pop from RX FIFO. |
| 0x04 | STATUS | RO | See bit table below |
| 0x08 | CTRL | R/W | See bit table below |
| 0x0C | BAUD_DIV | R/W | clk_div = f_clk / (baud * 16). Default 27 for 115200 @ 50 MHz. |

### STATUS (offset 0x04, RO)
| Bit | Name | Description |
|---|---|---|
| 0 | TX_EMPTY | 1 when TX FIFO has no pending bytes |
| 1 | TX_FULL | 1 when TX FIFO is full |
| 2 | RX_EMPTY | 1 when RX FIFO has no byte to read |
| 3 | RX_FULL | 1 when RX FIFO is full |
| 4 | FRAME_ERR | Sticky; write-1-to-clear via CTRL.CLR_ERR |
| 5 | OVERRUN | Sticky; RX FIFO overflow |
| 31:6 | reserved | 0 |

### CTRL (offset 0x08, R/W)
| Bit | Name | Description |
|---|---|---|
| 0 | TX_EN | Enable TX shifter |
| 1 | RX_EN | Enable RX sampler |
| 2 | TX_INT_EN | Raise IRQ on TX_EMPTY |
| 3 | RX_INT_EN | Raise IRQ on RX_NOT_EMPTY |
| 4 | ERR_INT_EN | Raise IRQ on frame/overrun |
| 5 | CLR_ERR | W1P to clear sticky error bits in STATUS |
| 31:6 | reserved | 0 |

## IRQ rule
```
irq = (TX_INT_EN & STATUS.TX_EMPTY) |
      (RX_INT_EN & ~STATUS.RX_EMPTY) |
      (ERR_INT_EN & (STATUS.FRAME_ERR | STATUS.OVERRUN));
```

## Baud generator
16× oversampling.
```
tick_div = BAUD_DIV;   // counts up to tick_div-1 then wraps, produces baud_x16_tick
```
At 50 MHz with BAUD_DIV = 27 → baud_x16 = 50e6/27 ≈ 1.852 MHz → baud ≈ 115753 (0.13% off from 115200) ✅

## RX sampling
- Detect falling start bit (sync 2 FF)
- Count 8 baud_x16 ticks → mid of start bit → verify still 0
- Every 16 ticks sample the next bit
- After 8 data bits + stop: if stop != 1 → `FRAME_ERR`, still push byte
- Push to RX FIFO unless full → set `OVERRUN`

## TX
- Pop from TX FIFO when idle and TX_EN=1
- Shift out: start(0) + 8 data LSB first + stop(1)
- One bit every 16 baud_x16 ticks

## Parameters (compile-time)
| Param | Default | Description |
|---|---|---|
| `CLK_FREQ_HZ` | 50_000_000 | System clock |
| `DEFAULT_BAUD` | 115200 | Used to compute reset BAUD_DIV |
| `FIFO_DEPTH` | 16 | Must be power of 2 |
