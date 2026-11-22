set root [file dirname [file dirname [file normalize [info script]]]]

if {![info exists ::env(ISP)] || $::env(ISP) ni {NormalISP LowlightISP checker_scan}} {
    puts stderr "Set ISP to NormalISP, LowlightISP, or checker_scan"
    exit 1
}
if {![info exists ::env(FLOW)] || $::env(FLOW) ni {csim csynth cosim export all}} {
    puts stderr "Set FLOW to csim, csynth, cosim, export, or all"
    exit 1
}
set isp $::env(ISP)
set flow $::env(FLOW)
set build_dir [file join $root build]

file mkdir $build_dir
cd $build_dir
open_project -reset [file join $build_dir $isp]
set_top $isp
set cosim_args {-tool xsim -rtl verilog}
if {$isp eq "checker_scan"} {
    add_files [file join $root checker checker.cpp]
    add_files -tb [file join $root checker checker_reference_tb.cpp]
    lappend cosim_args -argv rtl
} else {
    add_files [file join $root $isp ${isp}.cpp]
    add_files -tb [file join $root $isp ${isp}_reference_tb.cpp]
    add_files -tb [file join $root vectors ${isp}_vectors.csv]
}

open_solution -reset solution1 -flow_target vivado
set_part xczu7ev-ffvc1156-2-e
create_clock -period 4 -name default

if {$flow in {csim all}} {
    csim_design
}
if {$flow ne "csim"} {
    csynth_design
}
set cosim_failed 0
if {$flow in {cosim all}} {
    set cosim_failed [catch {cosim_design {*}$cosim_args} cosim_error]
    if {$cosim_failed} {
        puts stderr "C/RTL co-simulation failed: $cosim_error"
    }
}
if {$flow in {export all}} {
    export_design -format ip_catalog
}
close_project
exit $cosim_failed
