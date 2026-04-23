## Zybo Z7-20 — pin constraints for riscv_uart_soc
## Source: Digilent Zybo-Z7 Reference Manual & master XDC.
## Only pins actually used by soc_top are enabled here.

## --- System clock (125 MHz single-ended on K17) ---
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports sys_clk_125]
create_clock -period 8.000 -name sys_clk_125 [get_ports sys_clk_125]

## --- Reset button (BTN0, active-high -> we invert inside top) ---
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports rst_btn]

## --- LEDs (LD0..LD3) ---
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN M15 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]

## --- UART on Pmod JC (upper row) ---
## JC1 -> uart_tx (MiniRV -> host RX)   pin V15
## JC2 -> uart_rx (host TX -> MiniRV)   pin W15
## JC3 -> (unused)                      pin T11
## JC4 -> (unused)                      pin T10
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports uart_tx]
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS33 } [get_ports uart_rx]

## --- Configuration voltage (BANK 0) ---
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## NOTE: double-check pins against the specific Zybo Z7-20 rev in hand
## (Rev B.2+ should match the numbers above).
