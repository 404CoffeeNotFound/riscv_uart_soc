#!/bin/bash
# Toolchain installation guide for riscv_uart_soc.
# This script is INFORMATIONAL — review before running.
# RISC-V bare-metal toolchain + Verilator are the two hard requirements.

set -e

echo "=== 1. RISC-V bare-metal toolchain (GCC + newlib) ==="
echo "    apt package is sufficient for RV32I baremetal:"
echo "    sudo apt-get update"
echo "    sudo apt-get install -y gcc-riscv64-unknown-elf"
echo ""
echo "    (The 'riscv64' name is fine — with -march=rv32i we emit 32-bit code.)"
echo ""
echo "    Verify:"
echo "    riscv64-unknown-elf-gcc --version"
echo ""

echo "=== 2. Verilator ==="
echo "    Ubuntu 20.04 apt version is too old (v4.x). Build from source:"
echo "    sudo apt-get install -y git make autoconf g++ flex bison libfl2 libfl-dev zlib1g-dev help2man perl"
echo "    git clone https://github.com/verilator/verilator /tmp/verilator"
echo "    cd /tmp/verilator && git checkout stable"
echo "    autoconf && ./configure && make -j\$(nproc) && sudo make install"
echo ""

echo "=== 3. (Optional) cocotb + pyuvm for open-source UVM ==="
echo "    python3 -m pip install --user cocotb pyuvm"
echo ""

echo "=== 4. (Optional) GTKWave for waveform viewing ==="
echo "    sudo apt-get install -y gtkwave"
echo ""

echo "=== 5. picocom for serial terminal (Week 5) ==="
echo "    sudo apt-get install -y picocom"
echo ""

echo "After installing:"
echo "  which riscv64-unknown-elf-gcc verilator gtkwave picocom"
