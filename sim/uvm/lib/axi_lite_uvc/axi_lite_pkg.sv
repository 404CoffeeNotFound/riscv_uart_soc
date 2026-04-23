// axi_lite_pkg.sv — AXI4-Lite UVC (master + monitor).
// Reusable library UVC — no test-specific knowledge.
`timescale 1ns/1ps

package axi_lite_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    typedef enum bit {AXIL_READ = 0, AXIL_WRITE = 1} axil_dir_e;

    // -------------------- transaction --------------------
    class axi_lite_item extends uvm_sequence_item;
        rand bit [31:0] addr;
        rand bit [31:0] data;         // write data (or captured read data)
        rand bit [3:0]  wstrb = 4'hF; // valid for writes
        rand axil_dir_e dir   = AXIL_WRITE;
             bit [1:0]  resp;         // BRESP / RRESP captured by driver

        constraint c_addr_aligned { addr[1:0] == 2'b00; }

        `uvm_object_utils_begin(axi_lite_item)
            `uvm_field_int(addr, UVM_DEFAULT)
            `uvm_field_int(data, UVM_DEFAULT)
            `uvm_field_int(wstrb, UVM_DEFAULT)
            `uvm_field_enum(axil_dir_e, dir, UVM_DEFAULT)
            `uvm_field_int(resp, UVM_DEFAULT)
        `uvm_object_utils_end

        function new(string name = "axi_lite_item"); super.new(name); endfunction

        function string convert2string();
            return $sformatf("%s addr=0x%08h data=0x%08h wstrb=%0h resp=%0d",
                             dir == AXIL_WRITE ? "WR" : "RD", addr, data, wstrb, resp);
        endfunction
    endclass

    // -------------------- master driver --------------------
    class axi_lite_master_driver extends uvm_driver#(axi_lite_item);
        `uvm_component_utils(axi_lite_master_driver)
        virtual axi_lite_if vif;

        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        function void build_phase(uvm_phase phase);
            if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "axi_lite_if not set")
        endfunction

        task idle_all();
            vif.awvalid <= 1'b0;
            vif.wvalid  <= 1'b0;
            vif.bready  <= 1'b0;
            vif.arvalid <= 1'b0;
            vif.rready  <= 1'b0;
            vif.awaddr  <= 32'd0;
            vif.awprot  <= 3'b000;
            vif.wdata   <= 32'd0;
            vif.wstrb   <= 4'd0;
            vif.araddr  <= 32'd0;
            vif.arprot  <= 3'b000;
        endtask

        task run_phase(uvm_phase phase);
            idle_all();
            wait (vif.aresetn === 1'b1);
            forever begin
                axi_lite_item tr;
                seq_item_port.get_next_item(tr);
                if (tr.dir == AXIL_WRITE) do_write(tr);
                else                      do_read(tr);
                seq_item_port.item_done();
            end
        endtask

        task do_write(axi_lite_item tr);
            @(posedge vif.aclk);
            vif.awaddr  <= tr.addr;
            vif.awprot  <= 3'b000;
            vif.awvalid <= 1'b1;
            vif.wdata   <= tr.data;
            vif.wstrb   <= tr.wstrb;
            vif.wvalid  <= 1'b1;
            vif.bready  <= 1'b1;
            fork
                begin : aw_ch
                    do @(posedge vif.aclk); while (!(vif.awvalid && vif.awready));
                    vif.awvalid <= 1'b0;
                end
                begin : w_ch
                    do @(posedge vif.aclk); while (!(vif.wvalid && vif.wready));
                    vif.wvalid <= 1'b0;
                end
            join
            do @(posedge vif.aclk); while (!(vif.bvalid && vif.bready));
            tr.resp = vif.bresp;
            vif.bready <= 1'b0;
        endtask

        task do_read(axi_lite_item tr);
            @(posedge vif.aclk);
            vif.araddr  <= tr.addr;
            vif.arprot  <= 3'b000;
            vif.arvalid <= 1'b1;
            vif.rready  <= 1'b1;
            do @(posedge vif.aclk); while (!(vif.arvalid && vif.arready));
            vif.arvalid <= 1'b0;
            do @(posedge vif.aclk); while (!(vif.rvalid && vif.rready));
            tr.data = vif.rdata;
            tr.resp = vif.rresp;
            vif.rready <= 1'b0;
        endtask
    endclass

    // -------------------- monitor --------------------
    class axi_lite_monitor extends uvm_monitor;
        `uvm_component_utils(axi_lite_monitor)
        virtual axi_lite_if vif;
        uvm_analysis_port #(axi_lite_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "axi_lite_if not set")
        endfunction

        task run_phase(uvm_phase phase);
            fork
                watch_writes();
                watch_reads();
            join
        endtask

        // Capture the write-data+addr pair and emit once B has landed.
        task watch_writes();
            forever begin
                axi_lite_item tr;
                bit [31:0] addr_q, data_q;
                bit [3:0]  strb_q;
                // wait for AW and W handshakes (either order)
                fork
                    begin
                        do @(posedge vif.aclk); while (!(vif.awvalid && vif.awready));
                        addr_q = vif.awaddr;
                    end
                    begin
                        do @(posedge vif.aclk); while (!(vif.wvalid && vif.wready));
                        data_q = vif.wdata;
                        strb_q = vif.wstrb;
                    end
                join
                // wait for B
                do @(posedge vif.aclk); while (!(vif.bvalid && vif.bready));
                tr = axi_lite_item::type_id::create("wr_tr");
                tr.dir   = AXIL_WRITE;
                tr.addr  = addr_q;
                tr.data  = data_q;
                tr.wstrb = strb_q;
                tr.resp  = vif.bresp;
                ap.write(tr);
            end
        endtask

        task watch_reads();
            forever begin
                axi_lite_item tr;
                bit [31:0] addr_q;
                do @(posedge vif.aclk); while (!(vif.arvalid && vif.arready));
                addr_q = vif.araddr;
                do @(posedge vif.aclk); while (!(vif.rvalid && vif.rready));
                tr = axi_lite_item::type_id::create("rd_tr");
                tr.dir  = AXIL_READ;
                tr.addr = addr_q;
                tr.data = vif.rdata;
                tr.resp = vif.rresp;
                ap.write(tr);
            end
        endtask
    endclass

    typedef uvm_sequencer#(axi_lite_item) axi_lite_sequencer;

    // -------------------- agent --------------------
    class axi_lite_agent extends uvm_agent;
        `uvm_component_utils(axi_lite_agent)
        axi_lite_master_driver drv;
        axi_lite_monitor       mon;
        axi_lite_sequencer     seqr;

        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        function void build_phase(uvm_phase phase);
            mon = axi_lite_monitor::type_id::create("mon", this);
            if (get_is_active() == UVM_ACTIVE) begin
                drv  = axi_lite_master_driver::type_id::create("drv",  this);
                seqr = axi_lite_sequencer    ::type_id::create("seqr", this);
            end
        endfunction

        function void connect_phase(uvm_phase phase);
            if (get_is_active() == UVM_ACTIVE)
                drv.seq_item_port.connect(seqr.seq_item_export);
        endfunction
    endclass

    // -------------------- sequence library --------------------
    class axi_lite_write_seq extends uvm_sequence#(axi_lite_item);
        `uvm_object_utils(axi_lite_write_seq)
        rand bit [31:0] addr;
        rand bit [31:0] data;
        rand bit [3:0]  strb = 4'hF;
        function new(string name = "axi_lite_write_seq"); super.new(name); endfunction
        task body();
            axi_lite_item tr = axi_lite_item::type_id::create("tr");
            start_item(tr);
            tr.dir   = AXIL_WRITE;
            tr.addr  = addr;
            tr.data  = data;
            tr.wstrb = strb;
            finish_item(tr);
        endtask
    endclass

    class axi_lite_read_seq extends uvm_sequence#(axi_lite_item);
        `uvm_object_utils(axi_lite_read_seq)
        rand bit [31:0] addr;
        bit      [31:0] rdata;    // captured
        function new(string name = "axi_lite_read_seq"); super.new(name); endfunction
        task body();
            axi_lite_item tr = axi_lite_item::type_id::create("tr");
            start_item(tr);
            tr.dir  = AXIL_READ;
            tr.addr = addr;
            finish_item(tr);
            rdata = tr.data;
        endtask
    endclass
endpackage
