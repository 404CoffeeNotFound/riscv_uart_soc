`timescale 1ns/1ps
// uart_uvc_pkg.sv — minimal UVM UVC for the UART peripheral.
// Transaction / driver / monitor / sequencer / agent / base sequence / env / scoreboard.
// Functional coverage lives in the monitor.
//
// Expand per Week 3 plan:
//   - sequences: single byte, burst, max-rate, frame-error, overrun, baud-sweep
//   - add coverage bins for all STATUS/CTRL bits and error combos
package uart_uvc_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // ----------------------- transaction -----------------------
    class uart_item extends uvm_sequence_item;
        rand bit [7:0] data;
        rand bit       inject_frame_err;  // driver will not send stop=1
        rand int unsigned gap_bits;       // idle bits after this byte
        constraint c_default {
            soft inject_frame_err == 0;
            soft gap_bits inside {[0:8]};
        }
        `uvm_object_utils_begin(uart_item)
            `uvm_field_int(data, UVM_DEFAULT)
            `uvm_field_int(inject_frame_err, UVM_DEFAULT)
            `uvm_field_int(gap_bits, UVM_DEFAULT)
        `uvm_object_utils_end
        function new(string name = "uart_item"); super.new(name); endfunction
    endclass

    // ----------------------- driver -----------------------
    class uart_driver extends uvm_driver #(uart_item);
        `uvm_component_utils(uart_driver)
        virtual uart_if vif;
        uvm_analysis_port #(uart_item) ap_sent;  // what we actually transmitted

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap_sent = new("ap_sent", this);
        endfunction

        function void build_phase(uvm_phase phase);
            if (!uvm_config_db#(virtual uart_if)::get(this,"","vif",vif))
                `uvm_fatal("NOVIF", "uart_if not set")
        endfunction

        task run_phase(uvm_phase phase);
            vif.rxd = 1'b1;
            forever begin
                uart_item tr;
                seq_item_port.get_next_item(tr);
                send_byte(tr);
                ap_sent.write(tr);
                seq_item_port.item_done();
            end
        endtask

        task send_byte(uart_item tr);
            int CYC = vif.CYC_PER_BIT;
            // start bit
            vif.rxd = 1'b0; repeat (CYC) @(posedge vif.clk);
            // 8 data bits LSB first
            for (int i = 0; i < 8; i++) begin
                vif.rxd = tr.data[i]; repeat (CYC) @(posedge vif.clk);
            end
            // stop bit (or injected error)
            vif.rxd = tr.inject_frame_err ? 1'b0 : 1'b1;
            repeat (CYC) @(posedge vif.clk);
            vif.rxd = 1'b1;
            // gap
            repeat (tr.gap_bits * CYC) @(posedge vif.clk);
        endtask
    endclass

    // ----------------------- monitor -----------------------
    class uart_monitor extends uvm_monitor;
        `uvm_component_utils(uart_monitor)
        virtual uart_if vif;
        uvm_analysis_port #(uart_item) ap;

        // functional coverage
        covergroup cg with function sample(uart_item tr);
            option.per_instance = 1;
            cp_data    : coverpoint tr.data {
                bins zero  = {8'h00};
                bins low   = {[8'h01:8'h1F]};
                bins ascii = {[8'h20:8'h7E]};
                bins high  = {[8'h7F:8'hFE]};
                bins ff    = {8'hFF};
            }
            cp_err     : coverpoint tr.inject_frame_err;
            cp_x_data_err : cross cp_data, cp_err;
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
            cg = new;
        endfunction

        function void build_phase(uvm_phase phase);
            if (!uvm_config_db#(virtual uart_if)::get(this,"","vif",vif))
                `uvm_fatal("NOVIF", "uart_if not set")
        endfunction

        task run_phase(uvm_phase phase);
            int CYC = vif.CYC_PER_BIT;
            forever begin
                uart_item tr;
                // wait for start bit
                @(negedge vif.txd);
                repeat (CYC + CYC/2) @(posedge vif.clk);  // go to middle of bit 0
                tr = uart_item::type_id::create("tr");
                for (int i = 0; i < 8; i++) begin
                    tr.data[i] = vif.txd;
                    repeat (CYC) @(posedge vif.clk);
                end
                tr.inject_frame_err = (vif.txd == 1'b0);  // stop-bit check
                ap.write(tr);
                cg.sample(tr);
            end
        endtask
    endclass

    // ----------------------- sequencer -----------------------
    typedef uvm_sequencer#(uart_item) uart_sequencer;

    // ----------------------- agent -----------------------
    class uart_agent extends uvm_agent;
        `uvm_component_utils(uart_agent)
        uart_driver    drv;
        uart_monitor   mon;
        uart_sequencer seqr;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            mon  = uart_monitor::type_id::create("mon", this);
            if (get_is_active() == UVM_ACTIVE) begin
                drv  = uart_driver::type_id::create("drv", this);
                seqr = uart_sequencer::type_id::create("seqr", this);
            end
        endfunction
        function void connect_phase(uvm_phase phase);
            if (get_is_active() == UVM_ACTIVE)
                drv.seq_item_port.connect(seqr.seq_item_export);
        endfunction
    endclass

    // ----------------------- scoreboard -----------------------
    //
    // Compares bytes the driver actually transmitted on rxd with what the
    // monitor observed on txd after the DUT round-tripped them via the
    // loopback BFM in the testbench.  Inequality is a real RTL bug.
    //
    // NOTE on inject_frame_err: a byte with stop=0 still gets pushed to the
    // RX FIFO (with frame_err_sticky set).  The loopback re-transmits it
    // with a proper stop=1, so the TX-side observation won't have the err
    // flag set — we only compare the DATA field.
    // -------------------------------------------------------------------
    class uart_scoreboard extends uvm_component;
        `uvm_component_utils(uart_scoreboard)
        uvm_tlm_analysis_fifo #(uart_item) sent_fifo;
        uvm_tlm_analysis_fifo #(uart_item) recv_fifo;

        int unsigned n_ok;
        int unsigned n_mismatch;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            sent_fifo = new("sent_fifo", this);
            recv_fifo = new("recv_fifo", this);
        endfunction

        task run_phase(uvm_phase phase);
            uart_item s, r;
            forever begin
                sent_fifo.get(s);
                recv_fifo.get(r);
                if (s.data !== r.data) begin
                    n_mismatch++;
                    `uvm_error("SB_MISMATCH",
                        $sformatf("sent=0x%02h recv=0x%02h (err_inj=%0b observed_err=%0b)",
                                  s.data, r.data, s.inject_frame_err, r.inject_frame_err))
                end else begin
                    n_ok++;
                    `uvm_info("SB_OK",
                        $sformatf("#%0d match 0x%02h (err_inj=%0b)",
                                  n_ok, s.data, s.inject_frame_err), UVM_MEDIUM)
                end
            end
        endtask

        function void report_phase(uvm_phase phase);
            `uvm_info("SB_SUM", $sformatf("OK=%0d MISMATCH=%0d", n_ok, n_mismatch),
                      UVM_NONE)
            if (n_mismatch > 0)
                `uvm_error("SB_SUM", "scoreboard saw mismatches")
            if (n_ok == 0)
                `uvm_error("SB_SUM", "scoreboard saw zero matches — sequence or loopback broken")
        endfunction
    endclass

    // ----------------------- env -----------------------
    class uart_env extends uvm_env;
        `uvm_component_utils(uart_env)
        uart_agent       agt;
        uart_scoreboard  sb;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            agt = uart_agent    ::type_id::create("agt", this);
            sb  = uart_scoreboard::type_id::create("sb",  this);
        endfunction
        function void connect_phase(uvm_phase phase);
            agt.drv.ap_sent.connect(sb.sent_fifo.analysis_export);
            agt.mon.ap     .connect(sb.recv_fifo.analysis_export);
        endfunction
    endclass

    // ----------------------- base test -----------------------
    class uart_base_test extends uvm_test;
        `uvm_component_utils(uart_base_test)
        uart_env env;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            env = uart_env::type_id::create("env", this);
        endfunction
    endclass

    // ----------------------- sequences -----------------------
    class uart_basic_seq extends uvm_sequence #(uart_item);
        `uvm_object_utils(uart_basic_seq)
        rand int unsigned n = 10;
        function new(string name = "uart_basic_seq"); super.new(name); endfunction
        task body();
            for (int i = 0; i < n; i++) begin
                uart_item tr = uart_item::type_id::create("tr");
                start_item(tr);
                if (!tr.randomize()) `uvm_fatal("RAND", "randomize failed")
                finish_item(tr);
            end
        endtask
    endclass

    // Back-to-back bytes (zero inter-byte gap) — stresses the TX FIFO depth
    // and the RX engine's start-bit re-detection after a stop bit.
    class uart_burst_seq extends uvm_sequence #(uart_item);
        `uvm_object_utils(uart_burst_seq)
        rand int unsigned n = 20;
        function new(string name = "uart_burst_seq"); super.new(name); endfunction
        task body();
            for (int i = 0; i < n; i++) begin
                uart_item tr = uart_item::type_id::create("tr");
                start_item(tr);
                if (!tr.randomize() with {
                    inject_frame_err == 0;
                    gap_bits == 0;
                }) `uvm_fatal("RAND", "randomize failed")
                finish_item(tr);
            end
        endtask
    endclass

    // Corner-case patterns: 0x00, 0xFF, 0x55, 0xAA — flips every bit position.
    class uart_corner_seq extends uvm_sequence #(uart_item);
        `uvm_object_utils(uart_corner_seq)
        function new(string name = "uart_corner_seq"); super.new(name); endfunction
        task body();
            byte unsigned patterns[] = '{8'h00, 8'hFF, 8'h55, 8'hAA,
                                          8'h01, 8'h80, 8'h7F, 8'hFE};
            foreach (patterns[i]) begin
                uart_item tr = uart_item::type_id::create("tr");
                start_item(tr);
                if (!tr.randomize() with {
                    data == patterns[i];
                    inject_frame_err == 0;
                    gap_bits inside {[1:4]};
                }) `uvm_fatal("RAND", "randomize failed")
                finish_item(tr);
            end
        endtask
    endclass

    // TODO(err_test): proper frame-error verification requires a UVM bus
    // agent that can poll STATUS and write CLR_ERR at arbitrary points.
    // Scoreboard data-equality is fundamentally unreliable for err bytes
    // because after a stop=0, the RX engine may re-interpret the trailing
    // zero as the next start bit, causing byte-boundary slippage.
    //
    // For now, frame-error coverage is handled via SVA (A4 in uart_top.sv)
    // and directed bus writes will be added alongside the bus agent in
    // the next UVM milestone.

    // ----------------------- concrete tests -----------------------
    class uart_basic_test extends uart_base_test;
        `uvm_component_utils(uart_basic_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        task run_phase(uvm_phase phase);
            uart_basic_seq   s_basic  = uart_basic_seq ::type_id::create("s_basic");
            uart_corner_seq  s_corner = uart_corner_seq::type_id::create("s_corner");
            uart_burst_seq   s_burst  = uart_burst_seq ::type_id::create("s_burst");
            s_basic.n = 8;
            s_burst.n = 16;

            phase.raise_objection(this);
            `uvm_info("TEST", "running basic -> corner -> burst", UVM_LOW)
            s_basic .start(env.agt.seqr);
            s_corner.start(env.agt.seqr);
            s_burst .start(env.agt.seqr);
            // drain: allow last bytes to round-trip through DUT TX + monitor
            #(5_000_000);   // 5 ms @ 1ns timescale
            phase.drop_objection(this);
        endtask
    endclass

endpackage
