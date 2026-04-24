// axi_lite_master_driver.sv — AXI4-Lite master driver.
// Included from axi_lite_pkg.sv.

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
