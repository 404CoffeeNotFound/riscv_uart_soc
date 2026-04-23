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
        function new(string name, uvm_component parent); super.new(name, parent); endfunction

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
                bins low   = {[8'h00:8'h1F]};
                bins ascii = {[8'h20:8'h7E]};
                bins high  = {[8'h7F:8'hFF]};
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
    class uart_scoreboard extends uvm_component;
        `uvm_component_utils(uart_scoreboard)
        uvm_analysis_imp #(uart_item, uart_scoreboard) in;
        int unsigned n_bytes;
        function new(string name, uvm_component parent);
            super.new(name, parent);
            in = new("in", this);
        endfunction
        function void write(uart_item tr);
            n_bytes++;
            `uvm_info("SB", $sformatf("observed byte #%0d 0x%02h err=%0b",
                                      n_bytes, tr.data, tr.inject_frame_err), UVM_MEDIUM)
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
            agt.mon.ap.connect(sb.in);
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

    // ----------------------- basic sequence -----------------------
    class uart_basic_seq extends uvm_sequence #(uart_item);
        `uvm_object_utils(uart_basic_seq)
        rand int unsigned n = 10;
        function new(string name = "uart_basic_seq"); super.new(name); endfunction
        task body();
            for (int i = 0; i < n; i++) begin
                uart_item tr = uart_item::type_id::create("tr");
                start_item(tr);
                assert(tr.randomize());
                finish_item(tr);
            end
        endtask
    endclass
endpackage
