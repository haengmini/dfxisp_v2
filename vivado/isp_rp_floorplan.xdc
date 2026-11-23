create_pblock pblock_isp_rp
add_cells_to_pblock [get_pblocks pblock_isp_rp] [get_cells dfx_ch2_i/isp_rp]
resize_pblock [get_pblocks pblock_isp_rp] -add {CLOCKREGION_X1Y0:CLOCKREGION_X2Y0}
set_property SNAPPING_MODE ON [get_pblocks pblock_isp_rp]
set_property CONTAIN_ROUTING true [get_pblocks pblock_isp_rp]
set_property EXCLUDE_PLACEMENT true [get_pblocks pblock_isp_rp]
