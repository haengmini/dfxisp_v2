set here [file dirname [file normalize [info script]]]
set root [file dirname $here]
set out [file join $root build vivado]
file mkdir [file join $out reports]
source [file join $here rm_bd.tcl]
source [file join $here bd_parameters.tcl]

proc add_ip {name vlnv {config {}}} {
    set cell [create_bd_cell -type ip -vlnv $vlnv $name]
    if {[llength $config]} { set_property -dict $config $cell }
    return $cell
}
proc net {args} {
    connect_bd_net {*}[lmap pin $args {rm_get get_bd_pins $pin}]
}
proc axi {args} {
    connect_bd_intf_net {*}[lmap pin $args {rm_get get_bd_intf_pins $pin}]
}
proc map_address {space segment offset range} {
    assign_bd_address -target_address_space [rm_get get_bd_addr_spaces $space] \
        -offset $offset -range $range [rm_get get_bd_addr_segs $segment]
}

set begin [clock seconds]
set_param general.maxThreads 4
create_project -force dfx_ch2 [file join $out project] -part xczu7ev-ffvc1156-2-e
set_property PR_FLOW 1 [current_project]
set_property BOARD_PART xilinx.com:zcu104:part0:1.1 [current_project]
add_files -norecurse [list [file join $root rm_wrapper rm_control.v] \
    {*}[lsort [glob -directory [file join $root dfx_shell] *.v]]]
configure_ch3_ip_catalog $root
create_isp_rm isp_rp NormalISP
create_isp_rm isp_rp_lowlightISP LowlightISP
create_bd_design dfx_ch2

set ps zynq_ultra_ps_e_0
# HPC0 and HP1/HP2 belong to the omitted DPU. HP0 keeps the TF ISP/ICAP/Checker path.
foreach key {PSU__USE__S_AXI_GP0 PSU__USE__S_AXI_GP3 PSU__USE__S_AXI_GP4 PSU__USE__IRQ0} {
    dict set ps_config CONFIG.$key 0
}
add_ip $ps xilinx.com:ip:zynq_ultra_ps_e:3.5 $ps_config
add_ip rst_ps8_0_100M xilinx.com:ip:proc_sys_reset:5.0
add_ip axi_smc xilinx.com:ip:smartconnect:1.0 {CONFIG.NUM_SI 4 CONFIG.NUM_MI 1}
add_ip control_smc xilinx.com:ip:smartconnect:1.0 {CONFIG.NUM_SI 1 CONFIG.NUM_MI 5}
add_ip checker_axi3_adapter xilinx.com:ip:axi_protocol_converter:2.1 \
    {CONFIG.SI_PROTOCOL AXI4 CONFIG.MI_PROTOCOL AXI3 CONFIG.ADDR_WIDTH 64 CONFIG.DATA_WIDTH 32 CONFIG.ID_WIDTH 1}
add_ip checker_ip_0 user.org:user:checker_ip:1.1
add_ip dfx_controller_0 xilinx.com:ip:dfx_controller:1.0 [list CONFIG.ALL_PARAMS $dfxc_parameters]
add_ip dfx_decoupler_0 xilinx.com:ip:dfx_decoupler:1.0 [list CONFIG.ALL_PARAMS $decoupler_parameters]
foreach name {axi_shutdown_ctrl axi_shutdown_gmem0 axi_shutdown_gmem1} {
    set config {CONFIG.CTRL_INTERFACE_TYPE 0 CONFIG.DP_AXI_RESP 0}
    if {$name eq "axi_shutdown_ctrl"} {
        lappend config CONFIG.DP_PROTOCOL AXI4LITE CONFIG.RP_IS_MASTER false
    } else {
        lappend config CONFIG.DP_PROTOCOL AXI4MM CONFIG.RP_IS_MASTER true CONFIG.DP_AXI_ADDR_WIDTH 64 CONFIG.DP_AXI_ID_WIDTH 1
    }
    add_ip $name xilinx.com:ip:dfx_axi_shutdown_manager:1.0 $config
}
add_ip frame_idle_permit_gpio xilinx.com:ip:axi_gpio:2.0 \
    {CONFIG.C_IS_DUAL 1 CONFIG.C_GPIO_WIDTH 8 CONFIG.C_ALL_OUTPUTS 1 CONFIG.C_DOUT_DEFAULT 0x00000000 CONFIG.C_GPIO2_WIDTH 32 CONFIG.C_ALL_INPUTS_2 1}
add_ip response_error_or xilinx.com:ip:util_vector_logic:2.0 {CONFIG.C_OPERATION or CONFIG.C_SIZE 1}
add_ip response_clear_zero xilinx.com:ip:xlconstant:1.1 {CONFIG.CONST_VAL 0 CONFIG.CONST_WIDTH 1}
add_ip rm_reset_not xilinx.com:ip:util_vector_logic:2.0 {CONFIG.C_OPERATION not CONFIG.C_SIZE 1}
add_ip rm_aresetn_and xilinx.com:ip:util_vector_logic:2.0 {CONFIG.C_OPERATION and CONFIG.C_SIZE 1}
create_bd_cell -type module -reference icap_dfx_bridge icap_dfx_bridge_0
create_bd_cell -type module -reference dfx_safety_guard safety_guard
set_property CONFIG.TIMEOUT_CYCLES 10000000 [get_bd_cells safety_guard]
create_bd_cell -type module -reference axi_response_monitor_wrapper response_observer

set rp [create_bd_cell -type container -reference isp_rp isp_rp]
set_property APERTURES {{0xA0000000 64K}} [get_bd_intf_pins isp_rp/s_axi_control]
foreach n {0 1} {
    set_property APERTURES {{0x0 2G} {0xC0000000 512M}} [get_bd_intf_pins isp_rp/m_axi_gmem$n]
}
save_bd_design
set_property -dict {CONFIG.ACTIVE_SIM_BD isp_rp.bd CONFIG.ACTIVE_SYNTH_BD isp_rp.bd CONFIG.ENABLE_DFX true
    CONFIG.LIST_SIM_BD isp_rp.bd:isp_rp_lowlightISP.bd CONFIG.LIST_SYNTH_BD isp_rp.bd:isp_rp_lowlightISP.bd
    CONFIG.LOCK_PROPAGATE 0 CONFIG.TRAINING_MODULE isp_rp.bd} $rp

axi $ps/M_AXI_HPM0_FPD control_smc/S00_AXI
foreach {port sink} {
    M00_AXI axi_shutdown_ctrl/S_AXI M01_AXI dfx_controller_0/s_axi_reg
    M02_AXI checker_ip_0/s_axi_control M03_AXI checker_ip_0/s_axi_status M04_AXI frame_idle_permit_gpio/S_AXI
} { axi control_smc/$port $sink }
axi axi_shutdown_ctrl/M_AXI dfx_decoupler_0/s_CTRL
axi dfx_decoupler_0/rp_CTRL isp_rp/s_axi_control
foreach {n smc} {0 S00_AXI 1 S01_AXI} {
    axi isp_rp/m_axi_gmem$n dfx_decoupler_0/rp_GMEM$n
    axi dfx_decoupler_0/s_GMEM$n axi_shutdown_gmem$n/S_AXI
    axi axi_shutdown_gmem$n/M_AXI axi_smc/$smc
    axi response_observer/mon_gmem$n axi_shutdown_gmem$n/M_AXI
}
axi dfx_controller_0/M_AXI_MEM axi_smc/S02_AXI
axi checker_ip_0/m_axi_gmem0 checker_axi3_adapter/S_AXI
axi checker_axi3_adapter/M_AXI axi_smc/S03_AXI
axi axi_smc/M00_AXI $ps/S_AXI_HP0_FPD

set dfxc dfx_controller_0/vsm_VS_0
net checker_ip_0/vs_hw_triggers safety_guard/candidate
net safety_guard/hw_triggers ${dfxc}_hw_triggers
net safety_guard/shutdown_ack ${dfxc}_rm_shutdown_ack
net isp_rp/rm_ap_idle safety_guard/rm_idle checker_ip_0/rm_ap_idle
net ${dfxc}_rm_shutdown_req axi_shutdown_ctrl/request_shutdown axi_shutdown_gmem0/request_shutdown \
    axi_shutdown_gmem1/request_shutdown checker_ip_0/vs_rm_shutdown_req safety_guard/shutdown_req
foreach {manager drain} {ctrl ctrl gmem0 read gmem1 write} {
    net axi_shutdown_$manager/in_shutdown safety_guard/drain_$drain
}
net ${dfxc}_rm_decouple dfx_decoupler_0/decouple checker_ip_0/vs_rm_decouple safety_guard/decouple
net ${dfxc}_m_axis_status_tvalid safety_guard/status_valid
net ${dfxc}_m_axis_status_tdata safety_guard/dfx_status
net ${dfxc}_event_error response_error_or/Op1
net response_observer/fault_now response_error_or/Op2
net response_error_or/Res safety_guard/event_error
net response_clear_zero/dout response_observer/safe_reset_req response_observer/safe_reset_confirm response_observer/quiescent
net frame_idle_permit_gpio/gpio_io_o safety_guard/ctrl
net safety_guard/guard_status frame_idle_permit_gpio/gpio2_io_i
foreach pin {icap_csib icap_o icap_rdwrb icap_avail icap_i icap_prdone icap_prerror} {
    net dfx_controller_0/$pin icap_dfx_bridge_0/$pin
}

net $ps/pl_clk0 $ps/maxihpm0_fpd_aclk $ps/saxihp0_fpd_aclk rst_ps8_0_100M/slowest_sync_clk \
    axi_smc/aclk control_smc/aclk checker_axi3_adapter/aclk checker_ip_0/aclk safety_guard/clk \
    dfx_controller_0/clk dfx_controller_0/icap_clk icap_dfx_bridge_0/icap_clk \
    dfx_decoupler_0/CTRL_aclk dfx_decoupler_0/GMEM0_aclk dfx_decoupler_0/GMEM1_aclk \
    axi_shutdown_ctrl/clk axi_shutdown_gmem0/clk axi_shutdown_gmem1/clk isp_rp/ap_clk \
    frame_idle_permit_gpio/s_axi_aclk response_observer/clk
net $ps/pl_resetn0 rst_ps8_0_100M/ext_reset_in
net rst_ps8_0_100M/peripheral_aresetn axi_smc/aresetn control_smc/aresetn checker_axi3_adapter/aresetn \
    checker_ip_0/aresetn safety_guard/rst_n dfx_controller_0/reset dfx_controller_0/icap_reset \
    dfx_decoupler_0/CTRL_arstn dfx_decoupler_0/GMEM0_arstn dfx_decoupler_0/GMEM1_arstn \
    axi_shutdown_ctrl/resetn axi_shutdown_gmem0/resetn axi_shutdown_gmem1/resetn \
    frame_idle_permit_gpio/s_axi_aresetn response_observer/rst_n rm_aresetn_and/Op1
net ${dfxc}_rm_reset rm_reset_not/Op1
net rm_reset_not/Res rm_aresetn_and/Op2
net rm_aresetn_and/Res isp_rp/ap_rst_n

foreach {segment offset} {
    isp_rp/control/s_axi/reg0 0xA0000000
    dfx_controller_0/s_axi_reg/Reg 0xA2000000
    checker_ip_0/s_axi_control/reg0 0xA3000000
    checker_ip_0/s_axi_status/reg0 0xA3010000
    frame_idle_permit_gpio/S_AXI/Reg 0xA3020000
} { map_address $ps/Data $segment $offset 64K }
foreach space {dfx_controller_0/Data isp_rp/core/Data_m_axi_gmem0 isp_rp/core/Data_m_axi_gmem1 checker_ip_0/m_axi_gmem0} {
    map_address $space $ps/SAXIGP2/HP0_DDR_LOW 0 2G
    if {$space ne "checker_ip_0/m_axi_gmem0"} {
        map_address $space $ps/SAXIGP2/HP0_QSPI 0xC0000000 512M
        exclude_bd_addr_seg -target_address_space [get_bd_addr_spaces $space] [get_bd_addr_segs $ps/SAXIGP2/HP0_LPS_OCM]
    }
}
validate_bd_design -force
save_bd_design

set top_bd [get_files */dfx_ch2.bd]
add_files -norecurse [make_wrapper -files $top_bd -top]
set_property top dfx_ch2_wrapper [get_filesets sources_1]
add_files -fileset constrs_1 [file join $here isp_rp_floorplan.xdc]
puts "CHECKPOINT2_VALIDATED elapsed_s=[expr {[clock seconds]-$begin}]"
puts "PR modules: [get_reconfig_modules]"
puts "PR configurations: [get_pr_configurations]"
puts "Runs: [get_runs]"
close_project
