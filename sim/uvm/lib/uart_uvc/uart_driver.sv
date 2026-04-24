// uart_driver.sv — drives rxd with 8N1 frames.  Included from uart_pkg.sv.

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
