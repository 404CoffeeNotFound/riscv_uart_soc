// uart_agent.sv — wraps uart_driver + uart_monitor + sequencer.
// Included from uart_pkg.sv.

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
