// uart_pkg.sv — UART serial-line UVC.
// Reusable — no test / DUT awareness beyond the 8N1 line-level protocol.
// The driver injects bytes on rxd; the monitor captures bytes from txd.
`timescale 1ns/1ps

package uart_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // -------------------- transaction --------------------
    class uart_item extends uvm_sequence_item;
        rand bit [7:0]     data;
        rand bit           inject_frame_err;
        rand int unsigned  gap_bits;
        constraint c_default {
            soft inject_frame_err == 0;
            soft gap_bits inside {[1:8]};
        }
        `uvm_object_utils_begin(uart_item)
            `uvm_field_int(data, UVM_DEFAULT)
            `uvm_field_int(inject_frame_err, UVM_DEFAULT)
            `uvm_field_int(gap_bits, UVM_DEFAULT)
        `uvm_object_utils_end
        function new(string name = "uart_item"); super.new(name); endfunction
    endclass

    // -------------------- driver (drives rxd) --------------------
    class uart_driver extends uvm_driver#(uart_item);
        `uvm_component_utils(uart_driver)
        virtual uart_if vif;

        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        function void build_phase(uvm_phase phase);
            if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
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
            vif.rxd = 1'b0; repeat (CYC) @(posedge vif.clk);  // start
            for (int i = 0; i < 8; i++) begin
                vif.rxd = tr.data[i]; repeat (CYC) @(posedge vif.clk);
            end
            vif.rxd = tr.inject_frame_err ? 1'b0 : 1'b1;      // stop or err
            repeat (CYC) @(posedge vif.clk);
            vif.rxd = 1'b1;
            repeat (tr.gap_bits * CYC) @(posedge vif.clk);
        endtask
    endclass

    // -------------------- monitor (observes txd) --------------------
    class uart_monitor extends uvm_monitor;
        `uvm_component_utils(uart_monitor)
        virtual uart_if vif;
        uvm_analysis_port #(uart_item) ap;

        covergroup cg with function sample(uart_item tr);
            option.per_instance = 1;
            cp_data : coverpoint tr.data {
                bins zero  = {8'h00};
                bins low   = {[8'h01:8'h1F]};
                bins ascii = {[8'h20:8'h7E]};
                bins high  = {[8'h7F:8'hFE]};
                bins ff    = {8'hFF};
            }
            cp_err  : coverpoint tr.inject_frame_err;
            cx      : cross cp_data, cp_err;
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
            cg = new;
        endfunction

        function void build_phase(uvm_phase phase);
            if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "uart_if not set")
        endfunction

        task run_phase(uvm_phase phase);
            int CYC = vif.CYC_PER_BIT;
            forever begin
                uart_item tr;
                @(negedge vif.txd);                             // start bit
                repeat (CYC + CYC/2) @(posedge vif.clk);         // to middle of bit 0
                tr = uart_item::type_id::create("tr");
                for (int i = 0; i < 8; i++) begin
                    tr.data[i] = vif.txd;
                    repeat (CYC) @(posedge vif.clk);
                end
                tr.inject_frame_err = (vif.txd == 1'b0);
                ap.write(tr);
                cg.sample(tr);
            end
        endtask
    endclass

    typedef uvm_sequencer#(uart_item) uart_sequencer;

    // -------------------- agent --------------------
    class uart_agent extends uvm_agent;
        `uvm_component_utils(uart_agent)
        uart_driver    drv;
        uart_monitor   mon;
        uart_sequencer seqr;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            mon = uart_monitor::type_id::create("mon", this);
            if (get_is_active() == UVM_ACTIVE) begin
                drv  = uart_driver   ::type_id::create("drv",  this);
                seqr = uart_sequencer::type_id::create("seqr", this);
            end
        endfunction
        function void connect_phase(uvm_phase phase);
            if (get_is_active() == UVM_ACTIVE)
                drv.seq_item_port.connect(seqr.seq_item_export);
        endfunction
    endclass

    // -------------------- sequence library --------------------
    class uart_random_seq extends uvm_sequence#(uart_item);
        `uvm_object_utils(uart_random_seq)
        rand int unsigned n = 10;
        function new(string name = "uart_random_seq"); super.new(name); endfunction
        task body();
            for (int i = 0; i < n; i++) begin
                uart_item tr = uart_item::type_id::create("tr");
                start_item(tr);
                if (!tr.randomize()) `uvm_fatal("RAND","randomize failed")
                finish_item(tr);
            end
        endtask
    endclass

    class uart_corner_seq extends uvm_sequence#(uart_item);
        `uvm_object_utils(uart_corner_seq)
        function new(string name = "uart_corner_seq"); super.new(name); endfunction
        task body();
            byte unsigned pats[] = '{8'h00, 8'hFF, 8'h55, 8'hAA,
                                      8'h01, 8'h80, 8'h7F, 8'hFE};
            foreach (pats[i]) begin
                uart_item tr = uart_item::type_id::create("tr");
                start_item(tr);
                if (!tr.randomize() with { data == pats[i]; inject_frame_err == 0; })
                    `uvm_fatal("RAND","randomize failed")
                finish_item(tr);
            end
        endtask
    endclass

    // Inject exactly one byte on rxd with stop=0 — used by the frame-error
    // directed test to trigger the DUT's sticky FRAME_ERR bit.
    class uart_one_err_seq extends uvm_sequence#(uart_item);
        `uvm_object_utils(uart_one_err_seq)
        rand bit [7:0] data_val = 8'h5A;
        function new(string name = "uart_one_err_seq"); super.new(name); endfunction
        task body();
            uart_item tr = uart_item::type_id::create("tr");
            start_item(tr);
            if (!tr.randomize() with {
                data == data_val;
                inject_frame_err == 1;
                gap_bits == 4;          // give the RX engine idle time to settle
            }) `uvm_fatal("RAND","randomize failed")
            finish_item(tr);
        endtask
    endclass
endpackage
