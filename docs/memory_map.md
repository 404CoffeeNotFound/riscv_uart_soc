# Memory Map

32-bit flat address space. PicoRV32 native bus (not AXI). All accesses word-aligned except explicitly sub-word writes via `mem_wstrb`.

## Regions
| Base | Size | Name | Access | Notes |
|---|---|---|---|---|
| `0x0000_0000` | 16 KB | BRAM | R/W | Code + data. Initialized from `sw/hello/hello.mem` at elaboration. |
| `0x1000_0000` | 256 B | UART | R/W | See uart_spec.md |
| `0x2000_0000` | 16 B | GPIO | R/W | `[0]=LEDs`, future expansion |
| else | — | — | — | Returns 0 on read, ignored on write |

## Reset vector
PicoRV32 `PROGADDR_RESET = 0x0000_0000`. First instruction at BRAM[0].

## Interrupt map
PicoRV32 has 32 IRQ lines (custom, not standard RISC-V CLINT).
| IRQ | Source |
|---|---|
| 0 | UART combined (tx_empty OR rx_not_empty OR frame_err, masked by CTRL) |
| 1..31 | unused (tie low) |

## Bus protocol (PicoRV32 native)
Signals from core → slave:
- `mem_valid` — asserts when transaction active
- `mem_addr[31:0]`
- `mem_wdata[31:0]`, `mem_wstrb[3:0]` — wstrb=0 means read, else write
- `mem_instr` — instruction fetch flag (ignored by peripherals)

Signal from slave → core:
- `mem_ready` — must pulse high for one cycle with `mem_rdata` valid for reads
- `mem_rdata[31:0]`

BRAM latency = 1 cycle. UART/GPIO registers = 1 cycle combinational read.
