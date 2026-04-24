// uart_env_pkg.sv — package façade for the env.  Pulls in the scoreboard
// and the env composer.  The `uvm_analysis_imp_decl macros must live in
// the package (before their consumers) and cannot be included, so they
// stay here verbatim.
`timescale 1ns/1ps

package uart_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axi_lite_pkg::*;
    import uart_pkg::*;

    // Two typed analysis_imp functions on the same class need these decls.
    `uvm_analysis_imp_decl(_axi)
    `uvm_analysis_imp_decl(_uart)

    `include "uart_scoreboard.sv"
    `include "uart_env.sv"
endpackage
