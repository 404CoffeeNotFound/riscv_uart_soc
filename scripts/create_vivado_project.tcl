# Vivado 2024.2 project generator for riscv_uart_soc on Zybo Z7-20.
# Usage:  vivado -mode batch -source scripts/create_vivado_project.tcl
# or inside Vivado GUI Tcl console: source scripts/create_vivado_project.tcl

set repo_root [file normalize [file dirname [info script]]/..]
set proj_name "riscv_uart_soc"
set proj_dir  "$repo_root/vivado_project"
set part      "xc7z020clg400-1"
set board     "digilentinc.com:zybo-z7-20:part0:2.0"

# ---- sanity ----
if { ![file exists "$repo_root/rtl/core/picorv32/picorv32.v"] } {
    puts "ERROR: picorv32.v not found. Run scripts/fetch_picorv32.sh first."
    exit 1
}

# ---- fresh project ----
file delete -force $proj_dir
create_project $proj_name $proj_dir -part $part -force

# Board files must be installed under <Vivado>/data/boards/board_files/
# (Digilent vivado-boards repo). If unavailable, the set_property below is skipped.
if { [catch { set_property board_part $board [current_project] } err] } {
    puts "WARN: board file for $board not found; continuing part-only. ($err)"
}

# ---- add sources ----
add_files -norecurse \
    "$repo_root/rtl/core/picorv32/picorv32.v" \
    "$repo_root/rtl/peripherals/uart/uart_top.sv" \
    "$repo_root/rtl/soc/soc_top.sv"

# Constraints
add_files -fileset constrs_1 -norecurse \
    "$repo_root/rtl/constraints/zybo_z720.xdc"

# VHDL/Verilog mix — default to SystemVerilog for .sv
set_property file_type SystemVerilog [get_files *.sv]

set_property top soc_top [current_fileset]
update_compile_order -fileset sources_1

# ---- BRAM init: hello.mem (if SW already built) ----
set memfile "$repo_root/sw/hello/hello.mem"
if { [file exists $memfile] } {
    add_files -norecurse $memfile
    set_property scoped_to_cells {u_bram} [get_files $memfile]
} else {
    puts "NOTE: $memfile not yet built. Run 'make -C sw' before synthesis."
}

puts "Project created at $proj_dir"
puts "Next:  launch_runs synth_1 -jobs 4; wait_on_run synth_1"
puts "       launch_runs impl_1 -to_step write_bitstream -jobs 4"
