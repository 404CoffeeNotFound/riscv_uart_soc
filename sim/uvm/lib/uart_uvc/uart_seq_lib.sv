// uart_seq_lib.sv — reusable sequences for the UART serial-line UVC.
// Included from uart_pkg.sv.

// Random bytes with default (soft) constraints.
class uart_random_seq extends uvm_sequence#(uart_item);
    `uvm_object_utils(uart_random_seq)
    rand int unsigned n = 10;
    function new(string name = "uart_random_seq"); super.new(name); endfunction
    task body();
        for (int i = 0; i < n; i++) begin
            uart_item tr = uart_item::type_id::create("tr");
            start_item(tr);
            if (!tr.randomize()) `uvm_fatal("RAND","randomize failed")
            finish_item(tr);
        end
    endtask
endclass

// Fixed corner-case patterns: every bit position flipped at least once.
class uart_corner_seq extends uvm_sequence#(uart_item);
    `uvm_object_utils(uart_corner_seq)
    function new(string name = "uart_corner_seq"); super.new(name); endfunction
    task body();
        byte unsigned pats[] = '{8'h00, 8'hFF, 8'h55, 8'hAA,
                                  8'h01, 8'h80, 8'h7F, 8'hFE};
        foreach (pats[i]) begin
            uart_item tr = uart_item::type_id::create("tr");
            start_item(tr);
            if (!tr.randomize() with { data == pats[i]; inject_frame_err == 0; })
                `uvm_fatal("RAND","randomize failed")
            finish_item(tr);
        end
    endtask
endclass

// Inject an arbitrary byte stream on rxd (clean frames, 1-bit gap).
// Used by SoC-level tests that need to upload a binary payload.
class uart_inject_seq extends uvm_sequence#(uart_item);
    `uvm_object_utils(uart_inject_seq)
    byte unsigned bytes[$];
    function new(string name = "uart_inject_seq"); super.new(name); endfunction
    task body();
        foreach (bytes[i]) begin
            uart_item tr = uart_item::type_id::create("tr");
            start_item(tr);
            if (!tr.randomize() with {
                data == bytes[i];
                inject_frame_err == 0;
                gap_bits == 1;
            }) `uvm_fatal("RAND","randomize failed")
            finish_item(tr);
        end
    endtask
endclass

// Inject exactly one byte on rxd with stop=0 — used by the frame-error
// directed test to trigger the DUT's sticky FRAME_ERR bit.
class uart_one_err_seq extends uvm_sequence#(uart_item);
    `uvm_object_utils(uart_one_err_seq)
    rand bit [7:0] data_val = 8'h5A;
    function new(string name = "uart_one_err_seq"); super.new(name); endfunction
    task body();
        uart_item tr = uart_item::type_id::create("tr");
        start_item(tr);
        if (!tr.randomize() with {
            data == data_val;
            inject_frame_err == 1;
            gap_bits == 4;          // give the RX engine idle time to settle
        }) `uvm_fatal("RAND","randomize failed")
        finish_item(tr);
    endtask
endclass
