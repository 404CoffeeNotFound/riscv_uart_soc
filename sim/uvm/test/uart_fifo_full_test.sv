// uart_fifo_full_test.sv — fills TX FIFO with a poll-then-write loop,
// verifies STATUS.TX_FULL asserts, then drains and checks TX_EMPTY.
// Included from uart_test_pkg.sv.

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

        for (int i = 0; i < 24; i++) begin
            axi_read(UART_STATUS, status);
            if (status[STAT_TX_FULL]) break;
            axi_write(UART_DATA, 32'h0000_0030 + i);  // ASCII digits/letters
            n_written++;
        end
        `uvm_info("FIFO_DEPTH",
            $sformatf("wrote %0d bytes before TX_FULL asserted", n_written), UVM_LOW)

        if (n_written < 14 || n_written > 17)
            `uvm_error("DEPTH",
                $sformatf("unexpected fill count %0d (want 14..17 given TX engine timing)",
                          n_written))

        axi_read(UART_STATUS, status);
        if (!status[STAT_TX_FULL])
            `uvm_error("TX_FULL_EXPECTED",
                $sformatf("STATUS=0x%08h after fill — TX_FULL should be 1", status))

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

        // TX_EMPTY reflects the FIFO only; the TX shift register may still
        // be sending the final byte.  Pad ≥1 bit-time of wait.
        #(200_000);

        if (status[STAT_TX_FULL])
            `uvm_error("TX_FULL_STUCK", "TX_FULL still set after drain")

        phase.drop_objection(this);
    endtask
endclass
