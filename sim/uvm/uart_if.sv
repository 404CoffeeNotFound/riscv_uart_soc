// uart_if.sv — virtual interface between UVM UVC and DUT.
// Carries the UART serial wires and a config handle to share clock rate / baud.
`timescale 1ns/1ps
interface uart_if #(parameter int CLK_FREQ_HZ = 50_000_000,
                    parameter int BAUD        = 115200) (input logic clk);
    logic rxd;   // host -> DUT  (driver drives this)
    logic txd;   // DUT  -> host (monitor samples this)

    // Helper: number of clk cycles per UART bit.
    localparam int CYC_PER_BIT = CLK_FREQ_HZ / BAUD;

    clocking cb @(posedge clk);
        default input #1step output #1;
        output rxd;
        input  txd;
    endclocking
endinterface
