// soc_tb_top.sv — SoC-level UVM testbench for soc_top.
// Runs the full PicoRV32 + bootloader + AXI4-Lite UART stack; the external
// testbench stimulus is the UART line only.  Used by uart_boot_test.
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import uart_test_pkg::*;

module soc_tb_top;
    localparam int CLK_FREQ_HZ = 50_000_000;
    localparam int BAUD        = 115200;

    // --- clock / reset ---
    logic clk = 0;
    always #(10) clk = ~clk;   // 50 MHz

    logic rst_btn = 1;  // active-high on the real board (inverted inside soc_top)
    initial begin
        repeat (20) @(posedge clk);
        rst_btn = 0;            // deassert reset
    end

    // --- UART interface (no AXI — that's internal to the SoC) ---
    uart_if #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD(BAUD)) uif (.clk(clk));

    // --- DUT: full SoC ---
    soc_top #(.SYS_CLK_HZ(CLK_FREQ_HZ), .BRAM_INIT("hello.mem")) u_dut (
        .sys_clk_125 (clk),
        .rst_btn     (rst_btn),
        .led         (),
        .uart_rx     (uif.rxd),
        .uart_tx     (uif.txd)
    );

    // --- UVM bootstrap ---
    initial begin
        // Tell the env there's no external AXI agent in SoC mode.
        uvm_config_db#(bit)::set(null, "uvm_test_top.env", "has_axi_agent", 1'b0);
        uvm_config_db#(bit)::set(null, "uvm_test_top.env.sb", "match_mode",  1'b0);
        // The UART agent's virtual interface.
        uvm_config_db#(virtual uart_if)::set(null, "uvm_test_top.env.uart_agt.*", "vif", uif);

        if ($test$plusargs("UVM_TESTNAME")) run_test();
        else                                run_test("uart_boot_test");
    end

    initial begin
        $dumpfile("soc_tb.vcd");
        #(50_000_000);           // 50 ms hard cap
        `uvm_fatal("TIMEOUT", "SoC simulation timed out")
    end
endmodule
