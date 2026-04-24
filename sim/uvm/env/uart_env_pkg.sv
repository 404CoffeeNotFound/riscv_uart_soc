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

        // Mode flag:
        //   1 (default)  block-level — AXI agent drives UART.DATA; scoreboard
        //                does strict expected-vs-observed byte matching.
        //   0            SoC level   — there is no external AXI master to
        //                watch.  The scoreboard just accumulates the serial
        //                output into txd_all so tests can grep for signatures.
        bit match_mode = 1'b1;

        uvm_analysis_imp_axi  #(axi_lite_item, uart_scoreboard) axi_in;
        uvm_analysis_imp_uart #(uart_item,     uart_scoreboard) uart_in;

        bit [7:0]     exp_q [$];  // bytes written to DATA, awaiting observation on txd
        int unsigned  n_ok;
        int unsigned  n_mismatch;
        string        txd_all;    // every observed byte, appended (for pattern grep)

        function new(string name, uvm_component parent);
            super.new(name, parent);
            axi_in  = new("axi_in",  this);
            uart_in = new("uart_in", this);
        endfunction

        function void build_phase(uvm_phase phase);
            void'(uvm_config_db#(bit)::get(this, "", "match_mode", match_mode));
        endfunction

        // String helper — SV's string type has no `find`.
        function int str_find(string hay, string needle);
            int h = hay.len();
            int n = needle.len();
            if (n == 0 || h < n) return -1;
            for (int i = 0; i <= h - n; i++)
                if (hay.substr(i, i + n - 1) == needle) return i;
            return -1;
        endfunction

        function bit contains(string needle);
            return str_find(txd_all, needle) != -1;
        endfunction

        // AXI monitor input — pick out writes to UART.DATA (match mode only)
        function void write_axi(axi_lite_item tr);
            if (!match_mode) return;
            if (tr.dir == AXIL_WRITE && tr.addr[7:2] == DATA_REG_IDX && tr.wstrb[0]) begin
                exp_q.push_back(tr.data[7:0]);
                `uvm_info("SB_TX_EXP",
                    $sformatf("expecting txd=0x%02h (AXI write @ 0x%08h)",
                              tr.data[7:0], tr.addr), UVM_HIGH)
            end
        endfunction

        // UART monitor input — always accumulates into txd_all; compares
        // against exp_q only in match_mode.
        function void write_uart(uart_item tr);
            bit [7:0] expected;
            // Append raw byte to the tail buffer
            txd_all = {txd_all, string'(tr.data)};

            if (!match_mode) begin
                n_ok++;
                return;
            end

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
            `uvm_info("SB_SUM",
                $sformatf("mode=%s OK=%0d MISMATCH=%0d PENDING=%0d txd_len=%0d",
                          match_mode ? "MATCH" : "LOG",
                          n_ok, n_mismatch, exp_q.size(), txd_all.len()),
                UVM_NONE)
            if (n_mismatch > 0)
                `uvm_error("SB_SUM", "scoreboard saw data mismatches")
            if (match_mode && exp_q.size() != 0)
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
        bit              has_axi_agent = 1'b1;

        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        function void build_phase(uvm_phase phase);
            void'(uvm_config_db#(bit)::get(this, "", "has_axi_agent", has_axi_agent));
            if (has_axi_agent)
                axi_agt = axi_lite_agent::type_id::create("axi_agt", this);
            uart_agt = uart_agent     ::type_id::create("uart_agt", this);
            sb       = uart_scoreboard::type_id::create("sb",       this);
        endfunction

        function void connect_phase(uvm_phase phase);
            if (has_axi_agent)
                axi_agt.mon.ap.connect(sb.axi_in);
            uart_agt.mon.ap.connect(sb.uart_in);
        endfunction
    endclass
endpackage
