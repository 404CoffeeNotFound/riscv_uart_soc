# SoC-level UVM testbench compile order (DUT = soc_top).
# Include directories are passed to xvlog via -i flags in the Makefile.

../../rtl/core/picorv32/picorv32.v
../../rtl/peripherals/uart/uart_core.sv
../../rtl/peripherals/uart/uart_top.sv
../../rtl/bus/native_to_axi_lite.sv
../../rtl/soc/soc_top.sv

../../rtl/bus/axi_lite_if.sv
lib/uart_uvc/uart_if.sv

lib/axi_lite_uvc/axi_lite_pkg.sv
lib/uart_uvc/uart_pkg.sv

env/uart_env_pkg.sv
test/uart_test_pkg.sv
test/soc_tb_top.sv
