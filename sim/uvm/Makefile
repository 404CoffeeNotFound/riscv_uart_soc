# Block-level UVM testbench for uart_top (AXI4-Lite DUT).
# Default backend: Vivado 2024.2 xsim (bundled UVM-1.2).
SIM  ?= xsim
TEST ?= uart_basic_test

# ---------------- xsim ----------------
ifeq ($(SIM),xsim)
run:
	xvlog -sv --incr -L uvm -f filelist.f
	xelab -L uvm --debug typical --timescale 1ns/1ps uart_tb_top -s uart_tb
	xsim uart_tb --runall --testplusarg "UVM_TESTNAME=$(TEST)"

regress:
	@for t in uart_basic_test uart_reg_rw_test uart_fifo_full_test uart_frame_err_test; do \
	    echo "=== $$t ==="; \
	    $(MAKE) SIM=xsim TEST=$$t run 2>&1 | tee $$t.log | \
	        grep -E "UVM_ERROR|UVM_FATAL|SB_SUM" | head -10; \
	    grep -qE "UVM_ERROR :    0" $$t.log && \
	    grep -qE "UVM_FATAL :    0" $$t.log || \
	        { echo "FAILED: $$t"; exit 1; }; \
	done; \
	echo "=== all tests passed ==="

clean:
	rm -rf xsim.dir xsim.covdb *.jou *.log *.pb *.wdb *.vcd transcript
endif

.PHONY: run regress clean
