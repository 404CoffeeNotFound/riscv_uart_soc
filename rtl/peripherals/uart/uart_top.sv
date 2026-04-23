// uart_top.sv — AXI4-Lite slave wrapper around uart_core.
//
// Accepts one outstanding write and one outstanding read at a time (serial
// AXI4-Lite slave FSM — adequate for the peripheral profile).  Writes require
// both AW and W to arrive before responding on B.  Reads take one cycle of
// capture latency after AR.
`timescale 1ns/1ps

module uart_top #(
    parameter int CLK_FREQ_HZ  = 50_000_000,
    parameter int DEFAULT_BAUD = 115200,
    parameter int FIFO_DEPTH   = 16
)(
    input  logic        aclk,
    input  logic        aresetn,

    // --- AXI4-Lite slave ---
    input  logic [31:0] s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    input  logic [31:0] s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    input  logic        rxd,
    output logic        txd,
    output logic        irq
);
    // -----------------------------------------------------------------
    // Native-style bus to uart_core (driven by our FSMs below)
    // -----------------------------------------------------------------
    logic        mem_valid;
    logic        mem_ready;
    logic [7:0]  mem_addr;
    logic [31:0] mem_wdata;
    logic [3:0]  mem_wstrb;
    logic [31:0] mem_rdata;

    // -----------------------------------------------------------------
    // Write-channel FSM
    // -----------------------------------------------------------------
    typedef enum logic [1:0] {W_IDLE, W_DO, W_RESP} w_state_t;
    w_state_t    w_state;
    logic [31:0] aw_q;
    logic [31:0] wd_q;
    logic [3:0]  ws_q;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            w_state       <= W_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
        end else begin
            case (w_state)
                W_IDLE: begin
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b1;
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        aw_q <= s_axi_awaddr;
                        wd_q <= s_axi_wdata;
                        ws_q <= s_axi_wstrb;
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b0;
                        w_state <= W_DO;
                    end
                end
                W_DO: begin
                    // mem_valid pulses (combinational, below); uart_core
                    // commits the write this cycle.  Assert B response.
                    s_axi_bvalid <= 1'b1;
                    s_axi_bresp  <= 2'b00;   // OKAY
                    w_state      <= W_RESP;
                end
                W_RESP: begin
                    if (s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        w_state      <= W_IDLE;
                    end
                end
                default: w_state <= W_IDLE;
            endcase
        end
    end

    // -----------------------------------------------------------------
    // Read-channel FSM
    // -----------------------------------------------------------------
    typedef enum logic [1:0] {R_IDLE, R_DO, R_RESP} r_state_t;
    r_state_t    r_state;
    logic [31:0] ar_q;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            r_state       <= R_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 32'd0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    s_axi_arready <= 1'b1;
                    if (s_axi_arvalid) begin
                        ar_q <= s_axi_araddr;
                        s_axi_arready <= 1'b0;
                        r_state       <= R_DO;
                    end
                end
                R_DO: begin
                    // mem_valid pulses below; capture mem_rdata and also
                    // allow rx_pop (combinational in core) to take effect.
                    s_axi_rdata  <= mem_rdata;
                    s_axi_rresp  <= 2'b00;
                    s_axi_rvalid <= 1'b1;
                    r_state      <= R_RESP;
                end
                R_RESP: begin
                    if (s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        r_state      <= R_IDLE;
                    end
                end
                default: r_state <= R_IDLE;
            endcase
        end
    end

    // -----------------------------------------------------------------
    // Drive the native-bus pulse to uart_core from whichever channel
    // is in its DO state.  Reads and writes cannot be in DO simultaneously
    // by construction (independent FSMs can be, but the combinations are
    // disjoint on {mem_addr, mem_wstrb}, and uart_core handles any single
    // pulse cleanly).
    // -----------------------------------------------------------------
    always_comb begin
        mem_valid = 1'b0;
        mem_addr  = 8'd0;
        mem_wdata = 32'd0;
        mem_wstrb = 4'd0;
        if (w_state == W_DO) begin
            mem_valid = 1'b1;
            mem_addr  = aw_q[7:0];
            mem_wdata = wd_q;
            mem_wstrb = ws_q;
        end else if (r_state == R_DO) begin
            mem_valid = 1'b1;
            mem_addr  = ar_q[7:0];
            mem_wstrb = 4'b0000;  // read
        end
    end

    uart_core #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .DEFAULT_BAUD(DEFAULT_BAUD),
        .FIFO_DEPTH  (FIFO_DEPTH)
    ) u_core (
        .clk       (aclk),
        .rst_n     (aresetn),
        .mem_valid (mem_valid),
        .mem_ready (mem_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata),
        .rxd       (rxd),
        .txd       (txd),
        .irq       (irq)
    );

    // mem_ready is combinational inside uart_core; unused here but kept on
    // the port for future extensibility.
    /* verilator lint_off UNUSED */
    wire _unused_mem_ready = mem_ready;
    /* verilator lint_on UNUSED */
endmodule
