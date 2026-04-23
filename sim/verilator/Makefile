# Verilator smoke-sim build.  Requires verilator + g++.
# Usage: make           -> build + run
#        VCD=1 make run -> also dump sim.vcd
ROOT     = ../..
SRCS     = $(ROOT)/rtl/core/picorv32/picorv32.v \
           $(ROOT)/rtl/peripherals/uart/uart_top.sv \
           $(ROOT)/rtl/soc/soc_top.sv
TOP      = soc_top
OBJDIR   = obj_dir
BIN      = $(OBJDIR)/V$(TOP)

# Works on both old (4.028, apt focal) and new (5.x) Verilator.
# Old verilator lacks --build, so we run the generated sub-makefile explicitly.
VFLAGS   = --cc --exe \
           --top-module $(TOP) \
           -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-PINMISSING \
           --trace \
           -I$(ROOT)/rtl/core/picorv32 \
           -I$(ROOT)/rtl/peripherals/uart \
           -I$(ROOT)/rtl/soc

all: run

$(BIN): $(SRCS) tb_soc.cpp
	@test -f $(ROOT)/sw/hello/hello.mem || (echo "Build SW first: make -C $(ROOT)/sw" && exit 1)
	cp $(ROOT)/sw/hello/hello.mem ./hello.mem
	verilator $(VFLAGS) $(SRCS) tb_soc.cpp
	$(MAKE) -j -C $(OBJDIR) -f V$(TOP).mk V$(TOP)

run: $(BIN)
	./$(BIN)

clean:
	rm -rf $(OBJDIR) sim.vcd hello.mem

.PHONY: all run clean
