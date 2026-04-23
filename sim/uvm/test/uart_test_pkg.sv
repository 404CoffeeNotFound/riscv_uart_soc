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
endpackage
