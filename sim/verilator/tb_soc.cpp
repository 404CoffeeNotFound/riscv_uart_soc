// tb_soc.cpp — Verilator smoke / boot test for soc_top.
//
// Two modes, selected by the BOOT env var:
//   BOOT unset:  BRAM pre-loaded with hello/hello.mem; the harness just
//                captures bytes from uart_tx (prints "Hello, MiniRV...").
//   BOOT=1:      BRAM pre-loaded with bootloader/bootloader.mem; the
//                harness also reads sw/app/app.bin and, after observing
//                "BOOT\n" on txd, bit-bangs the sync byte + length + app
//                bytes onto uart_rx.  Expected txd output: "BOOT\nLOAD\nAPP_OK\n".

#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <vector>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vsoc_top.h"

static const uint64_t CLK_HZ        = 50'000'000;
static const uint64_t BAUD          = 115200;
static const uint64_t TICKS_PER_BIT = (CLK_HZ + BAUD/2) / BAUD;

static vluint64_t sim_time = 0;

static void tick(Vsoc_top* dut, VerilatedVcdC* vcd) {
    dut->sys_clk_125 = 0; dut->eval();
    if (vcd) vcd->dump(sim_time++);
    dut->sys_clk_125 = 1; dut->eval();
    if (vcd) vcd->dump(sim_time++);
}

// ---------------------------------------------------------------------------
// RX bit-banger: drives dut->uart_rx at the configured baud rate from a
// queue of bytes.  Idle when queue empty.
// ---------------------------------------------------------------------------
struct RxBangOut {
    std::vector<uint8_t> queue;
    size_t               byte_idx   = 0;
    int                  bit_idx    = -1;   // -1=idle, 0=start, 1..8=data, 9=stop
    uint64_t             next_edge  = 0;
    void push_byte(uint8_t b)       { queue.push_back(b); }
    void push_u32_le(uint32_t v) {
        for (int i = 0; i < 4; i++) push_byte((v >> (i*8)) & 0xFF);
    }
};

static void update_rx(RxBangOut& rx, uint64_t cyc, Vsoc_top* dut) {
    if (rx.bit_idx < 0) {
        dut->uart_rx = 1;                         // line idle high
        if (rx.byte_idx < rx.queue.size()) {
            rx.bit_idx   = 0;
            dut->uart_rx = 0;                     // start bit
            rx.next_edge = cyc + TICKS_PER_BIT;
        }
        return;
    }
    if (cyc < rx.next_edge) return;

    rx.bit_idx++;
    if (rx.bit_idx <= 8) {
        uint8_t byte = rx.queue[rx.byte_idx];
        dut->uart_rx = (byte >> (rx.bit_idx - 1)) & 1;
        rx.next_edge = cyc + TICKS_PER_BIT;
    } else if (rx.bit_idx == 9) {
        dut->uart_rx = 1;                         // stop bit
        rx.next_edge = cyc + TICKS_PER_BIT;
    } else {
        rx.byte_idx++;
        rx.bit_idx = -1;
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
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

    const bool boot_mode = getenv("BOOT") != nullptr;

    // Load app.bin if in boot mode
    std::vector<uint8_t> app_bytes;
    if (boot_mode) {
        const char* path = "../../sw/app/app.bin";
        FILE* f = fopen(path, "rb");
        if (!f) { fprintf(stderr, "can't open %s\n", path); return 1; }
        uint8_t buf[256];
        size_t n;
        while ((n = fread(buf, 1, sizeof(buf), f)) > 0) {
            app_bytes.insert(app_bytes.end(), buf, buf + n);
        }
        fclose(f);
        fprintf(stderr, "[tb] boot-mode: app.bin = %zu bytes\n", app_bytes.size());
    }

    RxBangOut rx;
    dut->uart_rx = 1;

    // Reset
    dut->rst_btn = 1;
    for (int i = 0; i < 20; i++) tick(dut.get(), vcd);
    dut->rst_btn = 0;

    // TX sampler state
    uint64_t cyc = 0;
    const uint64_t max_cyc = boot_mode ? 20'000'000ULL : 2'000'000ULL;
    int        tx_state    = 0;
    uint64_t   next_sample = 0;
    int        bit_idx     = 0;
    uint8_t    shreg       = 0;

    std::string tx_tail;          // most recent txd bytes (to detect signatures)
    bool app_queued = false;

    while (cyc < max_cyc && !Verilated::gotFinish()) {
        update_rx(rx, cyc, dut.get());
        tick(dut.get(), vcd);
        cyc++;

        uint8_t txd = dut->uart_tx;

        if (tx_state == 0 && txd == 0) {
            tx_state    = 1;
            next_sample = cyc + TICKS_PER_BIT + TICKS_PER_BIT/2;
            bit_idx     = 0;
            shreg       = 0;
        } else if (tx_state == 1 && cyc >= next_sample) {
            if (bit_idx < 8) {
                shreg |= (txd & 1) << bit_idx;
                bit_idx++;
                next_sample += TICKS_PER_BIT;
            } else {
                fputc(shreg, stdout);
                fflush(stdout);

                if (boot_mode) {
                    tx_tail.push_back((char)shreg);
                    if (tx_tail.size() > 32) tx_tail.erase(0, tx_tail.size() - 32);

                    // Trigger upload once bootloader printed BOOT\n
                    if (!app_queued && tx_tail.find("BOOT\n") != std::string::npos) {
                        rx.push_byte(0xA5);
                        rx.push_u32_le((uint32_t)app_bytes.size());
                        for (uint8_t b : app_bytes) rx.push_byte(b);
                        app_queued = true;
                        fprintf(stderr, "[tb] BOOT seen -> queued %zu payload bytes\n",
                                rx.queue.size());
                    }

                    // Early-exit on success
                    if (tx_tail.find("APP_OK\n") != std::string::npos) {
                        fprintf(stderr, "[tb] APP_OK observed at cyc=%lu\n",
                                (unsigned long)cyc);
                        break;
                    }
                }

                tx_state = 0;
            }
        }
    }

    if (vcd) { vcd->close(); delete vcd; }
    return 0;
}
