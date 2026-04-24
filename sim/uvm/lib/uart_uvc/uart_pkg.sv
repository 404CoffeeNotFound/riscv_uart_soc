// uart_pkg.sv — package façade for the UART serial-line UVC.
// Each class lives in its own file; this package just pulls them in.
`timescale 1ns/1ps

package uart_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "uart_item.sv"
    `include "uart_driver.sv"
    `include "uart_monitor.sv"

    typedef uvm_sequencer#(uart_item) uart_sequencer;

    `include "uart_agent.sv"
    `include "uart_seq_lib.sv"
endpackage
