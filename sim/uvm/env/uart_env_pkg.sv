// uart_env_pkg.sv — test-bench environment: AXI4-Lite master agent +
// UART serial agent + scoreboard.  The scoreboard watches the AXI monitor
// and the UART monitor and checks that each byte the AXI master writes to
// the UART.DATA register reappears on the serial txd line.
`timescale 1ns/1ps

package uart_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axi_lite_pkg::*;
    import uart_pkg::*;

    // Analysis imp declarations so we can have two typed write() functions.
    `uvm_analysis_imp_decl(_axi)
    `uvm_analysis_imp_decl(_uart)

    // -------------------- scoreboard --------------------
    class uart_scoreboard extends uvm_component;
        `uvm_component_utils(uart_scoreboard)

        // UART register offset of the DATA register.
        // (Byte-aligned; addr[7:2] == 6'h00 means offset 0x00.)
        localparam logic [5:0] DATA_REG_IDX = 6'h00;

        uvm_analysis_imp_axi  #(axi_lite_item, uart_scoreboard) axi_in;
        uvm_analysis_imp_uart #(uart_item,     uart_scoreboard) uart_in;

        bit [7:0]     exp_q [$];  // bytes written to DATA, awaiting observation on txd
        int unsigned  n_ok;
        int unsigned  n_mismatch;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            axi_in  = new("axi_in",  this);
            uart_in = new("uart_in", this);
        endfunction

        // AXI monitor input — pick out writes to UART.DATA
        function void write_axi(axi_lite_item tr);
            if (tr.dir == AXIL_WRITE && tr.addr[7:2] == DATA_REG_IDX && tr.wstrb[0]) begin
                exp_q.push_back(tr.data[7:0]);
                `uvm_info("SB_TX_EXP",
                    $sformatf("expecting txd=0x%02h (AXI write @ 0x%08h)",
                              tr.data[7:0], tr.addr), UVM_HIGH)
            end
        endfunction

        // UART monitor input — compare against oldest expectation
        function void write_uart(uart_item tr);
            bit [7:0] expected;
            if (exp_q.size() == 0) begin
                `uvm_error("SB_ORPHAN",
                    $sformatf("txd observed 0x%02h with no matching AXI write", tr.data))
                n_mismatch++;
                return;
            end
            expected = exp_q.pop_front();
            if (expected !== tr.data) begin
                `uvm_error("SB_MISMATCH",
                    $sformatf("txd 0x%02h != expected 0x%02h", tr.data, expected))
                n_mismatch++;
            end else begin
                n_ok++;
                `uvm_info("SB_OK",
                    $sformatf("#%0d match 0x%02h (err_on_stop=%0b)",
                              n_ok, tr.data, tr.inject_frame_err), UVM_MEDIUM)
            end
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("SB_SUM", $sformatf("OK=%0d MISMATCH=%0d PENDING=%0d",
                                          n_ok, n_mismatch, exp_q.size()), UVM_NONE)
            if (n_mismatch > 0)
                `uvm_error("SB_SUM", "scoreboard saw data mismatches")
            // n_ok == 0 is OK for tests that exercise only the RX path or
            // only register-level behavior (e.g. frame-error directed test).
            if (exp_q.size() != 0)
                `uvm_error("SB_SUM",
                    $sformatf("%0d expected byte(s) never observed on txd", exp_q.size()))
        endfunction
    endclass

    // -------------------- env --------------------
    class uart_env extends uvm_env;
        `uvm_component_utils(uart_env)
        axi_lite_agent   axi_agt;
        uart_agent       uart_agt;
        uart_scoreboard  sb;

        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        function void build_phase(uvm_phase phase);
            axi_agt  = axi_lite_agent  ::type_id::create("axi_agt",  this);
            uart_agt = uart_agent      ::type_id::create("uart_agt", this);
            sb       = uart_scoreboard ::type_id::create("sb",       this);
        endfunction

        function void connect_phase(uvm_phase phase);
            axi_agt .mon.ap.connect(sb.axi_in);
            uart_agt.mon.ap.connect(sb.uart_in);
        endfunction
    endclass
endpackage
