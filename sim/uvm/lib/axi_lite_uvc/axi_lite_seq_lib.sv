// axi_lite_seq_lib.sv — reusable single-transaction sequences.
// Included from axi_lite_pkg.sv.

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
