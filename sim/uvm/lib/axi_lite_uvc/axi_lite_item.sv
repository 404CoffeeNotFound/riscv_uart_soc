// axi_lite_item.sv — transaction carried by the AXI4-Lite UVC.
// Included from axi_lite_pkg.sv; not a standalone compilation unit.

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
