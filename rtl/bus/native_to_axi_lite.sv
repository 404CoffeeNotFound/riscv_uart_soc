// native_to_axi_lite.sv — bridge a PicoRV32 native memory bus transaction
// into an AXI4-Lite master request.  Used by soc_top to let the CPU talk to
// AXI4-Lite slaves (the UART, and future peripherals).
//
// Protocol notes:
//   * PicoRV32 asserts mem_valid until it sees mem_ready.  We hold mem_ready
//     low until the AXI transaction fully completes (BVALID for writes,
//     RVALID for reads).
//   * One outstanding transaction — simple for a single-issue core.
`timescale 1ns/1ps

module native_to_axi_lite (
    input  logic        aclk,
    input  logic        aresetn,

    // PicoRV32 native slave (this module is the slave *on this side*)
    input  logic        mem_valid,
    output logic        mem_ready,
    input  logic [31:0] mem_addr,
    input  logic [31:0] mem_wdata,
    input  logic [3:0]  mem_wstrb,
    output logic [31:0] mem_rdata,

    // AXI4-Lite master
    output logic [31:0] m_axi_awaddr,
    output logic [2:0]  m_axi_awprot,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,

    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,

    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,

    output logic [31:0] m_axi_araddr,
    output logic [2:0]  m_axi_arprot,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,

    input  logic [31:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready
);
    typedef enum logic [2:0] {
        S_IDLE,
        S_W_ADDR,   // awvalid asserted, waiting awready
        S_W_DATA,   // wvalid asserted, waiting wready
        S_W_RESP,   // waiting bvalid
        S_R_ADDR,   // arvalid asserted, waiting arready
        S_R_DATA    // waiting rvalid
    } state_t;
    state_t state;

    logic aw_acked, w_acked;
    logic [31:0] rdata_q;

    assign m_axi_awprot = 3'b000;
    assign m_axi_arprot = 3'b000;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            state         <= S_IDLE;
            aw_acked      <= 1'b0;
            w_acked       <= 1'b0;
            rdata_q       <= 32'd0;
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
            m_axi_awaddr  <= 32'd0;
            m_axi_wdata   <= 32'd0;
            m_axi_wstrb   <= 4'd0;
            m_axi_araddr  <= 32'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    aw_acked <= 1'b0;
                    w_acked  <= 1'b0;
                    if (mem_valid) begin
                        if (mem_wstrb != 4'b0000) begin
                            // write
                            m_axi_awaddr  <= mem_addr;
                            m_axi_awvalid <= 1'b1;
                            m_axi_wdata   <= mem_wdata;
                            m_axi_wstrb   <= mem_wstrb;
                            m_axi_wvalid  <= 1'b1;
                            state         <= S_W_ADDR;
                        end else begin
                            m_axi_araddr  <= mem_addr;
                            m_axi_arvalid <= 1'b1;
                            m_axi_rready  <= 1'b1;
                            state         <= S_R_ADDR;
                        end
                    end
                end

                // Write: track AW and W handshakes independently
                S_W_ADDR: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        aw_acked      <= 1'b1;
                    end
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        w_acked      <= 1'b1;
                    end
                    // If both handshakes done, wait for B
                    if ((aw_acked || (m_axi_awvalid && m_axi_awready)) &&
                        (w_acked  || (m_axi_wvalid  && m_axi_wready ))) begin
                        m_axi_bready <= 1'b1;
                        state        <= S_W_RESP;
                    end
                end

                S_W_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        state        <= S_IDLE;
                    end
                end

                // Read
                S_R_ADDR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        state         <= S_R_DATA;
                    end
                end

                S_R_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        rdata_q      <= m_axi_rdata;
                        m_axi_rready <= 1'b0;
                        state        <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // mem_ready pulses for one cycle when an AXI transaction completes.
    // PicoRV32 samples mem_ready on posedge and de-asserts mem_valid.
    assign mem_ready = ((state == S_W_RESP) && m_axi_bvalid && m_axi_bready) ||
                       ((state == S_R_DATA) && m_axi_rvalid && m_axi_rready);

    assign mem_rdata = ((state == S_R_DATA) && m_axi_rvalid) ? m_axi_rdata : rdata_q;

    /* verilator lint_off UNUSED */
    wire _unused_bresp = |m_axi_bresp;
    wire _unused_rresp = |m_axi_rresp;
    /* verilator lint_on UNUSED */
endmodule
