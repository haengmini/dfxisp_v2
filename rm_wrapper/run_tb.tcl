set script_dir [file dirname [file normalize [info script]]]
set root [file dirname $script_dir]
set out [file join $root build ch3_rm]
file mkdir $out

foreach {isp side cases} {
    NormalISP 8 {flat_mid_awb_on gradient_awb_on blue_cast_awb_on}
    LowlightISP 4 {flat_mid gradient noisy_dark}
} {
    set rtl [file join $root build $isp solution1 impl ip hdl verilog]
    set fd [open [file join $rtl $isp.v] r]
    set source [read $fd]
    close $fd
    set work [file join $out $isp]
    file mkdir $work
    cd $work

    set definitions {}
    set wiring {}
    set unmodeled {m_axi_gmem0_AWREADY m_axi_gmem0_WREADY m_axi_gmem0_BVALID
        m_axi_gmem0_BRESP m_axi_gmem0_BID m_axi_gmem0_BUSER m_axi_gmem0_RUSER
        m_axi_gmem0_RRESP m_axi_gmem1_ARREADY m_axi_gmem1_RVALID m_axi_gmem1_RDATA
        m_axi_gmem1_RLAST m_axi_gmem1_RID m_axi_gmem1_RUSER m_axi_gmem1_RRESP
        m_axi_gmem1_BRESP m_axi_gmem1_BUSER}
    set memory_ports {m_axi_gmem0_ARVALID m_axi_gmem0_ARREADY m_axi_gmem0_ARADDR
        m_axi_gmem0_ARID m_axi_gmem0_ARLEN m_axi_gmem0_ARSIZE m_axi_gmem0_ARBURST
        m_axi_gmem0_RVALID m_axi_gmem0_RREADY m_axi_gmem0_RDATA m_axi_gmem0_RLAST
        m_axi_gmem0_RID m_axi_gmem1_AWVALID m_axi_gmem1_AWREADY m_axi_gmem1_AWADDR
        m_axi_gmem1_AWID m_axi_gmem1_AWLEN m_axi_gmem1_AWSIZE m_axi_gmem1_AWBURST
        m_axi_gmem1_WVALID m_axi_gmem1_WREADY m_axi_gmem1_WDATA m_axi_gmem1_WLAST
        m_axi_gmem1_WSTRB m_axi_gmem1_BVALID m_axi_gmem1_BREADY m_axi_gmem1_BID}
    foreach line [split $source "\n"] {
        if {![regexp {^(input|output)\s+(\[.*?\]\s*)?(\w+)\s*;} $line -> dir bits port]} { continue }
        lappend definitions [list $port $dir [string trim $bits]]
        if {$port in {ap_clk ap_rst_n ap_start ap_done ap_idle ap_ready} || $port in $memory_ports} {
            set net $port
        } elseif {[regexp {^s_axi_control_(.*)$} $port -> channel]} {
            set net m_axi_[string tolower $channel]
        } elseif {$port in $unmodeled} {
            set net {'0}
        } elseif {$dir eq "output" && [string match m_axi_gmem* $port]} {
            set net ""
        } else { error "unhandled port $port" }
        lappend wiring ".${port}($net)"
    }
    foreach port {ap_start ap_done ap_idle ap_ready} {
        if {$port ni [lmap v $definitions {lindex $v 0}]} { error "missing $isp/$port" }
    }
    set fd [open core_instance.vh w]
    puts $fd "$isp dut ([join $wiring ",\n"]);"
    close $fd
    set fd [open core_ports.txt w]
    puts $fd [join [lsort $definitions] "\n"]
    close $fd
    foreach dat [glob -nocomplain -directory $rtl *.dat] { file copy -force $dat . }

    set fd [open [file join $root vectors ${isp}_vectors.csv] r]
    set data [split [read $fd] "\n"]
    close $fd
    set index -1
    foreach name $cases {
        incr index
        set raw [open raw_$index.hex w]
        set rgb [open rgb_$index.hex w]
        set counts [dict create raw 0 rgb 0]
        foreach row $data {
            lassign [split $row ,] label width height mode out_w out_h kind pixel value
            if {$label ne $name} { continue }
            if {$width != 8 || $height != 8 || $mode != 1 || $out_w != $side || $out_h != $side ||
                $pixel != [dict get $counts $kind]} { error "invalid reference row: $row" }
            puts [set $kind] [format %x $value]
            dict incr counts $kind
        }
        close $raw
        close $rgb
        if {[dict get $counts raw] != 64 || [dict get $counts rgb] != $side*$side} {
            error "invalid reference length for $name"
        }
    }

    set fd [open capture.tcl w]
    puts $fd {open_vcd rm_idle.vcd
log_vcd [get_objects /rm_reference_tb/ap_*]
log_vcd [get_objects /rm_reference_tb/rm_ap_idle]
run all
close_vcd
quit}
    close $fd

    foreach command [list \
        [list xvlog -sv -i . -d OUT_SIDE=$side {*}[lsort [glob -directory $rtl *.v]] \
            [file join $script_dir rm_control.v] [file join $script_dir rm_reference_tb.sv]] \
        {xelab -debug typical rm_reference_tb -s rm_reference} \
        {xsim rm_reference -tclbatch capture.tcl -onerror quit}] {
        set log [lindex $command 0].stdout
        puts "$isp: $command > $log"
        set start [clock milliseconds]
        set failed [catch {exec {*}$command > $log 2>@1} detail]
        puts "$isp: [lindex $command 0] elapsed [expr {[clock milliseconds]-$start}] ms"
        if {$failed} { error "$isp [lindex $command 0] failed: $detail. See [pwd]/$log" }
    }
    set fd [open xsim.stdout r]
    set log [read $fd]
    close $fd
    if {![string match {*PASS AP_CTRL AXI-Lite RGB 3/3*} $log]} {
        error "missing passing result: [pwd]/xsim.stdout"
    }
}
