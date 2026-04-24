// uart_test_pkg.sv — package façade for tests.
// Hosts the DUT-register localparams and pulls in every concrete test
// via `include.  The base test must come first so the concrete tests
// (which extend it) see it.
`timescale 1ns/1ps

package uart_test_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axi_lite_pkg::*;
    import uart_pkg::*;
    import uart_env_pkg::*;

    // --- UART register byte offsets (from uart_core spec) -----------------
    localparam bit [31:0] UART_DATA    = 32'h0000_0000;
    localparam bit [31:0] UART_STATUS  = 32'h0000_0004;
    localparam bit [31:0] UART_CTRL    = 32'h0000_0008;
    localparam bit [31:0] UART_BAUD    = 32'h0000_000C;

    // --- CTRL register bit positions --------------------------------------
    localparam int CTRL_TX_EN      = 0;
    localparam int CTRL_RX_EN      = 1;
    localparam int CTRL_TX_INT_EN  = 2;
    localparam int CTRL_RX_INT_EN  = 3;
    localparam int CTRL_ERR_INT_EN = 4;
    localparam int CTRL_CLR_ERR    = 5;

    // --- STATUS register bit positions ------------------------------------
    localparam int STAT_TX_EMPTY   = 0;
    localparam int STAT_TX_FULL    = 1;
    localparam int STAT_RX_EMPTY   = 2;
    localparam int STAT_RX_FULL    = 3;
    localparam int STAT_FRAME_ERR  = 4;
    localparam int STAT_OVERRUN    = 5;

    `include "uart_base_test.sv"
    `include "uart_basic_test.sv"
    `include "uart_reg_rw_test.sv"
    `include "uart_fifo_full_test.sv"
    `include "uart_frame_err_test.sv"
    `include "uart_boot_test.sv"
endpackage
