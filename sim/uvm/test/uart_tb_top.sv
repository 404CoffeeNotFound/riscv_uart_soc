// uart_tb_top.sv — block-level UVM testbench top for uart_top (AXI4-Lite DUT).
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import uart_test_pkg::*;

module uart_tb_top;
    localparam int CLK_FREQ_HZ = 50_000_000;
    localparam int BAUD        = 115200;

    // --- clock / reset ---
    logic clk = 0;
    always #(10) clk = ~clk;   // 50 MHz

    logic rst_n = 0;
    initial begin
        repeat (20) @(posedge clk);
        rst_n = 1;
    end

    // --- interfaces ---
    axi_lite_if #(.ADDR_W(32))                                axi_if (.aclk(clk), .aresetn(rst_n));
    uart_if     #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD(BAUD))     uif    (.clk(clk));

    // --- DUT ---
    uart_top #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .DEFAULT_BAUD(BAUD)) u_dut (
        .aclk          (clk),
        .aresetn       (rst_n),
        .s_axi_awaddr  (axi_if.awaddr),
        .s_axi_awprot  (axi_if.awprot),
        .s_axi_awvalid (axi_if.awvalid),
        .s_axi_awready (axi_if.awready),
        .s_axi_wdata   (axi_if.wdata),
        .s_axi_wstrb   (axi_if.wstrb),
        .s_axi_wvalid  (axi_if.wvalid),
        .s_axi_wready  (axi_if.wready),
        .s_axi_bresp   (axi_if.bresp),
        .s_axi_bvalid  (axi_if.bvalid),
        .s_axi_bready  (axi_if.bready),
        .s_axi_araddr  (axi_if.araddr),
        .s_axi_arprot  (axi_if.arprot),
        .s_axi_arvalid (axi_if.arvalid),
        .s_axi_arready (axi_if.arready),
        .s_axi_rdata   (axi_if.rdata),
        .s_axi_rresp   (axi_if.rresp),
        .s_axi_rvalid  (axi_if.rvalid),
        .s_axi_rready  (axi_if.rready),
        .rxd           (uif.rxd),
        .txd           (uif.txd),
        .irq           ()
    );

    // --- UVM bootstrap ---
    initial begin
        uvm_config_db#(virtual axi_lite_if)::set(null, "uvm_test_top.env.axi_agt.*",  "vif", axi_if);
        uvm_config_db#(virtual uart_if)   ::set(null, "uvm_test_top.env.uart_agt.*", "vif", uif);
        if ($test$plusargs("UVM_TESTNAME")) run_test();
        else                                run_test("uart_basic_test");
    end

    initial begin
        $dumpfile("uart_tb.vcd");
        $dumpvars(0, uart_tb_top);
        #(200_000_000);
        `uvm_fatal("TIMEOUT", "simulation timed out")
    end
endmodule
