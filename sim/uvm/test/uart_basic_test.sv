// uart_basic_test.sv — AXI master writes a mix of corner + random bytes
// to UART.DATA; the scoreboard verifies each appears on txd.
// Included from uart_test_pkg.sv.

class uart_basic_test extends uart_base_test;
    `uvm_component_utils(uart_basic_test)
    rand int unsigned n_bytes = 16;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        bit [31:0] rd;
        phase.raise_objection(this);
        `uvm_info("TEST", $sformatf("uart_basic_test — will push %0d bytes via AXI", n_bytes), UVM_LOW)

        axi_write(UART_CTRL, 32'h0000_0003);
        axi_read (UART_CTRL, rd);
        `uvm_info("TEST", $sformatf("readback CTRL=0x%08h", rd), UVM_LOW)

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

        #(5_000_000);    // 5 ms drain
        phase.drop_objection(this);
    endtask
endclass
