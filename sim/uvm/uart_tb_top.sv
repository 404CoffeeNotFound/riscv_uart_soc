// uart_tb_top.sv — standalone UVM testbench for uart_top (block-level, Week 3).
// Does NOT instantiate the full SoC; drives the PicoRV32 bus slave directly
// via a tiny bus BFM written in SV procedural code.
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"
import uart_uvc_pkg::*;

module uart_tb_top;
    localparam int CLK_FREQ_HZ = 50_000_000;
    localparam int BAUD        = 115200;

    logic clk = 0;
    always #(10) clk = ~clk;  // 50 MHz -> 20 ns period

    logic rst_n = 0;
    initial begin
        repeat (20) @(posedge clk);
        rst_n = 1;
    end

    // UART DUT I/O
    uart_if #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD(BAUD)) uif (.clk(clk));

    // PicoRV32-style bus driver (simple initial block — expand into a BFM class)
    logic        mem_valid = 0;
    logic        mem_ready;
    logic [7:0]  mem_addr  = 0;
    logic [31:0] mem_wdata = 0;
    logic [3:0]  mem_wstrb = 0;
    logic [31:0] mem_rdata;
    logic        irq;

    uart_top #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .DEFAULT_BAUD(BAUD)) u_dut (
        .clk, .rst_n,
        .mem_valid, .mem_ready, .mem_addr, .mem_wdata, .mem_wstrb, .mem_rdata,
        .rxd (uif.rxd),
        .txd (uif.txd),
        .irq (irq)
    );

    // convenience tasks
    task automatic bus_write(input logic [7:0] addr, input logic [31:0] data);
        @(posedge clk);
        mem_valid <= 1; mem_addr <= addr; mem_wdata <= data; mem_wstrb <= 4'hF;
        do @(posedge clk); while (!mem_ready);
        mem_valid <= 0; mem_wstrb <= 4'h0;
    endtask

    task automatic bus_read(input logic [7:0] addr, output logic [31:0] data);
        @(posedge clk);
        mem_valid <= 1; mem_addr <= addr; mem_wstrb <= 4'h0;
        do @(posedge clk); while (!mem_ready);
        data = mem_rdata;
        mem_valid <= 0;
    endtask

    // UVM boot — run_test must fire at time 0 (no prior consumption of sim time)
    initial begin
        uvm_config_db#(virtual uart_if)::set(null, "uvm_test_top.env.agt.*", "vif", uif);
        // Pass no argument so +UVM_TESTNAME=<name> (from Makefile) selects
        // the concrete test.  Falls back to uart_basic_test if not provided.
        if ($test$plusargs("UVM_TESTNAME")) run_test();
        else                                run_test("uart_basic_test");
    end

    // After reset, configure UART CTRL register (TX_EN | RX_EN) then run a
    // software-style loopback: whenever RX FIFO has a byte, pop it and push it
    // into TX FIFO.  This lets the monitor observe what the DUT received from
    // the driver, via the DUT's own TX engine — exercising the full data path.
    initial begin
        logic [31:0] status, data;
        wait (rst_n == 1);
        @(posedge clk);
        bus_write(8'h08, 32'h03);     // CTRL = TX_EN | RX_EN

        forever begin
            bus_read(8'h04, status);
            if (!status[2] /*RX_EMPTY*/) begin
                bus_read(8'h00, data);        // pop RX FIFO
                // wait until TX FIFO not full, then push
                do bus_read(8'h04, status); while (status[1] /*TX_FULL*/);
                bus_write(8'h00, data);
            end else begin
                @(posedge clk);               // small idle tick
            end
        end
    end

    initial begin
        $dumpfile("uart_tb.vcd");
        $dumpvars(0, uart_tb_top);
        #(200_000_000);  // 200 ms timeout
        `uvm_fatal("TIMEOUT", "simulation ran too long")
    end
endmodule
