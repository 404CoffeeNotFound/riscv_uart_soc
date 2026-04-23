# Build hello.elf and hello.mem (for $readmemh BRAM init).
CROSS   ?= riscv64-unknown-elf
CC       = $(CROSS)-gcc
OBJCOPY  = $(CROSS)-objcopy
OBJDUMP  = $(CROSS)-objdump

ARCH     = rv32i
ABI      = ilp32
CFLAGS   = -march=$(ARCH) -mabi=$(ABI) -nostdlib -nostartfiles -ffreestanding \
           -Os -Wall -Wextra -g
LDFLAGS  = -T linker.ld -Wl,--no-relax

SRCS     = crt0.S hello/main.c
ELF      = hello/hello.elf
BIN      = hello/hello.bin
MEM      = hello/hello.mem
DUMP     = hello/hello.dis

all: $(MEM) $(DUMP)

$(ELF): $(SRCS) linker.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S hello/main.c

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

# $readmemh wants one 32-bit word per line (hex).  Zero-pad to 16 KB / 4 = 4096 words.
$(MEM): $(BIN)
	python3 -c "import sys; \
d = open('$<','rb').read(); \
d += b'\\0' * ((-len(d)) % 4); \
words = [int.from_bytes(d[i:i+4],'little') for i in range(0,len(d),4)]; \
words += [0] * (4096 - len(words)); \
print('\\n'.join(f'{w:08x}' for w in words))" > $@

$(DUMP): $(ELF)
	$(OBJDUMP) -D $< > $@

clean:
	rm -f $(ELF) $(BIN) $(MEM) $(DUMP)

.PHONY: all clean
