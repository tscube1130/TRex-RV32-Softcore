set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ".."]]
set src_dir    [file join $repo_root "src"]
set pipe_dir   [file join $src_dir "3-stage-pipeline"]

read_verilog [list \
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

synth_design -top top_fpga -part xc7a100tcsg324-1
puts "DEBUG_OK: top_fpga synthesized in non-project mode"
