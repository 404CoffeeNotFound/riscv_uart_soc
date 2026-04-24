// axi_lite_agent.sv — wraps driver, sequencer, monitor.
// Included from axi_lite_pkg.sv.

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
