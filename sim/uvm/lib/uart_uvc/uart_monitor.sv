// uart_monitor.sv — observes txd, emits uart_item per byte, plus functional
// coverage.  Included from uart_pkg.sv.

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
