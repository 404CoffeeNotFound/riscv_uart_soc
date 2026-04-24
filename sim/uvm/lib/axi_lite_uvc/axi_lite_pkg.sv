// axi_lite_pkg.sv — package façade for the AXI4-Lite UVC.
// The package itself only hosts the UVM boilerplate + shared types; each
// class lives in its own file and is pulled in via `include.
`timescale 1ns/1ps

package axi_lite_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Shared enum (used by item + driver + monitor)
    typedef enum bit {AXIL_READ = 0, AXIL_WRITE = 1} axil_dir_e;

    `include "axi_lite_item.sv"
    `include "axi_lite_master_driver.sv"
    `include "axi_lite_monitor.sv"

    // Sequencer is a bare typedef; keep it in the pkg header.
    typedef uvm_sequencer#(axi_lite_item) axi_lite_sequencer;

    `include "axi_lite_agent.sv"
    `include "axi_lite_seq_lib.sv"
endpackage
