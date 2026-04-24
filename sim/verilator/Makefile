# Verilator SoC smoke.  Two modes:
#   make          -> hello-world mode (BRAM init = sw/hello/hello.mem)
#   make boot     -> bootloader+app mode (BRAM init = sw/bootloader/bootloader.mem;
#                                          tb_soc streams sw/app/app.bin over rxd)
ROOT     = ../..
SRCS     = $(ROOT)/rtl/core/picorv32/picorv32.v \
           $(ROOT)/rtl/peripherals/uart/uart_core.sv \
           $(ROOT)/rtl/peripherals/uart/uart_top.sv \
           $(ROOT)/rtl/bus/native_to_axi_lite.sv \
           $(ROOT)/rtl/soc/soc_top.sv
TOP      = soc_top
OBJDIR   = obj_dir
BIN      = $(OBJDIR)/V$(TOP)

# Works on old (4.028) and new (5.x) Verilator.
VFLAGS   = --cc --exe \
           --top-module $(TOP) \
           -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-PINMISSING \
           --trace \
           -I$(ROOT)/rtl/core/picorv32 \
           -I$(ROOT)/rtl/peripherals/uart \
           -I$(ROOT)/rtl/bus \
           -I$(ROOT)/rtl/soc

all: run

# -------- hello mode --------
$(BIN)-hello.stamp: $(SRCS) tb_soc.cpp
	@test -f $(ROOT)/sw/hello/hello.mem || (echo "Build SW first: make -C $(ROOT)/sw" && exit 1)
	cp $(ROOT)/sw/hello/hello.mem ./hello.mem
	verilator $(VFLAGS) $(SRCS) tb_soc.cpp
	$(MAKE) -j -C $(OBJDIR) -f V$(TOP).mk V$(TOP)
	@touch $@

run: $(BIN)-hello.stamp
	./$(BIN)

# -------- bootloader mode --------
# The testharness (BOOT=1 env var) reads sw/app/app.bin and bit-bangs it
# onto rxd once "BOOT\n" appears on txd.  Successful completion prints
# "APP_OK\n" to stdout.
boot: $(SRCS) tb_soc.cpp
	@test -f $(ROOT)/sw/bootloader/bootloader.mem || (echo "Build SW first: make -C $(ROOT)/sw" && exit 1)
	@test -f $(ROOT)/sw/app/app.bin            || (echo "Build SW first: make -C $(ROOT)/sw" && exit 1)
	cp $(ROOT)/sw/bootloader/bootloader.mem ./hello.mem
	verilator $(VFLAGS) $(SRCS) tb_soc.cpp
	$(MAKE) -j -C $(OBJDIR) -f V$(TOP).mk V$(TOP)
	BOOT=1 ./$(BIN)

clean:
	rm -rf $(OBJDIR) sim.vcd hello.mem $(BIN)-*.stamp

.PHONY: all run boot clean
