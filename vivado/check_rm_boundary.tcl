set here [file dirname [file normalize [info script]]]
set root [file dirname $here]
source [file join $here rm_bd.tcl]
set work [file join $root build ch3_rm boundary]
file mkdir $work
create_project -force rm_boundary $work -part xczu7ev-ffvc1156-2-e
add_files [file join $root rm_wrapper rm_control.v]
configure_ch3_ip_catalog $root
create_isp_rm isp_rp NormalISP
create_isp_rm isp_rp_lowlightISP LowlightISP
close_project
