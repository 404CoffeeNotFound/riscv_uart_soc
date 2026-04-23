// tb_soc.cpp — Verilator smoke test.
// Builds the SoC, pumps reset, runs N cycles, dumps UART TX to stdout
// by sampling the uart_tx pin at the configured baud.
//
// Build with sim/verilator/Makefile.

#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <memory>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vsoc_top.h"

static const uint64_t CLK_HZ       = 50'000'000;
static const uint64_t BAUD         = 115200;
static const double   NS_PER_CYC   = 1e9 / (double)CLK_HZ;
static const uint64_t TICKS_PER_BIT = (CLK_HZ + BAUD/2) / BAUD;

static vluint64_t sim_time = 0;

static void tick(Vsoc_top* dut, VerilatedVcdC* vcd) {
    dut->sys_clk_125 = 0; dut->eval();
    if (vcd) vcd->dump(sim_time++);
    dut->sys_clk_125 = 1; dut->eval();
    if (vcd) vcd->dump(sim_time++);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    auto dut = std::make_unique<Vsoc_top>();

    VerilatedVcdC* vcd = nullptr;
    if (getenv("VCD")) {
        Verilated::traceEverOn(true);
        vcd = new VerilatedVcdC;
        dut->trace(vcd, 99);
        vcd->open("sim.vcd");
    }

    // reset
    dut->rst_btn = 1;      // active high -> asserted
    dut->uart_rx = 1;      // idle-high UART line (otherwise RX sees endless start bits)
    for (int i = 0; i < 20; i++) tick(dut.get(), vcd);
    dut->rst_btn = 0;

    // run — sample uart_tx at baud center
    uint64_t cyc = 0;
    uint64_t max_cyc = 2'000'000;   // enough to emit several bytes @ 115200
    int      rx_state = 0;          // 0=idle, 1=receiving
    uint64_t next_sample = 0;
    int      bit_idx = 0;
    uint8_t  shreg = 0;

    while (cyc < max_cyc && !Verilated::gotFinish()) {
        tick(dut.get(), vcd);
        cyc++;
        // Track uart_tx at sys clock granularity.
        uint8_t txd = dut->uart_tx;
        if (rx_state == 0 && txd == 0) {
            // start bit detected
            rx_state = 1;
            next_sample = cyc + TICKS_PER_BIT + TICKS_PER_BIT/2; // middle of bit 0
            bit_idx = 0;
            shreg = 0;
        } else if (rx_state == 1 && cyc >= next_sample) {
            if (bit_idx < 8) {
                shreg |= (txd & 1) << bit_idx;
                bit_idx++;
                next_sample += TICKS_PER_BIT;
            } else {
                // stop bit -- print and reset
                fputc(shreg, stdout); fflush(stdout);
                rx_state = 0;
            }
        }
    }

    if (vcd) { vcd->close(); delete vcd; }
    return 0;
}
