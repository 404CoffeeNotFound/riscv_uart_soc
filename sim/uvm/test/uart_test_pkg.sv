// uart_test_pkg.sv — test library.
// Tests drive high-level scenarios via the AXI master agent.  The UART
// agent's monitor (always passive) observes txd and feeds the scoreboard.
`timescale 1ns/1ps

package uart_test_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axi_lite_pkg::*;
    import uart_pkg::*;
    import uart_env_pkg::*;

    // UART register byte offsets (from uart_core spec)
    localparam bit [31:0] UART_DATA    = 32'h0000_0000;
    localparam bit [31:0] UART_STATUS  = 32'h0000_0004;
    localparam bit [31:0] UART_CTRL    = 32'h0000_0008;
    localparam bit [31:0] UART_BAUD    = 32'h0000_000C;

    // ----------------- base test -----------------
    class uart_base_test extends uvm_test;
        `uvm_component_utils(uart_base_test)
        uart_env env;

        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            env = uart_env::type_id::create("env", this);
        endfunction

        // Convenience: single-write via the axi agent (blocks until complete).
        task axi_write(bit [31:0] addr, bit [31:0] data, bit [3:0] strb = 4'hF);
            axi_lite_write_seq seq = axi_lite_write_seq::type_id::create("seq");
            seq.addr = addr; seq.data = data; seq.strb = strb;
            seq.start(env.axi_agt.seqr);
        endtask

        task axi_read(bit [31:0] addr, output bit [31:0] rdata);
            axi_lite_read_seq seq = axi_lite_read_seq::type_id::create("seq");
            seq.addr = addr;
            seq.start(env.axi_agt.seqr);
            rdata = seq.rdata;
        endtask
    endclass

    // CTRL register bit positions
    localparam int CTRL_TX_EN      = 0;
    localparam int CTRL_RX_EN      = 1;
    localparam int CTRL_TX_INT_EN  = 2;
    localparam int CTRL_RX_INT_EN  = 3;
    localparam int CTRL_ERR_INT_EN = 4;
    localparam int CTRL_CLR_ERR    = 5;

    // STATUS register bit positions
    localparam int STAT_TX_EMPTY   = 0;
    localparam int STAT_TX_FULL    = 1;
    localparam int STAT_RX_EMPTY   = 2;
    localparam int STAT_RX_FULL    = 3;
    localparam int STAT_FRAME_ERR  = 4;
    localparam int STAT_OVERRUN    = 5;

    // ----------------- TX-path test -----------------
    // AXI master writes bytes to UART.DATA; scoreboard verifies that each
    // byte appears on the serial txd line.
    class uart_basic_test extends uart_base_test;
        `uvm_component_utils(uart_basic_test)
        rand int unsigned n_bytes = 16;

        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        task run_phase(uvm_phase phase);
            bit [31:0] rd;
            phase.raise_objection(this);
            `uvm_info("TEST", $sformatf("uart_basic_test — will push %0d bytes via AXI", n_bytes), UVM_LOW)

            // Enable TX and RX
            axi_write(UART_CTRL, 32'h0000_0003);
            axi_read (UART_CTRL, rd);
            `uvm_info("TEST", $sformatf("readback CTRL=0x%08h", rd), UVM_LOW)

            // Mix of corner patterns + randoms
            axi_write(UART_DATA, 32'h0000_0048);   // 'H'
            axi_write(UART_DATA, 32'h0000_0069);   // 'i'
            axi_write(UART_DATA, 32'h0000_0021);   // '!'
            axi_write(UART_DATA, 32'h0000_0000);   // NUL
            axi_write(UART_DATA, 32'h0000_00FF);   // 0xFF
            axi_write(UART_DATA, 32'h0000_0055);   // 0x55
            axi_write(UART_DATA, 32'h0000_00AA);   // 0xAA
            for (int i = 0; i < n_bytes - 7; i++) begin
                bit [7:0] rnd = $urandom_range(8'h00, 8'hFF);
                axi_write(UART_DATA, {24'd0, rnd});
            end

            // Drain — last byte at 115200 takes ~87 us to shift out; pad well.
            #(5_000_000);    // 5 ms
            phase.drop_objection(this);
        endtask
    endclass

    // ----------------- Register read/write test -----------------
    // Exercises CTRL and BAUD_DIV register paths (write-then-read equality)
    // and confirms STATUS is read-only / sensible at reset.
    class uart_reg_rw_test extends uart_base_test;
        `uvm_component_utils(uart_reg_rw_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        task check_ctrl_rw(bit [5:0] pattern);
            bit [31:0] rd;
            bit [5:0]  expected;
            // CTRL bit 5 is CLR_ERR (W1P; reads 0), bits 0..4 are R/W.
            expected = pattern & 6'h1F;
            axi_write(UART_CTRL, {26'd0, pattern});
            axi_read (UART_CTRL, rd);
            if (rd[5:0] !== expected)
                `uvm_error("CTRL_RW",
                    $sformatf("wrote 0x%02h, read 0x%02h (expected 0x%02h)",
                              pattern, rd[5:0], expected))
        endtask

        task check_baud_rw(bit [15:0] value);
            bit [31:0] rd;
            axi_write(UART_BAUD, {16'd0, value});
            axi_read (UART_BAUD, rd);
            if (rd[15:0] !== value)
                `uvm_error("BAUD_RW",
                    $sformatf("wrote 0x%04h, read 0x%04h", value, rd[15:0]))
        endtask

        task run_phase(uvm_phase phase);
            bit [31:0] status;
            phase.raise_objection(this);
            `uvm_info("TEST", "uart_reg_rw_test — register read/write paths", UVM_LOW)

            // CTRL patterns — walk every functional bit
            check_ctrl_rw(6'b00_0000);
            check_ctrl_rw(6'b00_0001);   // TX_EN
            check_ctrl_rw(6'b00_0010);   // RX_EN
            check_ctrl_rw(6'b00_0100);   // TX_INT_EN
            check_ctrl_rw(6'b00_1000);   // RX_INT_EN
            check_ctrl_rw(6'b01_0000);   // ERR_INT_EN
            check_ctrl_rw(6'b10_0000);   // CLR_ERR (should NOT stick)
            check_ctrl_rw(6'b01_1111);   // all R/W bits on
            check_ctrl_rw(6'b00_0011);   // common default (TX+RX)

            // BAUD_DIV — default reset value is 27 (115200 @ 50 MHz).
            // Walk a few values including corner 0 (baud gen disables ticks).
            check_baud_rw(16'h001B);
            check_baud_rw(16'h0001);
            check_baud_rw(16'hFFFF);
            check_baud_rw(16'h0000);     // valid write; baud gen idles
            check_baud_rw(16'h001B);     // restore default

            // STATUS: after the above, RX FIFO is empty, TX FIFO is empty.
            // We haven't enabled interrupts or induced errors, so the bit
            // pattern should be: TX_EMPTY=1, RX_EMPTY=1 → 0x05.
            axi_write(UART_CTRL, (1 << CTRL_TX_EN) | (1 << CTRL_RX_EN));
            axi_read (UART_STATUS, status);
            if (status[5:0] !== 6'h05)
                `uvm_error("STATUS_AT_RESET",
                    $sformatf("expected STATUS[5:0]=0x05, read 0x%02h", status[5:0]))

            #(50_000);
            phase.drop_objection(this);
        endtask
    endclass

    // ----------------- TX FIFO-full test -----------------
    // Rapidly writes DATA while polling STATUS.TX_FULL.  Confirms:
    //   (a) TX_FULL eventually asserts (FIFO actually fills),
    //   (b) we can drain and TX_EMPTY reasserts,
    //   (c) scoreboard sees every written byte on txd (no silent drops).
    class uart_fifo_full_test extends uart_base_test;
        `uvm_component_utils(uart_fifo_full_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        task run_phase(uvm_phase phase);
            bit [31:0] status;
            int unsigned n_written = 0;
            int unsigned drain_polls;

            phase.raise_objection(this);
            `uvm_info("TEST", "uart_fifo_full_test — fill TX FIFO without overflow", UVM_LOW)

            axi_write(UART_CTRL, (1 << CTRL_TX_EN));   // TX only

            // Fill loop: read STATUS first, write DATA only if not full.
            for (int i = 0; i < 24; i++) begin
                axi_read(UART_STATUS, status);
                if (status[STAT_TX_FULL]) break;
                axi_write(UART_DATA, 32'h0000_0030 + i);  // ASCII digits/letters
                n_written++;
            end
            `uvm_info("FIFO_DEPTH",
                $sformatf("wrote %0d bytes before TX_FULL asserted", n_written), UVM_LOW)

            // Sanity: FIFO is 16-deep.  Writes should stop somewhere in 15..17.
            if (n_written < 14 || n_written > 17)
                `uvm_error("DEPTH",
                    $sformatf("unexpected fill count %0d (want 14..17 given TX engine timing)",
                              n_written))

            // FULL assertion check
            axi_read(UART_STATUS, status);
            if (!status[STAT_TX_FULL])
                `uvm_error("TX_FULL_EXPECTED",
                    $sformatf("STATUS=0x%08h after fill — TX_FULL should be 1", status))

            // Drain: wait for TX_EMPTY (all bytes shifted out + stop bit complete).
            // Worst case 17 bytes @ 115200 baud ≈ 1.5 ms.
            drain_polls = 0;
            do begin
                #(50_000);
                axi_read(UART_STATUS, status);
                drain_polls++;
                if (drain_polls > 100)
                    `uvm_fatal("DRAIN_TIMEOUT",
                        $sformatf("TX_EMPTY never asserted (STATUS=0x%08h)", status))
            end while (!status[STAT_TX_EMPTY]);
            `uvm_info("DRAIN",
                $sformatf("TX_EMPTY after %0d polls; STATUS=0x%08h", drain_polls, status), UVM_LOW)

            // TX_EMPTY reflects the FIFO only; the TX shift register may
            // still be sending the final byte.  Pad ≥1 bit-time of wait
            // (1 byte = ~87 us @ 115200 baud) so the UART monitor can
            // capture the final byte's stop bit.
            #(200_000);    // 200 us

            // Final safety: TX_FULL should also be clear
            if (status[STAT_TX_FULL])
                `uvm_error("TX_FULL_STUCK", "TX_FULL still set after drain")

            phase.drop_objection(this);
        endtask
    endclass

    // ----------------- SoC-level boot test -----------------
    // Used with soc_tb_top (instantiates soc_top, not uart_top).  The
    // PicoRV32 inside the SoC runs the bootloader loaded at 0x0000_0000.
    // The UART UVC is the only external testbench stimulus:
    //   - driver  injects sync + length + app.bin payload on rxd
    //   - monitor observes every byte on txd
    //   - scoreboard in LOG mode (match_mode=0) accumulates into txd_all
    //
    // PASS criteria: txd_all contains "APP_OK\n".
    class uart_boot_test extends uart_base_test;
        `uvm_component_utils(uart_boot_test)
        string app_bin_path = "../../sw/app/app.bin";

        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        // Slurp a raw binary file into a byte queue using $fread.  One byte
        // at a time to stay compatible across simulators.
        function void load_app(ref byte unsigned out_bytes[$]);
            int fd;
            int n;
            byte unsigned b;
            fd = $fopen(app_bin_path, "rb");
            if (fd == 0) `uvm_fatal("FOPEN", $sformatf("cannot open %s", app_bin_path))
            forever begin
                n = $fread(b, fd);
                if (n == 0) break;
                out_bytes.push_back(b);
            end
            $fclose(fd);
        endfunction

        task run_phase(uvm_phase phase);
            byte unsigned app_bytes[$];
            uart_inject_seq inj = uart_inject_seq::type_id::create("inj");
            int unsigned len;

            phase.raise_objection(this);
            `uvm_info("BOOT_TEST", "SoC-level hybrid UVM+C bootloader test", UVM_LOW)

            load_app(app_bytes);
            len = app_bytes.size();
            `uvm_info("BOOT_TEST", $sformatf("app.bin = %0d bytes", len), UVM_LOW)

            // Let the bootloader print "BOOT\n" and reach its sync-wait loop.
            // Bootloader's 5-byte greeting takes ~435 us at 115200 baud.
            #(1_000_000);   // 1 ms

            // Build the payload stream: 0xA5 sync + 4-byte LE length + app bytes
            inj.bytes.push_back(8'hA5);
            for (int i = 0; i < 4; i++)
                inj.bytes.push_back((len >> (i*8)) & 8'hFF);
            foreach (app_bytes[i]) inj.bytes.push_back(app_bytes[i]);
            `uvm_info("BOOT_TEST",
                $sformatf("injecting %0d bytes on rxd", inj.bytes.size()), UVM_LOW)
            inj.start(env.uart_agt.seqr);

            // Drain for: LOAD + APP_OK prints (~12 bytes * 87 us ≈ 1 ms)
            #(3_000_000);

            // Check signatures
            if (!env.sb.contains("BOOT\n"))
                `uvm_error("MISSING_BOOT", "no 'BOOT\\n' greeting on txd")
            if (!env.sb.contains("LOAD\n"))
                `uvm_error("MISSING_LOAD", "bootloader never printed 'LOAD\\n' (payload not accepted?)")
            if (!env.sb.contains("APP_OK\n"))
                `uvm_error("MISSING_APP_OK",
                    $sformatf("uploaded app did not emit 'APP_OK\\n'. txd_all=%0d bytes",
                              env.sb.txd_all.len()))
            else
                `uvm_info("BOOT_TEST",
                    "== full boot chain verified: BOOT -> LOAD -> APP_OK ==", UVM_NONE)

            phase.drop_objection(this);
        endtask
    endclass

    // ----------------- Frame-error directed test -----------------
    // Uses the UART agent to inject a byte with stop=0, then uses the
    // AXI agent to verify that STATUS.FRAME_ERR sets, DATA still reads
    // the byte, and CTRL.CLR_ERR (W1P) clears the sticky bit.
    class uart_frame_err_test extends uart_base_test;
        `uvm_component_utils(uart_frame_err_test)
        bit [7:0] expected_byte = 8'h5A;

        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        task run_phase(uvm_phase phase);
            bit [31:0] status, data;
            int unsigned poll_count;
            uart_one_err_seq inj = uart_one_err_seq::type_id::create("inj");

            phase.raise_objection(this);
            `uvm_info("TEST", "uart_frame_err_test — inject stop=0 byte and check sticky bit", UVM_LOW)

            // Enable TX and RX (TX_EN | RX_EN) — leave error interrupts off
            axi_write(UART_CTRL, (1 << CTRL_TX_EN) | (1 << CTRL_RX_EN));

            // Kick off serial injection in parallel — uart_one_err_seq sends
            // one byte with stop=0 then idles for 4 bit times.
            inj.data_val = expected_byte;
            fork
                inj.start(env.uart_agt.seqr);
            join_none

            // Poll STATUS.RX_EMPTY until the byte has been captured.
            // Each AXI read takes a few clks; one byte @ 115200 baud = ~87 us.
            poll_count = 0;
            do begin
                #(10_000);   // 10 us between polls
                axi_read(UART_STATUS, status);
                poll_count++;
                if (poll_count > 200)
                    `uvm_fatal("RX_TIMEOUT",
                        $sformatf("RX_EMPTY never cleared (STATUS=0x%08h)", status))
            end while (status[STAT_RX_EMPTY] == 1'b1);

            `uvm_info("TEST",
                $sformatf("byte arrived after %0d polls; STATUS=0x%08h", poll_count, status), UVM_LOW)

            // Assertion 1: FRAME_ERR should be set
            if (status[STAT_FRAME_ERR] !== 1'b1)
                `uvm_error("FRAME_ERR_EXPECTED",
                    $sformatf("STATUS.FRAME_ERR=0 after stop=0 byte (STATUS=0x%08h)", status))
            else
                `uvm_info("FRAME_ERR_OK", "STATUS.FRAME_ERR set as expected", UVM_LOW)

            // Assertion 2: DATA read returns the injected byte
            axi_read(UART_DATA, data);
            if (data[7:0] !== expected_byte)
                `uvm_error("DATA_MISMATCH",
                    $sformatf("read 0x%02h, expected 0x%02h", data[7:0], expected_byte))
            else
                `uvm_info("DATA_OK",
                    $sformatf("DATA read returned 0x%02h as expected", data[7:0]), UVM_LOW)

            // Assertion 3: CLR_ERR writes clear the sticky bit
            axi_write(UART_CTRL,
                      (1 << CTRL_TX_EN) | (1 << CTRL_RX_EN) | (1 << CTRL_CLR_ERR));
            axi_read (UART_STATUS, status);
            if (status[STAT_FRAME_ERR] !== 1'b0)
                `uvm_error("CLR_ERR_FAILED",
                    $sformatf("STATUS.FRAME_ERR still 1 after CLR_ERR (STATUS=0x%08h)", status))
            else
                `uvm_info("CLR_ERR_OK",
                    $sformatf("CLR_ERR cleared sticky bit; STATUS=0x%08h", status), UVM_LOW)

            #(100_000);   // brief drain
            phase.drop_objection(this);
        endtask
    endclass
endpackage
