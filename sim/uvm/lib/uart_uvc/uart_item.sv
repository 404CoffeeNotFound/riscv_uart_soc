// uart_item.sv — transaction carried by the UART serial-line UVC.
// Included from uart_pkg.sv.

class uart_item extends uvm_sequence_item;
    rand bit [7:0]     data;
    rand bit           inject_frame_err;
    rand int unsigned  gap_bits;
    constraint c_default {
        soft inject_frame_err == 0;
        soft gap_bits inside {[1:8]};
    }
    `uvm_object_utils_begin(uart_item)
        `uvm_field_int(data, UVM_DEFAULT)
        `uvm_field_int(inject_frame_err, UVM_DEFAULT)
        `uvm_field_int(gap_bits, UVM_DEFAULT)
    `uvm_object_utils_end
    function new(string name = "uart_item"); super.new(name); endfunction
endclass
