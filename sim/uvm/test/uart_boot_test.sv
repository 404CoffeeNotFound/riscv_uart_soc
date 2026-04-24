// uart_boot_test.sv — SoC-level hybrid UVM+C bootloader test.
// Runs against soc_tb_top; the PicoRV32 inside runs sw/bootloader, and
// the UART agent uploads sw/app/app.bin, expecting "BOOT/LOAD/APP_OK" on txd.
// Included from uart_test_pkg.sv.

class uart_boot_test extends uart_base_test;
    `uvm_component_utils(uart_boot_test)
    string app_bin_path = "../../sw/app/app.bin";

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void load_app(ref byte unsigned out_bytes[$]);
        int fd;
        int n;
        byte unsigned b;
        fd = $fopen(app_bin_path, "rb");
        if (fd == 0) `uvm_fatal("FOPEN", $sformatf("cannot open %s", app_bin_path))
        forever begin
            n = $fread(b, fd);
            if (n == 0) break;
            out_bytes.push_back(b);
        end
        $fclose(fd);
    endfunction

    task run_phase(uvm_phase phase);
        byte unsigned app_bytes[$];
        uart_inject_seq inj = uart_inject_seq::type_id::create("inj");
        int unsigned len;

        phase.raise_objection(this);
        `uvm_info("BOOT_TEST", "SoC-level hybrid UVM+C bootloader test", UVM_LOW)

        load_app(app_bytes);
        len = app_bytes.size();
        `uvm_info("BOOT_TEST", $sformatf("app.bin = %0d bytes", len), UVM_LOW)

        // Let the bootloader print "BOOT\n" and reach its sync-wait loop.
        #(1_000_000);   // 1 ms

        inj.bytes.push_back(8'hA5);
        for (int i = 0; i < 4; i++)
            inj.bytes.push_back((len >> (i*8)) & 8'hFF);
        foreach (app_bytes[i]) inj.bytes.push_back(app_bytes[i]);
        `uvm_info("BOOT_TEST",
            $sformatf("injecting %0d bytes on rxd", inj.bytes.size()), UVM_LOW)
        inj.start(env.uart_agt.seqr);

        #(3_000_000);

        if (!env.sb.contains("BOOT\n"))
            `uvm_error("MISSING_BOOT", "no 'BOOT\\n' greeting on txd")
        if (!env.sb.contains("LOAD\n"))
            `uvm_error("MISSING_LOAD", "bootloader never printed 'LOAD\\n' (payload not accepted?)")
        if (!env.sb.contains("APP_OK\n"))
            `uvm_error("MISSING_APP_OK",
                $sformatf("uploaded app did not emit 'APP_OK\\n'. txd_all=%0d bytes",
                          env.sb.txd_all.len()))
        else
            `uvm_info("BOOT_TEST",
                "== full boot chain verified: BOOT -> LOAD -> APP_OK ==", UVM_NONE)

        phase.drop_objection(this);
    endtask
endclass
