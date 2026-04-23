// uart_if.sv — virtual interface for the UART UVC (serial side only).
`timescale 1ns/1ps

interface uart_if #(parameter int CLK_FREQ_HZ = 50_000_000,
                    parameter int BAUD        = 115200) (input logic clk);
    logic rxd;   // host -> DUT
    logic txd;   // DUT  -> host
    localparam int CYC_PER_BIT = CLK_FREQ_HZ / BAUD;
endinterface
