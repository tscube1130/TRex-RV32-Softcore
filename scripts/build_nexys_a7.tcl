# Build the Project T-Rex / Chrome Dino bitstream for Nexys A7-100T.
#
# Run from the repository root:
#   C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -source scripts/build_nexys_a7.tcl

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ".."]]
set build_dir  [file join $repo_root "build" "vivado"]
set proj_name  "trex_dino_nexys_a7"
set part_name  "xc7a100tcsg324-1"

cd $repo_root
file mkdir $build_dir

create_project -force $proj_name $build_dir -part $part_name
set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]

set src_dir [file join $repo_root "src"]
set pipe_dir [file join $src_dir "3-stage-pipeline"]

add_files -fileset sources_1 -norecurse [list \
    [file join $pipe_dir "top_fpga.v"] \
    [file join $pipe_dir "pipeline.v"] \
    [file join $pipe_dir "memory.v"] \
    [file join $src_dir "audio_driver.v"] \
    [file join $src_dir "math_coproc.v"] \
    [file join $src_dir "mmio_decoder.v"] \
    [file join $src_dir "debouncer.v"] \
    [file join $src_dir "lfsr16.v"] \
    [file join $src_dir "led_ctrl.v"] \
    [file join $src_dir "seg7_mux.v"] \
]

set_property include_dirs [list $pipe_dir] [get_filesets sources_1]

set imem_hex [file join $repo_root "software" "mem_generator" "imem_dmem" "imem.hex"]
set dmem_hex [file join $repo_root "software" "mem_generator" "imem_dmem" "dmem.hex"]
add_files -fileset sources_1 -norecurse [list $imem_hex $dmem_hex]

# Vivado synth_design evaluates $readmemh relative to the synthesis run
# directory. Copy the BRAM init files there so instr_mem/data_mem can load them.
set synth_dir [file join $build_dir "$proj_name.runs" "synth_1"]
file mkdir $synth_dir
file copy -force $imem_hex [file join $synth_dir "imem.hex"]
file copy -force $dmem_hex [file join $synth_dir "dmem.hex"]

add_files -fileset constrs_1 -norecurse [list [file join $repo_root "constraints" "nexys_a7.xdc"]]

set_property top top_fpga [get_filesets sources_1]
update_compile_order -fileset sources_1

# Ensure stale run metadata cannot keep an old top (e.g. "pipe")
if {[llength [get_runs synth_1 -quiet]] > 0} {
    reset_run synth_1
}
if {[llength [get_runs impl_1 -quiet]] > 0} {
    reset_run impl_1
}

# Fail fast if project top is not top_fpga
if {[get_property top [get_filesets sources_1]] ne "top_fpga"} {
    error "Top module mismatch: project top is '[get_property top [get_filesets sources_1]]', expected 'top_fpga'"
}
puts "INFO: Using top module '[get_property top [get_filesets sources_1]]' for synthesis"

launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "synth_1 did not complete successfully"
}

# Generate impl scripts first; on some setups runme launches before scripts exist.
launch_runs impl_1 -to_step write_bitstream -jobs 4 -scripts_only
set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set impl_tcls [glob -nocomplain -directory $impl_dir *.tcl]
if {[llength $impl_tcls] == 0} {
    error "impl_1 script generation failed: no .tcl file found under $impl_dir"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "impl_1 did not complete successfully"
}

set bit_path [get_property DIRECTORY [get_runs impl_1]]
puts "Bitstream generated under: $bit_path"
