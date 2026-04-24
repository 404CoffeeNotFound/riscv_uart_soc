// uart_base_test.sv — base class shared by every concrete test.
// Provides the env handle + convenience axi_write / axi_read helpers.
// Included from uart_test_pkg.sv.

class uart_base_test extends uvm_test;
    `uvm_component_utils(uart_base_test)
    uart_env env;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        env = uart_env::type_id::create("env", this);
    endfunction

    // Single-write via the axi agent (blocks until complete).
    task axi_write(bit [31:0] addr, bit [31:0] data, bit [3:0] strb = 4'hF);
        axi_lite_write_seq seq = axi_lite_write_seq::type_id::create("seq");
        seq.addr = addr; seq.data = data; seq.strb = strb;
        seq.start(env.axi_agt.seqr);
    endtask

    task axi_read(bit [31:0] addr, output bit [31:0] rdata);
        axi_lite_read_seq seq = axi_lite_read_seq::type_id::create("seq");
        seq.addr = addr;
        seq.start(env.axi_agt.seqr);
        rdata = seq.rdata;
    endtask
endclass
