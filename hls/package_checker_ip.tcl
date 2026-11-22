set root [file dirname [file dirname [file normalize [info script]]]]
set build_dir [file join $root build]
set rtl_dir [file join $build_dir checker_scan solution1 impl ip hdl verilog]
set rtl_files [lsort [glob -nocomplain -directory $rtl_dir *.v]]
if {![file isfile [file join $rtl_dir checker_scan.v]]} {
    error "Export checker_scan from HLS before packaging checker_ip"
}

set ip_dir [file join $build_dir ip_repo checker_ip]
create_project -force checker_ip_pack [file join $build_dir checker_ip_pack] -part xczu7ev-ffvc1156-2-e
foreach rtl {checker_ip checker_hysteresis dfxc_trigger_adapter pr_latency_probe} {
    lappend rtl_files [file join $root checker ${rtl}.v]
}
add_files -norecurse $rtl_files
set_property top checker_ip [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project -root_dir $ip_dir -vendor user.org -library user -taxonomy /UserIP -import_files -set_current true
set core [ipx::current_core]
set_property version 1.1 $core
set gmem [ipx::get_bus_interfaces m_axi_gmem0 -of_objects $core]
foreach channel {AW W AR R B} {
    set name ${channel}USER_WIDTH
    set parameter [ipx::get_bus_parameters -quiet $name -of_objects $gmem]
    if {![llength $parameter]} {
        set parameter [ipx::add_bus_parameter $name $gmem]
    }
    set_property value 0 $parameter
}
foreach bus {m_axi_gmem0 s_axi_control s_axi_status} {
    ipx::associate_bus_interfaces -busif $bus -clock aclk $core
}
set clk [ipx::get_bus_interfaces aclk -of_objects $core]
set reset [ipx::get_bus_interfaces aresetn -of_objects $core]
set_property value aresetn [ipx::get_bus_parameters ASSOCIATED_RESET -of_objects $clk]
set_property value ACTIVE_LOW [ipx::get_bus_parameters POLARITY -of_objects $reset]

ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core
close_project
