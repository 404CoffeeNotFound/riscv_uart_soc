# Compile order for the block-level UVM testbench.
# RTL first, then interfaces, then UVC packages (bottom-up), then env, tests, tb_top.

../../rtl/peripherals/uart/uart_core.sv
../../rtl/peripherals/uart/uart_top.sv

../../rtl/bus/axi_lite_if.sv
lib/uart_uvc/uart_if.sv

lib/axi_lite_uvc/axi_lite_pkg.sv
lib/uart_uvc/uart_pkg.sv

env/uart_env_pkg.sv
test/uart_test_pkg.sv
test/uart_tb_top.sv
