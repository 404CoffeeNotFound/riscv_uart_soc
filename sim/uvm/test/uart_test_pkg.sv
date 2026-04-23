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
