// soc_top.sv — PicoRV32 + 16KB BRAM + UART + GPIO(LEDs) on Zybo Z7-20.
// PicoRV32 native bus is routed to a simple address decoder.
`timescale 1ns/1ps

module soc_top #(
    parameter int SYS_CLK_HZ  = 50_000_000,
    parameter int BRAM_WORDS  = 4096,        // 16 KB
    parameter     BRAM_INIT   = "hello.mem"  // loaded at elab; empty string = none
)(
    input  logic        sys_clk_125,
    input  logic        rst_btn,    // BTN0 (active-high on Zybo)
    output logic [3:0]  led,
    input  logic        uart_rx,
    output logic        uart_tx
);
    // -------------------------------------------------------------------
    // Clock / reset
    //   Use the 125 MHz input directly for now.  Replace with MMCM in Vivado
    //   (Clocking Wizard IP) before Week 5 if timing requires.
    // -------------------------------------------------------------------
    logic clk;
    assign clk = sys_clk_125;

    logic rst_n;
    logic [3:0] rst_sync;
    always_ff @(posedge clk) rst_sync <= {rst_sync[2:0], ~rst_btn};
    assign rst_n = rst_sync[3];

    // -------------------------------------------------------------------
    // PicoRV32 core
    // -------------------------------------------------------------------
    logic        mem_valid, mem_instr, mem_ready;
    logic [31:0] mem_addr, mem_wdata, mem_rdata;
    logic [3:0]  mem_wstrb;
    logic [31:0] irq;

    assign irq = {31'd0, uart_irq};
    logic uart_irq;

    picorv32 #(
        .ENABLE_COUNTERS   (1),
        .ENABLE_MUL        (0),
        .ENABLE_DIV        (0),
        .ENABLE_IRQ        (1),
        .PROGADDR_RESET    (32'h0000_0000),
        .PROGADDR_IRQ      (32'h0000_0010),
        .STACKADDR         (32'h0000_4000),
        .BARREL_SHIFTER    (1),
        .COMPRESSED_ISA    (0),
        .CATCH_MISALIGN    (1),
        .CATCH_ILLINSN     (1)
    ) u_cpu (
        .clk       (clk),
        .resetn    (rst_n),
        .trap      (),
        .mem_valid (mem_valid),
        .mem_instr (mem_instr),
        .mem_ready (mem_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata),
        .mem_la_read (), .mem_la_write (), .mem_la_addr (),
        .mem_la_wdata (), .mem_la_wstrb (),
        .pcpi_valid (), .pcpi_insn (), .pcpi_rs1 (), .pcpi_rs2 (),
        .pcpi_wr (1'b0), .pcpi_rd (32'd0), .pcpi_wait (1'b0), .pcpi_ready (1'b0),
        .irq (irq),
        .eoi (),
        .trace_valid (), .trace_data ()
    );

    // -------------------------------------------------------------------
    // Address decode
    //   BRAM  0x0000_0000 .. 0x0000_3FFF   (when addr[31:24] == 0x00)
    //   UART  0x1000_0000 .. 0x1000_00FF   (when addr[31:24] == 0x10)
    //   GPIO  0x2000_0000 .. 0x2000_000F   (when addr[31:24] == 0x20)
    // -------------------------------------------------------------------
    logic sel_bram, sel_uart, sel_gpio;
    assign sel_bram = mem_valid && (mem_addr[31:24] == 8'h00);
    assign sel_uart = mem_valid && (mem_addr[31:24] == 8'h10);
    assign sel_gpio = mem_valid && (mem_addr[31:24] == 8'h20);

    // -------------------------------------------------------------------
    // BRAM  (simple, 1-cycle latency)
    // -------------------------------------------------------------------
    logic [31:0] bram [BRAM_WORDS];
    logic [31:0] bram_rdata;
    logic        bram_ready;
    logic [$clog2(BRAM_WORDS)-1:0] bram_idx;
    assign bram_idx = mem_addr[$clog2(BRAM_WORDS)+1:2];

    initial if (BRAM_INIT != "") $readmemh(BRAM_INIT, bram);

    always_ff @(posedge clk) begin
        if (sel_bram) begin
            if (mem_wstrb[0]) bram[bram_idx][ 7: 0] <= mem_wdata[ 7: 0];
            if (mem_wstrb[1]) bram[bram_idx][15: 8] <= mem_wdata[15: 8];
            if (mem_wstrb[2]) bram[bram_idx][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) bram[bram_idx][31:24] <= mem_wdata[31:24];
            bram_rdata <= bram[bram_idx];
        end
        bram_ready <= sel_bram;
    end

    // -------------------------------------------------------------------
    // UART
    // -------------------------------------------------------------------
    logic [31:0] uart_rdata;
    logic        uart_ready;
    uart_top #(.CLK_FREQ_HZ(SYS_CLK_HZ), .DEFAULT_BAUD(115200)) u_uart (
        .clk, .rst_n,
        .mem_valid (sel_uart),
        .mem_ready (uart_ready),
        .mem_addr  (mem_addr[7:0]),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (uart_rdata),
        .rxd       (uart_rx),
        .txd       (uart_tx),
        .irq       (uart_irq)
    );

    // -------------------------------------------------------------------
    // GPIO: 4-bit LED register
    // -------------------------------------------------------------------
    logic [31:0] gpio_rdata;
    logic        gpio_ready;
    logic [3:0]  led_q;
    always_ff @(posedge clk) begin
        if (!rst_n) led_q <= 4'd0;
        else if (sel_gpio && |mem_wstrb) led_q <= mem_wdata[3:0];
        gpio_ready <= sel_gpio;
    end
    assign gpio_rdata = {28'd0, led_q};
    assign led = led_q;

    // -------------------------------------------------------------------
    // Response mux
    // -------------------------------------------------------------------
    always_comb begin
        mem_rdata = 32'd0;
        mem_ready = 1'b0;
        if (bram_ready)     begin mem_rdata = bram_rdata; mem_ready = 1'b1; end
        else if (uart_ready) begin mem_rdata = uart_rdata; mem_ready = 1'b1; end
        else if (gpio_ready) begin mem_rdata = gpio_rdata; mem_ready = 1'b1; end
    end
endmodule
