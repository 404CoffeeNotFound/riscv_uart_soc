# UART UVM block-level testbench.
# Supports two backends:
#   XSIM     = Vivado's xsim (bundled with Vivado 2024.2, UVM-1.2)
#   QUESTA   = Siemens Questa (if available)
# Default: XSIM.
ROOT     = ../..
RTL      = $(ROOT)/rtl/peripherals/uart/uart_top.sv
UVM_PKG  = uart_uvc_pkg.sv
UVM_IF   = uart_if.sv
TB_TOP   = uart_tb_top.sv

SIM ?= xsim

# ---------------- xsim ----------------
ifeq ($(SIM),xsim)
run:
	xvlog -sv --incr -L uvm $(UVM_IF) $(UVM_PKG) $(RTL) $(TB_TOP)
	xelab -L uvm --debug typical --timescale 1ns/1ps uart_tb_top -s uart_tb
	xsim uart_tb --runall

clean:
	rm -rf xsim.dir *.jou *.log *.pb *.wdb *.vcd
endif

# ---------------- questa ----------------
ifeq ($(SIM),questa)
run:
	vlib work
	vlog -sv +incdir+. $(UVM_IF) $(UVM_PKG) $(RTL) $(TB_TOP)
	vsim -c uart_tb_top -do "run -all; quit"

clean:
	rm -rf work transcript *.vcd
endif

.PHONY: run clean
