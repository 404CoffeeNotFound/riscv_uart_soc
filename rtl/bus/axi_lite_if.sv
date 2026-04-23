// axi_lite_if.sv — AXI4-Lite SV interface.
// Used by UVM virtual interfaces and by test-bench wire-up.  RTL modules
// that must synthesize (uart_top, native_to_axi_lite) expose flat ports
// to keep Vivado/xsim happy; this interface just bundles the same signals
// for UVM-side convenience.
`timescale 1ns/1ps

interface axi_lite_if #(parameter int ADDR_W = 32) (input logic aclk, input logic aresetn);
    // Write address channel
    logic [ADDR_W-1:0] awaddr;
    logic [2:0]        awprot;
    logic              awvalid;
    logic              awready;

    // Write data channel
    logic [31:0]       wdata;
    logic [3:0]        wstrb;
    logic              wvalid;
    logic              wready;

    // Write response
    logic [1:0]        bresp;
    logic              bvalid;
    logic              bready;

    // Read address
    logic [ADDR_W-1:0] araddr;
    logic [2:0]        arprot;
    logic              arvalid;
    logic              arready;

    // Read data
    logic [31:0]       rdata;
    logic [1:0]        rresp;
    logic              rvalid;
    logic              rready;

    clocking master_cb @(posedge aclk);
        default input #1step output #1;
        output awaddr, awprot, awvalid, wdata, wstrb, wvalid, bready,
               araddr, arprot, arvalid, rready;
        input  awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid;
    endclocking

    clocking monitor_cb @(posedge aclk);
        default input #1step;
        input awaddr, awprot, awvalid, awready, wdata, wstrb, wvalid, wready,
              bresp, bvalid, bready, araddr, arprot, arvalid, arready,
              rdata, rresp, rvalid, rready;
    endclocking

    modport master  (clocking master_cb,  input aclk, aresetn);
    modport monitor (clocking monitor_cb, input aclk, aresetn);
endinterface
