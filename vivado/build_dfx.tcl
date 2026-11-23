set here [file dirname [file normalize [info script]]]
set out [file join [file dirname $here] build vivado]
set project [file join $out project dfx_ch2.xpr]
set reports [file join $out reports]
set exports [file join $out bitstreams]
file mkdir $reports $exports
set part xczu7ev-ffvc1156-2-e
set rp dfx_ch2_i/isp_rp
set begin [clock seconds]
set_param general.maxThreads 4

proc run_to {name step} {
    set start [clock seconds]
    set status [get_property STATUS [get_runs $name]]
    if {[string match "$step Complete*" $status]} {
        puts "RUN_RESULT $name $status already_complete"
        return
    }
    if {$step eq "synth_design"} {
        launch_runs $name -jobs 1
    } else {
        launch_runs $name -to_step $step -jobs 1
    }
    wait_on_run $name
    set status [get_property STATUS [get_runs $name]]
    puts "RUN_RESULT $name $status elapsed_s=[expr {[clock seconds]-$start}]"
    if {![string match "$step Complete*" $status]} { error "$name: $status" }
}

proc save_run_reports {tag reports {routed false}} {
    report_utilization -file [file join $reports ${tag}_utilization.rpt]
    report_utilization -hierarchical -hierarchical_depth 3 -file [file join $reports ${tag}_hier.rpt]
    if {$routed} {
        report_timing_summary -delay_type min_max -report_unconstrained -file [file join $reports ${tag}_timing.rpt]
        check_timing -verbose -file [file join $reports ${tag}_check_timing.rpt]
        report_drc -file [file join $reports ${tag}_drc.rpt]
        report_route_status -file [file join $reports ${tag}_route.rpt]
        report_utilization -pblocks [get_pblocks pblock_isp_rp] -file [file join $reports ${tag}_pblock.rpt]
    }
}

set stage [lindex $argv 0]
if {$stage ni {synth impl bits}} { error "Use -tclargs synth, impl, or bits" }
open_project $project
set normal_run impl_1
set lowlight_run impl_lowlight
switch $stage {
    synth {
        foreach name {isp_rp isp_rp_lowlightISP dfx_ch2} {
            generate_target all [get_files */$name.bd]
        }
        update_compile_order -fileset sources_1
        puts "PR_MODULES [get_reconfig_modules]"
        puts "SYNTH_RUNS [get_runs -filter {IS_SYNTHESIS == 1}]"
        foreach run {synth_1 isp_rp_inst_0_synth_1 isp_rp_lowlightISP_inst_0_synth_1} {
            if {![llength [get_runs -quiet $run]]} { error "Missing synthesis run $run" }
            run_to $run synth_design
            open_run $run
            save_run_reports $run $reports
            close_design
        }
    }
    impl {
        help create_pr_configuration
        help create_run
        help set_property
        foreach {config module} {Normal isp_rp_inst_0 Lowlight isp_rp_lowlightISP_inst_0} {
            if {![llength [get_pr_configurations -quiet $config]]} {
                create_pr_configuration -name $config -partitions [list ${rp}:$module]
            }
        }
        set_property PR_CONFIGURATION Normal [get_runs $normal_run]
        if {![llength [get_runs -quiet $lowlight_run]]} {
            create_run $lowlight_run -part $part -flow [get_property FLOW [get_runs $normal_run]] \
                -parent_run $normal_run -pr_config Lowlight
        }
        set_property PR_CONFIGURATION Lowlight [get_runs $lowlight_run]
        foreach {tag run} [list normal $normal_run lowlight $lowlight_run] {
            run_to $run route_design
            open_run $run
            save_run_reports $tag $reports true
            write_checkpoint -force [file join $reports ${tag}_routed.dcp]
            close_design
        }
    }
    bits {
        help pr_verify
        help write_bitstream
        set normal [file join $reports normal_routed.dcp]
        set lowlight [file join $reports lowlight_routed.dcp]
        set start [clock seconds]
        pr_verify -full_check -initial $normal -additional $lowlight -file [file join $reports pr_verify.log]
        puts "PR_VERIFY_PASS elapsed_s=[expr {[clock seconds]-$start}]"
        foreach {tag checkpoint} [list normal $normal lowlight $lowlight] {
            set start [clock seconds]
            open_checkpoint $checkpoint
            if {$tag eq "normal"} {
                write_bitstream -force -no_partial_bitfile [file join $exports full_normal.bit]
            }
            write_bitstream -force -bin_file -cell [get_cells $rp] [file join $exports partial_$tag.bit]
            close_design
            set bin [file join $exports partial_$tag.bin]
            set bit [file join $exports partial_$tag.bit]
            set f [open $bin rb]
            set payload [read $f]
            close $f
            set header [binary encode hex [string range $payload 0 127]]
            if {[string first aa995566 $header] < 0} { error "Unexpected byte order in $bin: $header" }
            set f [open $bit rb]
            seek $f [expr {[file size $bit]-[file size $bin]}]
            set bit_payload [read $f]
            close $f
            if {$payload ne $bit_payload} { error "$bin does not equal the headerless .bit payload" }
            file copy -force $bin [file join $exports partial_$tag.icap.bin]
            puts "BITSTREAM $tag elapsed_s=[expr {[clock seconds]-$start}] bit_bytes=[file size $bit] icap_bytes=[file size $bin] expected_dfxc_bytes=1447292"
        }
    }
}
close_project
puts "CHECKPOINT_STAGE_PASS $stage elapsed_s=[expr {[clock seconds]-$begin}]"
