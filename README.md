# riscv_uart_soc — MiniRV + UART SoC on Zybo Z7-20

PicoRV32 RISC-V 코어에 직접 설계한 메모리-매핑 UART 페리페럴을 붙여 SoC를 완성하고,
UVM + C 하이브리드 테스트벤치로 검증한 뒤 Zybo Z7-20 (Zynq-7020 PL) 에서 "Hello" 를 출력한다.

## Target
- Board: Digilent **Zybo Z7-20** (xc7z020clg400-1)
- Tool: Vivado **2024.2** (Classic Project Flow, TCL 생성)
- 전략: **PL-only** (Zynq PS 미사용). UART는 Pmod JC → USB-TTL 어댑터로 호스트 연결

## Memory Map (요약)
| Region | Base | Size | Device |
|---|---|---|---|
| BRAM (code+data) | `0x0000_0000` | 16 KB | synchronous BRAM |
| UART | `0x1000_0000` | 256 B | 직접 설계 |
| GPIO (LEDs) | `0x2000_0000` | 16 B | LED 4-bit |
| IRQ line 0 | — | — | UART combined IRQ |

자세한 내용: [docs/memory_map.md](docs/memory_map.md), [docs/uart_spec.md](docs/uart_spec.md)

## Directory
```
rtl/core/          - PicoRV32 (fetch_picorv32.sh 로 다운로드)
rtl/peripherals/   - 직접 설계한 UART
rtl/soc/           - 버스 디코드·top 모듈
rtl/constraints/   - Zybo Z7-20 XDC
sim/verilator/     - Verilator C++ 테스트하니스 (Week 1 스모크)
sim/uvm/           - UVM UVC + 테스트 (Week 3)
sw/                - 베어메탈 C, crt0, 링커 스크립트
scripts/           - Vivado TCL, picorv32 fetch, toolchain 설치 가이드
docs/              - 스펙 문서
```

## Quickstart
```bash
# 1. (한 번만) 툴체인 설치 안내
cat scripts/install_toolchain.sh

# 2. PicoRV32 clone
bash scripts/fetch_picorv32.sh

# 3. SW 빌드 (hello world)
make -C sw

# 4. Verilator 스모크 시뮬 (TODO: Week 1)
make -C sim/verilator

# 5. Vivado 프로젝트 생성 (Week 5)
vivado -mode batch -source scripts/create_vivado_project.tcl

# 6. 보드 플래시 후 호스트에서
picocom -b 115200 /dev/ttyUSB0
```

## Roadmap
- [ ] Week 0: toolchain + PicoRV32 fetch
- [ ] Week 1: minimal SoC (Verilator smoke)
- [ ] Week 2: UART RTL 완성
- [ ] Week 3: UART UVM 회귀 ≥ 90% coverage
- [ ] Week 4: C 부트로더 + hybrid UVM/C 테스트
- [ ] Week 5: Zybo Z7-20 bring-up (첫 "Hello")
- [ ] Week 6: writeup, 리소스/타이밍 리포트
