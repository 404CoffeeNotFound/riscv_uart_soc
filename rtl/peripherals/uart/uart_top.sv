// uart_top.sv — 8N1 UART with 16-deep TX/RX FIFOs and PicoRV32 native-bus slave.
// Spec: docs/uart_spec.md
//
// Register map (byte offset from base):
//   0x00 DATA     R/W  write=push TX, read=pop RX
//   0x04 STATUS   RO   tx_empty, tx_full, rx_empty, rx_full, frame_err, overrun
//   0x08 CTRL     R/W  tx_en, rx_en, tx_int_en, rx_int_en, err_int_en, clr_err(W1P)
//   0x0C BAUD_DIV R/W  clk / (baud*16)
`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// Synchronous FIFO (power-of-2 depth)
// ---------------------------------------------------------------------------
module sync_fifo #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 16    // must be power of 2
)(
    input  logic             clk,
    input  logic             rst_n,
    input  logic             push,
    input  logic [WIDTH-1:0] din,
    input  logic             pop,
    output logic [WIDTH-1:0] dout,
    output logic             empty,
    output logic             full,
    output logic [$clog2(DEPTH):0] level
);
    localparam int AW = $clog2(DEPTH);
    logic [WIDTH-1:0] mem [DEPTH];
    logic [AW:0] wptr, rptr;

    assign empty = (wptr == rptr);
    assign full  = (wptr[AW] != rptr[AW]) && (wptr[AW-1:0] == rptr[AW-1:0]);
    assign level = wptr - rptr;
    assign dout  = mem[rptr[AW-1:0]];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wptr <= '0;
            rptr <= '0;
        end else begin
            if (push && !full)  begin mem[wptr[AW-1:0]] <= din; wptr <= wptr + 1'b1; end
            if (pop  && !empty) rptr <= rptr + 1'b1;
        end
    end
endmodule

// ---------------------------------------------------------------------------
// Baud generator — emits 1-cycle pulse every baud_div system clocks
// (baud_x16_tick, since we oversample by 16).
// ---------------------------------------------------------------------------
module uart_baud_gen (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] baud_div,   // = f_clk / (baud * 16)
    output logic        tick_x16
);
    logic [15:0] cnt;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cnt      <= '0;
            tick_x16 <= 1'b0;
        end else if (baud_div == 16'd0) begin
            tick_x16 <= 1'b0;
        end else if (cnt >= baud_div - 16'd1) begin
            cnt      <= '0;
            tick_x16 <= 1'b1;
        end else begin
            cnt      <= cnt + 16'd1;
            tick_x16 <= 1'b0;
        end
    end
endmodule

// ---------------------------------------------------------------------------
// TX engine — 8N1.  One bit per 16 baud_x16 ticks.
// ---------------------------------------------------------------------------
module uart_tx (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        tick_x16,
    input  logic        tx_en,
    input  logic        fifo_empty,
    input  logic [7:0]  fifo_data,
    output logic        fifo_pop,
    output logic        txd,
    output logic        busy
);
    typedef enum logic [1:0] {S_IDLE, S_START, S_DATA, S_STOP} state_t;
    state_t state;
    logic [3:0]  os_cnt;   // oversample counter 0..15
    logic [2:0]  bit_idx;  // 0..7
    logic [7:0]  shreg;

    assign fifo_pop = (state == S_IDLE) && tx_en && !fifo_empty;
    assign busy     = (state != S_IDLE);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            os_cnt  <= '0;
            bit_idx <= '0;
            shreg   <= '0;
            txd     <= 1'b1;
        end else begin
            case (state)
                S_IDLE: begin
                    txd <= 1'b1;
                    if (tx_en && !fifo_empty) begin
                        shreg   <= fifo_data;
                        state   <= S_START;
                        os_cnt  <= '0;
                    end
                end
                S_START: begin
                    txd <= 1'b0;
                    if (tick_x16) begin
                        if (os_cnt == 4'd15) begin
                            os_cnt  <= '0;
                            bit_idx <= '0;
                            state   <= S_DATA;
                        end else os_cnt <= os_cnt + 4'd1;
                    end
                end
                S_DATA: begin
                    txd <= shreg[0];
                    if (tick_x16) begin
                        if (os_cnt == 4'd15) begin
                            os_cnt <= '0;
                            shreg  <= {1'b0, shreg[7:1]};
                            if (bit_idx == 3'd7) state <= S_STOP;
                            else bit_idx <= bit_idx + 3'd1;
                        end else os_cnt <= os_cnt + 4'd1;
                    end
                end
                S_STOP: begin
                    txd <= 1'b1;
                    if (tick_x16) begin
                        if (os_cnt == 4'd15) begin
                            os_cnt <= '0;
                            state  <= S_IDLE;
                        end else os_cnt <= os_cnt + 4'd1;
                    end
                end
            endcase
        end
    end
endmodule

// ---------------------------------------------------------------------------
// RX engine — 8N1.  Samples at middle of each bit (oversample 16).
// ---------------------------------------------------------------------------
module uart_rx (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        tick_x16,
    input  logic        rx_en,
    input  logic        rxd,
    output logic        byte_valid,  // 1-cycle pulse when byte captured
    output logic [7:0]  byte_data,
    output logic        frame_err
);
    typedef enum logic [1:0] {R_IDLE, R_START, R_DATA, R_STOP} state_t;
    state_t state;
    logic [3:0] os_cnt;
    logic [2:0] bit_idx;
    logic [7:0] shreg;
    logic rxd_s1, rxd_s2;  // metastability sync

    always_ff @(posedge clk) begin
        rxd_s1 <= rxd;
        rxd_s2 <= rxd_s1;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state      <= R_IDLE;
            os_cnt     <= '0;
            bit_idx    <= '0;
            shreg      <= '0;
            byte_valid <= 1'b0;
            byte_data  <= '0;
            frame_err  <= 1'b0;
        end else begin
            byte_valid <= 1'b0;
            frame_err  <= 1'b0;
            case (state)
                R_IDLE: if (rx_en && !rxd_s2) begin
                    state  <= R_START;
                    os_cnt <= '0;
                end
                R_START: if (tick_x16) begin
                    if (os_cnt == 4'd7) begin          // middle of start bit
                        if (rxd_s2 == 1'b0) begin       // valid start
                            os_cnt  <= '0;
                            bit_idx <= '0;
                            state   <= R_DATA;
                        end else begin                  // false start — abort
                            state <= R_IDLE;
                        end
                    end else os_cnt <= os_cnt + 4'd1;
                end
                R_DATA: if (tick_x16) begin
                    if (os_cnt == 4'd15) begin          // middle of next bit
                        os_cnt <= '0;
                        shreg  <= {rxd_s2, shreg[7:1]}; // LSB first
                        if (bit_idx == 3'd7) state <= R_STOP;
                        else bit_idx <= bit_idx + 3'd1;
                    end else os_cnt <= os_cnt + 4'd1;
                end
                R_STOP: if (tick_x16) begin
                    if (os_cnt == 4'd15) begin
                        os_cnt     <= '0;
                        state      <= R_IDLE;
                        byte_valid <= 1'b1;
                        byte_data  <= shreg;
                        if (rxd_s2 == 1'b0) frame_err <= 1'b1; // stop should be 1
                    end else os_cnt <= os_cnt + 4'd1;
                end
            endcase
        end
    end
endmodule

// ---------------------------------------------------------------------------
// UART top — PicoRV32 native-bus slave + TX/RX engines + FIFOs
// ---------------------------------------------------------------------------
module uart_top #(
    parameter int CLK_FREQ_HZ  = 50_000_000,
    parameter int DEFAULT_BAUD = 115200,
    parameter int FIFO_DEPTH   = 16
)(
    input  logic        clk,
    input  logic        rst_n,

    // PicoRV32 native bus slave
    input  logic        mem_valid,
    output logic        mem_ready,
    input  logic [7:0]  mem_addr,     // byte offset within UART region (8 LSB are enough)
    input  logic [31:0] mem_wdata,
    input  logic [3:0]  mem_wstrb,
    output logic [31:0] mem_rdata,

    // external pins
    input  logic        rxd,
    output logic        txd,

    // IRQ
    output logic        irq
);
    // --- register state ---
    localparam logic [15:0] RST_BAUD_DIV = CLK_FREQ_HZ / (DEFAULT_BAUD * 16);

    logic [15:0] baud_div_q;
    logic        tx_en_q, rx_en_q, tx_int_en_q, rx_int_en_q, err_int_en_q;
    logic        frame_err_sticky, overrun_sticky;

    // --- FIFO wires ---
    logic        tx_push, tx_pop, tx_empty, tx_full;
    logic [7:0]  tx_data_in, tx_data_out;
    logic        rx_push, rx_pop, rx_empty, rx_full;
    logic [7:0]  rx_data_in, rx_data_out;

    sync_fifo #(.WIDTH(8), .DEPTH(FIFO_DEPTH)) u_tx_fifo (
        .clk, .rst_n,
        .push(tx_push), .din(tx_data_in),
        .pop (tx_pop),  .dout(tx_data_out),
        .empty(tx_empty), .full(tx_full), .level()
    );
    sync_fifo #(.WIDTH(8), .DEPTH(FIFO_DEPTH)) u_rx_fifo (
        .clk, .rst_n,
        .push(rx_push), .din(rx_data_in),
        .pop (rx_pop),  .dout(rx_data_out),
        .empty(rx_empty), .full(rx_full), .level()
    );

    // --- baud + engines ---
    logic tick_x16;
    uart_baud_gen u_baud (.clk, .rst_n, .baud_div(baud_div_q), .tick_x16(tick_x16));

    uart_tx u_tx (
        .clk, .rst_n, .tick_x16,
        .tx_en(tx_en_q),
        .fifo_empty(tx_empty),
        .fifo_data (tx_data_out),
        .fifo_pop  (tx_pop),
        .txd       (txd),
        .busy      ()
    );

    logic        rx_byte_valid, rx_frame_err;
    logic [7:0]  rx_byte_data;
    uart_rx u_rx (
        .clk, .rst_n, .tick_x16,
        .rx_en(rx_en_q),
        .rxd(rxd),
        .byte_valid(rx_byte_valid),
        .byte_data (rx_byte_data),
        .frame_err (rx_frame_err)
    );

    // RX -> FIFO push with overrun detect
    assign rx_push    = rx_byte_valid && !rx_full;
    assign rx_data_in = rx_byte_data;

    // --- bus decode (declared early; strict tools like xsim require this) ---
    logic bus_we, bus_re;
    assign bus_we = mem_valid && (mem_wstrb != 4'b0000);
    assign bus_re = mem_valid && (mem_wstrb == 4'b0000);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            frame_err_sticky <= 1'b0;
            overrun_sticky   <= 1'b0;
        end else begin
            if (rx_byte_valid && rx_frame_err) frame_err_sticky <= 1'b1;
            if (rx_byte_valid && rx_full)      overrun_sticky   <= 1'b1;
            if (bus_we && mem_addr[7:2] == 6'h02 && mem_wdata[5])  // CTRL.CLR_ERR
                {frame_err_sticky, overrun_sticky} <= 2'b00;
        end
    end

    logic [31:0] status_word, ctrl_word;
    assign status_word = {26'd0, overrun_sticky, frame_err_sticky,
                          rx_full, rx_empty, tx_full, tx_empty};
    assign ctrl_word   = {26'd0, 1'b0, err_int_en_q, rx_int_en_q,
                          tx_int_en_q, rx_en_q, tx_en_q};

    // TX push on write to DATA
    assign tx_push    = bus_we && (mem_addr[7:2] == 6'h00) && !tx_full;
    assign tx_data_in = mem_wdata[7:0];

    // RX pop on read to DATA (single-cycle — handled by mem_ready timing below)
    assign rx_pop = bus_re && (mem_addr[7:2] == 6'h00) && !rx_empty;

    // CTRL / BAUD writes
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            baud_div_q   <= RST_BAUD_DIV;
            tx_en_q      <= 1'b1;
            rx_en_q      <= 1'b1;
            tx_int_en_q  <= 1'b0;
            rx_int_en_q  <= 1'b0;
            err_int_en_q <= 1'b0;
        end else if (bus_we) begin
            case (mem_addr[7:2])
                6'h02: begin // CTRL
                    tx_en_q      <= mem_wdata[0];
                    rx_en_q      <= mem_wdata[1];
                    tx_int_en_q  <= mem_wdata[2];
                    rx_int_en_q  <= mem_wdata[3];
                    err_int_en_q <= mem_wdata[4];
                    // bit 5 CLR_ERR handled above
                end
                6'h03: baud_div_q <= mem_wdata[15:0]; // BAUD_DIV
                default: ;
            endcase
        end
    end

    // read mux + ready (1-cycle combinational)
    always_comb begin
        unique case (mem_addr[7:2])
            6'h00: mem_rdata = {24'd0, rx_data_out};
            6'h01: mem_rdata = status_word;
            6'h02: mem_rdata = ctrl_word;
            6'h03: mem_rdata = {16'd0, baud_div_q};
            default: mem_rdata = 32'd0;
        endcase
    end
    assign mem_ready = mem_valid;  // always ready next cycle (combinational)

    // --- IRQ ---
    assign irq = (tx_int_en_q  &  tx_empty) |
                 (rx_int_en_q  & ~rx_empty) |
                 (err_int_en_q & (frame_err_sticky | overrun_sticky));

    // -------------------------------------------------------------------
    // SVA assertions — simulation only.  Guarded so synthesis tools skip.
    // These catch protocol/state-machine violations that stay silent in
    // ordinary simulation runs (the kind of bugs that show up only on the
    // board at 3am).
    // -------------------------------------------------------------------
`ifndef SYNTHESIS
`ifndef VERILATOR
    // (SVA properties use $rose / |=> / disable-iff — xsim/Questa only.)
    // A1: UART TX line must idle high whenever the TX FSM is in S_IDLE.
    property p_tx_idle_high;
        @(posedge clk) disable iff (!rst_n)
        (u_tx.state == 2'd0) |-> (txd == 1'b1);
    endproperty
    a_tx_idle_high: assert property (p_tx_idle_high)
        else $error("[SVA] TX line driven low while TX FSM is idle");

    // A2: FIFO push is always gated by !full.  If this ever fires, upstream
    //     logic dropped a byte silently.
    a_tx_no_overflow: assert property (
        @(posedge clk) disable iff (!rst_n) !(tx_push && tx_full))
        else $error("[SVA] TX FIFO push asserted while FIFO is full");

    // A3: RX push is gated by !full; the overrun-sticky bit tracks drops.
    //     If rx_push&&rx_full ever fires, the rx_push logic is broken.
    a_rx_no_overflow: assert property (
        @(posedge clk) disable iff (!rst_n) !(rx_push && rx_full))
        else $error("[SVA] RX FIFO push asserted while FIFO is full");

    // A4: CLR_ERR: writing CTRL with bit[5]=1 clears both sticky bits by
    //     the next cycle (barring a coincident new error).
    a_clr_err: assert property (
        @(posedge clk) disable iff (!rst_n)
        (bus_we && mem_addr[7:2] == 6'h02 && mem_wdata[5] && !rx_byte_valid)
        |=> (!frame_err_sticky && !overrun_sticky))
        else $error("[SVA] CLR_ERR did not clear sticky error bits");

    // A5: rx_byte_valid from the RX engine must be a 1-cycle pulse.
    a_rx_pulse: assert property (
        @(posedge clk) disable iff (!rst_n)
        $rose(u_rx.byte_valid) |=> !u_rx.byte_valid)
        else $error("[SVA] rx byte_valid should be a 1-cycle pulse");
`endif  // !VERILATOR
`endif  // !SYNTHESIS
endmodule
