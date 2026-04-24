# Build everything under sw/: hello (standalone), bootloader, app.
#
# Outputs:
#   hello/hello.mem         4096-word BRAM init for the standalone hello demo
#   bootloader/bootloader.mem  4096-word BRAM init for the bootloader
#   app/app.bin             raw binary the bootloader will receive over UART

CROSS    ?= riscv64-unknown-elf
CC        = $(CROSS)-gcc
OBJCOPY   = $(CROSS)-objcopy
OBJDUMP   = $(CROSS)-objdump

ARCH      = rv32i
ABI       = ilp32
CFLAGS    = -march=$(ARCH) -mabi=$(ABI) -nostdlib -nostartfiles -ffreestanding \
            -Os -Wall -Wextra -g

BIN2MEM = python3 scripts/bin2mem.py

all: hello/hello.mem bootloader/bootloader.mem app/app.bin hello/hello.dis \
     bootloader/bootloader.dis app/app.dis

# -------- hello (original standalone program, loaded into BRAM at reset) --
hello/hello.elf: crt0.S hello/main.c linker.ld
	$(CC) $(CFLAGS) -Wl,--no-relax -T linker.ld -o $@ crt0.S hello/main.c

hello/hello.bin: hello/hello.elf
	$(OBJCOPY) -O binary $< $@

hello/hello.mem: hello/hello.bin
	$(BIN2MEM) $< $@

hello/hello.dis: hello/hello.elf
	$(OBJDUMP) -D $< > $@

# -------- bootloader (4 KB image, loaded into BRAM at reset) --------------
bootloader/bootloader.elf: crt0.S bootloader/main.c bootloader/bootloader.ld
	$(CC) $(CFLAGS) -Wl,--no-relax -T bootloader/bootloader.ld -o $@ crt0.S bootloader/main.c

bootloader/bootloader.bin: bootloader/bootloader.elf
	$(OBJCOPY) -O binary $< $@

bootloader/bootloader.mem: bootloader/bootloader.bin
	$(BIN2MEM) $< $@
	@actual=$$(stat -c%s $<); \
	 if [ $$actual -gt 4096 ]; then \
	    echo "ERROR: bootloader.bin is $$actual bytes, exceeds 4 KB"; \
	    exit 1; \
	 else \
	    echo "bootloader.bin size: $$actual bytes ($$(( 4096 - $$actual )) bytes free)"; \
	 fi

bootloader/bootloader.dis: bootloader/bootloader.elf
	$(OBJDUMP) -D $< > $@

# -------- app (loaded into BRAM at 0x1000 by the bootloader at runtime) ---
app/app.elf: crt0.S app/main.c app/app.ld
	$(CC) $(CFLAGS) -Wl,--no-relax -T app/app.ld -o $@ crt0.S app/main.c

app/app.bin: app/app.elf
	$(OBJCOPY) -O binary $< $@
	@actual=$$(stat -c%s $@); \
	 echo "app.bin size: $$actual bytes"

app/app.dis: app/app.elf
	$(OBJDUMP) -D $< > $@

clean:
	rm -f hello/hello.elf hello/hello.bin hello/hello.mem hello/hello.dis
	rm -f bootloader/bootloader.elf bootloader/bootloader.bin \
	      bootloader/bootloader.mem bootloader/bootloader.dis
	rm -f app/app.elf app/app.bin app/app.dis

.PHONY: all clean
