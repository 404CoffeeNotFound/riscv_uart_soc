// uart_reg_rw_test.sv — walks CTRL / BAUD_DIV write-then-read paths and
// confirms STATUS is sensible at reset.  Included from uart_test_pkg.sv.

class uart_reg_rw_test extends uart_base_test;
    `uvm_component_utils(uart_reg_rw_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task check_ctrl_rw(bit [5:0] pattern);
        bit [31:0] rd;
        bit [5:0]  expected;
        expected = pattern & 6'h1F;  // bit 5 is W1P; reads 0
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

        check_ctrl_rw(6'b00_0000);
        check_ctrl_rw(6'b00_0001);   // TX_EN
        check_ctrl_rw(6'b00_0010);   // RX_EN
        check_ctrl_rw(6'b00_0100);   // TX_INT_EN
        check_ctrl_rw(6'b00_1000);   // RX_INT_EN
        check_ctrl_rw(6'b01_0000);   // ERR_INT_EN
        check_ctrl_rw(6'b10_0000);   // CLR_ERR (should NOT stick)
        check_ctrl_rw(6'b01_1111);   // all R/W bits on
        check_ctrl_rw(6'b00_0011);   // common default (TX+RX)

        check_baud_rw(16'h001B);
        check_baud_rw(16'h0001);
        check_baud_rw(16'hFFFF);
        check_baud_rw(16'h0000);     // valid write; baud gen idles
        check_baud_rw(16'h001B);     // restore default

        axi_write(UART_CTRL, (1 << CTRL_TX_EN) | (1 << CTRL_RX_EN));
        axi_read (UART_STATUS, status);
        if (status[5:0] !== 6'h05)
            `uvm_error("STATUS_AT_RESET",
                $sformatf("expected STATUS[5:0]=0x05, read 0x%02h", status[5:0]))

        #(50_000);
        phase.drop_objection(this);
    endtask
endclass
