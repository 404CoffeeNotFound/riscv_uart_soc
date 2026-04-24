// uart_frame_err_test.sv — inject one byte with stop=0 on rxd, then use
// the AXI agent to verify STATUS.FRAME_ERR sets, DATA still reads the
// byte, and CTRL.CLR_ERR (W1P) clears the sticky bit.
// Included from uart_test_pkg.sv.

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

        axi_write(UART_CTRL, (1 << CTRL_TX_EN) | (1 << CTRL_RX_EN));

        inj.data_val = expected_byte;
        fork
            inj.start(env.uart_agt.seqr);
        join_none

        poll_count = 0;
        do begin
            #(10_000);
            axi_read(UART_STATUS, status);
            poll_count++;
            if (poll_count > 200)
                `uvm_fatal("RX_TIMEOUT",
                    $sformatf("RX_EMPTY never cleared (STATUS=0x%08h)", status))
        end while (status[STAT_RX_EMPTY] == 1'b1);

        `uvm_info("TEST",
            $sformatf("byte arrived after %0d polls; STATUS=0x%08h", poll_count, status), UVM_LOW)

        if (status[STAT_FRAME_ERR] !== 1'b1)
            `uvm_error("FRAME_ERR_EXPECTED",
                $sformatf("STATUS.FRAME_ERR=0 after stop=0 byte (STATUS=0x%08h)", status))
        else
            `uvm_info("FRAME_ERR_OK", "STATUS.FRAME_ERR set as expected", UVM_LOW)

        axi_read(UART_DATA, data);
        if (data[7:0] !== expected_byte)
            `uvm_error("DATA_MISMATCH",
                $sformatf("read 0x%02h, expected 0x%02h", data[7:0], expected_byte))
        else
            `uvm_info("DATA_OK",
                $sformatf("DATA read returned 0x%02h as expected", data[7:0]), UVM_LOW)

        axi_write(UART_CTRL,
                  (1 << CTRL_TX_EN) | (1 << CTRL_RX_EN) | (1 << CTRL_CLR_ERR));
        axi_read (UART_STATUS, status);
        if (status[STAT_FRAME_ERR] !== 1'b0)
            `uvm_error("CLR_ERR_FAILED",
                $sformatf("STATUS.FRAME_ERR still 1 after CLR_ERR (STATUS=0x%08h)", status))
        else
            `uvm_info("CLR_ERR_OK",
                $sformatf("CLR_ERR cleared sticky bit; STATUS=0x%08h", status), UVM_LOW)

        #(100_000);
        phase.drop_objection(this);
    endtask
endclass
