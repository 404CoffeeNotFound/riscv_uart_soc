// axi_lite_monitor.sv — AXI4-Lite monitor (write + read channels) plus
// transaction-level functional coverage.
// Included from axi_lite_pkg.sv.

class axi_lite_monitor extends uvm_monitor;
    `uvm_component_utils(axi_lite_monitor)
    virtual axi_lite_if vif;
    uvm_analysis_port #(axi_lite_item) ap;

    // Functional coverage on register access patterns.
    covergroup cg_txn with function sample(axi_lite_item tr);
        option.per_instance = 1;
        cp_dir   : coverpoint tr.dir {
            bins write = {AXIL_WRITE};
            bins read  = {AXIL_READ};
        }
        cp_addr  : coverpoint tr.addr[7:2] {
            bins data_reg   = {6'h00};
            bins status_reg = {6'h01};
            bins ctrl_reg   = {6'h02};
            bins baud_reg   = {6'h03};
            bins other      = default;
        }
        cp_wstrb : coverpoint tr.wstrb iff (tr.dir == AXIL_WRITE) {
            bins full    = {4'hF};
            bins partial = {[4'h1:4'hE]};
            bins none    = {4'h0};
        }
        cp_resp  : coverpoint tr.resp {
            bins okay    = {2'b00};
            bins exokay  = {2'b01};
            bins slverr  = {2'b10};
            bins decerr  = {2'b11};
        }
        cx_dir_addr : cross cp_dir, cp_addr;
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
        cg_txn = new;
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

    task watch_writes();
        forever begin
            axi_lite_item tr;
            bit [31:0] addr_q, data_q;
            bit [3:0]  strb_q;
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
            do @(posedge vif.aclk); while (!(vif.bvalid && vif.bready));
            tr = axi_lite_item::type_id::create("wr_tr");
            tr.dir   = AXIL_WRITE;
            tr.addr  = addr_q;
            tr.data  = data_q;
            tr.wstrb = strb_q;
            tr.resp  = vif.bresp;
            ap.write(tr);
            cg_txn.sample(tr);
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
            cg_txn.sample(tr);
        end
    endtask
endclass
