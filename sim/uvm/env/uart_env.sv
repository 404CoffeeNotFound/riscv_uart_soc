// uart_env.sv — composes AXI + UART agents and the scoreboard.
// Included from uart_env_pkg.sv.

class uart_env extends uvm_env;
    `uvm_component_utils(uart_env)
    axi_lite_agent   axi_agt;
    uart_agent       uart_agt;
    uart_scoreboard  sb;
    bit              has_axi_agent = 1'b1;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        void'(uvm_config_db#(bit)::get(this, "", "has_axi_agent", has_axi_agent));
        if (has_axi_agent)
            axi_agt = axi_lite_agent::type_id::create("axi_agt", this);
        uart_agt = uart_agent     ::type_id::create("uart_agt", this);
        sb       = uart_scoreboard::type_id::create("sb",       this);
    endfunction

    function void connect_phase(uvm_phase phase);
        if (has_axi_agent)
            axi_agt.mon.ap.connect(sb.axi_in);
        uart_agt.mon.ap.connect(sb.uart_in);
    endfunction
endclass
