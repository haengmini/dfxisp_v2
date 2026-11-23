# Reusable block-design construction for an ISP reconfigurable module.
proc rm_get {object name} {
    set result [uplevel 1 [list $object -quiet $name]]
    if {[llength $result] != 1} { error "$object $name returned [llength $result] objects: $result" }
    return $result
}

proc create_isp_rm {name isp} {
    create_bd_design $name
    create_bd_cell -type ip -vlnv xilinx.com:hls:$isp:1.0 core
    create_bd_cell -type module -reference rm_control control

    create_bd_port -dir I -type clk -freq_hz 100000000 ap_clk
    create_bd_port -dir I -type rst ap_rst_n
    set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports ap_rst_n]
    create_bd_port -dir O rm_ap_idle
    connect_bd_net [get_bd_ports ap_clk] [get_bd_pins core/ap_clk] [get_bd_pins control/ap_clk]
    connect_bd_net [get_bd_ports ap_rst_n] [get_bd_pins core/ap_rst_n] [get_bd_pins control/ap_rst_n]
    connect_bd_net [get_bd_ports rm_ap_idle] [get_bd_pins control/rm_ap_idle]
    foreach pin {ap_start ap_done ap_idle ap_ready} {
        connect_bd_net [rm_get get_bd_pins core/$pin] [rm_get get_bd_pins control/$pin]
    }

    set slave [create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi_control]
    set_property -dict {CONFIG.PROTOCOL AXI4LITE CONFIG.ADDR_WIDTH 32 CONFIG.DATA_WIDTH 32} $slave
    connect_bd_intf_net $slave [rm_get get_bd_intf_pins control/S_AXI]
    connect_bd_intf_net [rm_get get_bd_intf_pins control/M_AXI] [rm_get get_bd_intf_pins core/s_axi_control]

    foreach {bus direction} {m_axi_gmem0 READ_ONLY m_axi_gmem1 WRITE_ONLY} {
        set boundary [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 $bus]
        set_property -dict [list CONFIG.PROTOCOL AXI4 CONFIG.ADDR_WIDTH 64 CONFIG.DATA_WIDTH 32 \
            CONFIG.READ_WRITE_MODE $direction CONFIG.HAS_BURST 0] $boundary
        connect_bd_intf_net $boundary [rm_get get_bd_intf_pins core/$bus]
    }
    set_property -dict {CONFIG.ASSOCIATED_BUSIF m_axi_gmem1:m_axi_gmem0:s_axi_control CONFIG.ASSOCIATED_RESET ap_rst_n} [get_bd_ports ap_clk]

    create_bd_addr_seg -offset 0xA0000000 -range 64K [get_bd_addr_spaces s_axi_control] \
        [get_bd_addr_segs control/s_axi/reg0] SEG_RM_CONTROL
    create_bd_addr_seg -offset 0 -range 128 [get_bd_addr_spaces control/m_axi] \
        [get_bd_addr_segs core/s_axi_control/Reg] SEG_HLS_CONTROL
    foreach bus {m_axi_gmem0 m_axi_gmem1} {
        set address_space [get_bd_addr_spaces core/Data_$bus]
        set memory [get_bd_addr_segs $bus/Reg]
        create_bd_addr_seg -offset 0 -range 2G $address_space $memory SEG_DDR_LOW
        create_bd_addr_seg -offset 0xC0000000 -range 512M $address_space $memory SEG_QSPI
    }
    validate_bd_design
    save_bd_design
    puts "RM_BOUNDARY $name: [lsort [get_bd_ports]] [lsort [get_bd_intf_ports]]"
    close_bd_design [current_bd_design]
}

proc configure_ch3_ip_catalog {root} {
    set repos [list [file join $root build ip_repo]]
    foreach isp {NormalISP LowlightISP} {
        set repo [file join $root build $isp solution1 impl ip]
        if {![file isfile [file join $repo component.xml]]} {
            error "Missing HLS export for $isp"
        }
        lappend repos $repo
    }
    set_property ip_repo_paths $repos [current_project]
    update_ip_catalog
}
