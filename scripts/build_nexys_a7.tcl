# Build the Project T-Rex / Chrome Dino bitstream for Nexys A7-100T (singleplayer variant).
#
# Run from the repository root:
#   vivado -mode batch -source scripts/build_nexys_a7.tcl
#
# On Windows (Vivado 2025.2):
#   C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -source scripts/build_nexys_a7.tcl

set script_dir  [file dirname [file normalize [info script]]]
set repo_root   [file normalize [file join $script_dir ".."]]
set build_dir   [file join $repo_root "build" "vivado"]
set proj_name   "trex_dino_nexys_a7"
set part_name   "xc7a100tcsg324-1"

# Source directories (new repo layout)
set src_core    [file join $repo_root "src" "core"]
set src_periph  [file join $repo_root "src" "peripherals"]
set variant_dir [file join $repo_root "variants" "singleplayer"]
set mem_dir     [file join $repo_root "mem_generator" "imem_dmem"]

cd $repo_root
file mkdir $build_dir

create_project -force $proj_name $build_dir -part $part_name
set_property target_language    Verilog [current_project]
set_property simulator_language Verilog [current_project]
set_property source_mgmt_mode  None    [current_project]

# ── RTL sources ──────────────────────────────────────────────────────────────
add_files -fileset sources_1 -norecurse [list \
    [file join $variant_dir "top_fpga.v"]       \
    [file join $src_core    "pipeline.v"]        \
    [file join $src_core    "IF_ID.v"]           \
    [file join $src_core    "execute.v"]         \
    [file join $src_core    "memory.v"]          \
    [file join $src_core    "wb.v"]              \
    [file join $src_core    "math_coproc.v"]     \
    [file join $variant_dir "mmio_decoder.v"]    \
    [file join $variant_dir "seg7_mux.v"]        \
    [file join $src_periph  "audio_driver.v"]    \
    [file join $src_periph  "debouncer.v"]       \
    [file join $src_periph  "lfsr16.v"]          \
    [file join $src_periph  "led_ctrl.v"]        \
]

# opcode.vh lives in src/core; variant headers in variants/singleplayer
set_property include_dirs [list $src_core $variant_dir] [get_filesets sources_1]

# ── BRAM init files ───────────────────────────────────────────────────────────
set imem_hex [file join $mem_dir "imem.hex"]
set dmem_hex [file join $mem_dir "dmem.hex"]
add_files -fileset sources_1 -norecurse [list $imem_hex $dmem_hex]

# Vivado evaluates $readmemh relative to the synth run directory — copy there.
set synth_dir [file join $build_dir "$proj_name.runs" "synth_1"]
file mkdir $synth_dir
file copy -force $imem_hex [file join $synth_dir "imem.hex"]
file copy -force $dmem_hex [file join $synth_dir "dmem.hex"]

# ── Constraints ───────────────────────────────────────────────────────────────
add_files -fileset constrs_1 -norecurse \
    [list [file join $variant_dir "constraints" "nexys_a7.xdc"]]

# ── Top module & compile order ────────────────────────────────────────────────
set_property top top_fpga [get_filesets sources_1]
update_compile_order -fileset sources_1

# Ensure stale run metadata cannot keep an old top module
if {[llength [get_runs synth_1 -quiet]] > 0} { reset_run synth_1 }
if {[llength [get_runs impl_1  -quiet]] > 0} { reset_run impl_1  }

# Fail fast if project top is not top_fpga
if {[get_property top [get_filesets sources_1]] ne "top_fpga"} {
    error "Top module mismatch: got '[get_property top [get_filesets sources_1]]', expected 'top_fpga'"
}
puts "INFO: Top module = [get_property top [get_filesets sources_1]]"

# ── Synthesis ─────────────────────────────────────────────────────────────────
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "synth_1 did not complete successfully"
}

# ── Implementation + Bitstream ────────────────────────────────────────────────
launch_runs impl_1 -to_step write_bitstream -jobs 4 -scripts_only
set impl_dir  [get_property DIRECTORY [get_runs impl_1]]
set impl_tcls [glob -nocomplain -directory $impl_dir *.tcl]
if {[llength $impl_tcls] == 0} {
    error "impl_1 script generation failed: no .tcl found under $impl_dir"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "impl_1 did not complete successfully"
}

puts "Bitstream generated under: [get_property DIRECTORY [get_runs impl_1]]"