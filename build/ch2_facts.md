# 2장 DFX 최종 통합 BD 사실 확인

정본 루트는 `dfxisp_essen/`이다. 이 문서에서 **TF**는 `unified_work/frame_idle_safety_gate/corrective_contract/timeout_fixed`, **BD**는 `TF/project/dfx_zcu104.srcs/sources_1/bd/NormalISP_zcu104_design1/NormalISP_zcu104_design1.bd`다. **XCI**는 BD 디렉터리에서 `design.components.<instance>.xci_path`가 가리키는 파일이다.

## Floorplan과 DFXC 비트스트림 위치

| 항목 | 최종 설계 | 근거 |
| --- | --- | --- |
| RP 계층 / Pblock | `NormalISP_zcu104_design1_i/isp_rp` / `pblock_isp_rp` | `TF/project/dfx_zcu104.srcs/constrs_1/new/isp_rp_floorplan.xdc:1–2` |
| 배치 범위와 snapping | `CLOCKREGION_X1Y0:CLOCKREGION_X2Y0`, `SNAPPING_MODE=ON`. 1단계와 클럭 리전 및 snapping 동일 | 최종 XDC:3–4, `DFX/constraints/dfx_pblock.xdc:10–12` |
| 라우팅 포함 | 1단계 XDC는 `CONTAIN_ROUTING=true`를 명시. 최종 XDC에는 해당 명령이 없고, 최종 구현 보고서는 `CONTAIN_ROUTING=1`, `EXCLUDE_PLACEMENT=1`, SLR0으로 기록 | `unified_final_v2/gate_reports/{normal,lowlight}_utilization_pblock.rpt:36–48` |
| Normal Pblock 가용 자원 | LUT 18,880, CLB registers 37,760, BRAM tile 24, DSP 216 | `unified_final_v2/gate_reports/normal_utilization_pblock.rpt:58,63,132,147` |
| DFXC BS ADDR/SIZE | RM_0 Normal `0x70800000 / 1447292 B`, RM_1 Lowlight `0x70A00000 / 1447292 B` | BD `design.components.dfx_controller_0.parameters.ALL_PARAMS`, `TF/edit_bd.tcl:14–26` |
| 런타임 | PS는 DDR `0x70000000` 예약 영역의 +`0x800000`, +`0xA00000`에 파셜을 적재하고 크기와 읽기 결과를 검증한다. 두 컨트롤러의 전환 루틴은 GPIO permit/commit 및 상태 폴링을 사용하며 DFXC의 BS 설정 레지스터를 런타임에 기록하지 않는다. | `experiment_v2/app/zcu_runtime.py:21–29,119–131`, `zcu_modes.py:64–65`, `experiment_v2/app/controller.py:124–158`, `TF/controller.py:99–127` |

이전 안전 게이트 보고서의 ADDR/SIZE 0은 이전 설계 시점이다(`unified_work/frame_idle_safety_gate/safety_gate_report_ko.md:27`). 최종 `edit_bd.tcl`이 IP 설정을 저장했다. `corrective_contract/repair_addresses.tcl:3–9`는 RM AXI control 및 DDR/QSPI 주소 세그먼트 복구를 다룬다.

| PS 코드 | 차이와 사용 근거 |
| --- | --- |
| `TF/controller.py` (MD5 `40bca21c47f17b07f01603711d5567f9`) | `fcntl.flock`; 반복 횟수 제한 폴링; `scan`은 COMPLETE에서만 허용; `swap`이 checker 완료를 직접 읽음. :16–47,99–127 |
| `experiment_v2/app/controller.py` (MD5 `09d1d8253407e9231ee30ff592027e85`) | `O_EXCL` PID 락, `time.monotonic` 타임아웃, READY에서는 실제 RM idle 확인 후 scan, `scan_outcome`이 완료 및 pending 대상 RM을 읽고 COR 완료 플래그 이중 폴링을 피함. :17–68,124–181 |
| 보드 실험과 11/19 재현 | 보드 스크립트는 `<root>/app`에서 `zcu_modes`와 `controller`를 가져온다(`2026-10-v2-board/scripts/board/board_v2_dfx_live.py:24–32,57–61`, `experiment_v2/app/zcu_modes.py:24,58`). 배포 `experiment_v2/manifest.json`의 `app/controller.py` SHA-256이 실험 코드와 `DFXISP-2026-10-yolo-replay/exp/app/controller.py`에 모두 일치했다(`9dfd2ae410b72eeff2eb4380ba0a1c7a8f9c0ff6f8d3c4535ef6e4aa2bcac581`). |

## IP 설정과 주소

`unified_work/frame_idle_safety_gate/live_config_and_preservation.json`은 TF 디렉터리의 파일이 아니며 이전 설계 스냅샷이다. 그 파일의 `config.frame_idle_permit_gpio`는 1비트 단일 채널이고 DFXC BS 주소·크기는 0이다. 아래 값은 최종 BD/XCI에서 가져왔다. Shutdown Manager 값은 이전 스냅샷의 해당 3개 `config` 항목과도 일치한다.

| IP | 파라미터 = 값 | 최종 출처 |
| --- | --- | --- |
| `dfx_controller_0` | `VS` = VS_0 하나(ID 0), `NUM_HW_TRIGGERS=2`, `TRIGGER_TO_RM={0 RM_0 1 RM_1}`, `POR_RM=RM_0`, `HAS_AXIS_STATUS=1`, `SHUTDOWN_ON_ERROR=1`, `HAS_AXI_LITE_IF=1`, `RESET_ACTIVE_LEVEL=0` | BD `design.components.dfx_controller_0.parameters.ALL_PARAMS` |
| DFXC RM_0 / RM_1 | RM_0 Normal(ID 0), RM_1 Lowlight(ID 1). 둘 다 `SHUTDOWN_REQUIRED=hw`, `RESET_REQUIRED=high`, `RESET_DURATION=8`, BS ID 0, `CLEAR=0` | 같은 `ALL_PARAMS.VS.VS_0.RM`, 각 RM 컨테이너 BD |
| `dfx_decoupler_0` | `ALWAYS_HAVE_AXI_CLK=1`. `INTF.CTRL` ID 0/AXI4LITE(주소·데이터 32, RP slave), `INTF.GMEM0` ID 1/AXI4(주소 64, 데이터 32, 읽기 경로), `INTF.GMEM1` ID 2/AXI4(주소 64, 데이터 32, 쓰기 경로). 각 `s_*`와 `rp_*` 쌍. GMEM0의 ARBURST 및 GMEM1의 AWBURST는 `PRESENT=0`. | BD `design.components.dfx_decoupler_0.parameters.ALL_PARAMS`; pin-map XCI `ip_inst.boundary.interfaces` |
| `axi_shutdown_ctrl` | `CTRL_INTERFACE_TYPE=0`, `DP_PROTOCOL=AXI4LITE`, `DP_AXI_RESP=0`, `RP_IS_MASTER=false`, `DP_AXI_DATA_WIDTH=32`, `DP_AXI_ADDR_WIDTH=32`, `DP_AXI_ID_WIDTH=0`(비활성) | XCI `*_dfx_axi_shutdown_man_0_0.xci:13–25` |
| `axi_shutdown_gmem0` | `CTRL_INTERFACE_TYPE=0`, `DP_PROTOCOL=AXI4MM`, `DP_AXI_RESP=0`, `RP_IS_MASTER=true`, `DP_AXI_DATA_WIDTH=32`, `DP_AXI_ADDR_WIDTH=64`, `DP_AXI_ID_WIDTH=1` | XCI `*_dfx_axi_shutdown_man_0_1.xci:13–25` |
| `axi_shutdown_gmem1` | `CTRL_INTERFACE_TYPE=0`, `DP_PROTOCOL=AXI4MM`, `DP_AXI_RESP=0`, `RP_IS_MASTER=true`, `DP_AXI_DATA_WIDTH=32`, `DP_AXI_ADDR_WIDTH=64`, `DP_AXI_ID_WIDTH=1` | XCI `*_dfx_axi_shutdown_man_0_2.xci:13–25` |
| `frame_idle_permit_gpio` | `C_IS_DUAL=1`, 채널 1 `C_GPIO_WIDTH=8`, `C_ALL_OUTPUTS=1`, `C_DOUT_DEFAULT=0x00000000`; 채널 2 `C_GPIO2_WIDTH=32`, `C_ALL_INPUTS_2=1` | BD의 동명 `parameters`; GPIO XCI:12–26 |
| `safety_guard` | `TIMEOUT_CYCLES=10000000` | BD `design.components.safety_guard.parameters`, `TF/edit_bd.tcl:8–12` |
| 주 클럭 | `zynq_ultra_ps_e_0/pl_clk0=100 MHz` → checker, guard, DFXC `clk/icap_clk`, ICAP bridge `icap_clk`, shutdown manager 3개, decoupler 3개, RP, permit GPIO, observer | BD `design.nets.zynq_ultra_ps_e_0_pl_clk0`, PS `PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ` |
| 리셋 | `rst_ps8_0_100M/peripheral_aresetn` → checker, guard, DFXC `reset/icap_reset`, shutdown manager 3개, decoupler 3개, GPIO, observer. RP `ap_rst_n=peripheral_aresetn & !DFXC.rm_reset`. | BD `design.nets.{rst_ps8_0_100M_peripheral_aresetn,dfx_controller_0_vsm_VS_0_rm_reset,rm_reset_not_Res,rm_aresetn_and_Res}` |

PS 주소는 BD `design.addressing["/zynq_ultra_ps_e_0"].address_spaces.Data.segments` 기준이다.

| 주소 | 범위 | 대상 / JSON 세그먼트 |
| --- | --- | --- |
| `0xA0000000` | 64 KiB | RP control · `SEG_NormalISP_0_Reg` |
| `0xA2000000` | 64 KiB | DFXC AXI-Lite · `SEG_dfx_controller_0_Reg` |
| `0xA3000000` | 64 KiB | checker control · `SEG_checker_ip_0_reg0` |
| `0xA3010000` | 64 KiB | checker status · `SEG_checker_ip_0_reg0_1` |
| `0xA3020000` | 64 KiB | permit GPIO · `SEG_frame_idle_permit_gpio_Reg` |

## 최종 연결

아래 키는 BD `design.nets` 또는 `design.interface_nets`에서 직접 확인했다.

| 출발 | 도착 | BD 키 |
| --- | --- | --- |
| `checker_ip_0/vs_hw_triggers` | `safety_guard/candidate` | `checker_ip_0_vs_hw_triggers` |
| `safety_guard/hw_triggers`, `shutdown_ack` | `dfx_controller_0/vsm_VS_0_hw_triggers`, `vsm_VS_0_rm_shutdown_ack` | `safety_guard_hw_triggers`, `safety_guard_shutdown_ack` |
| `checker_ip_0/vs_rm_shutdown_ack` | 수신 핀 없음 | `checker_ip_0_vs_rm_shutdown_ack` |
| `isp_rp/rm_ap_idle` | `safety_guard/rm_idle`, `checker_ip_0/rm_ap_idle` | `isp_rp_rm_ap_idle`. 두 RM의 `TF/idle_ip_repo/<ISP>/hdl/verilog/<ISP>.v:277`에서 `assign rm_ap_idle = ap_idle;` |
| `dfx_controller_0/vsm_VS_0_rm_shutdown_req` | shutdown manager 3개의 `request_shutdown`, `checker_ip_0/vs_rm_shutdown_req`, `safety_guard/shutdown_req` | `dfx_controller_0_vsm_VS_0_rm_shutdown_req` |
| ctrl, gmem0, gmem1 shutdown manager `in_shutdown` | `safety_guard/drain_ctrl`, `drain_read`, `drain_write` | `axi_shutdown_{ctrl,gmem0,gmem1}_in_shutdown` |
| `dfx_controller_0/vsm_VS_0_rm_decouple` | `dfx_decoupler_0/decouple`, `checker_ip_0/vs_rm_decouple`, `safety_guard/decouple` | `dfx_controller_0_vsm_VS_0_rm_decouple` |
| DFXC 상태 데이터 / 유효 | `safety_guard/dfx_status`, `status_valid` | `dfx_controller_0_vsm_VS_0_m_axis_status_t{data,valid}` |
| permit GPIO `gpio_io_o`; 가드 `guard_status` | `safety_guard/ctrl`; GPIO `gpio2_io_i` | `frame_idle_permit_gpio_gpio_io_o`, `safety_guard_guard_status` |
| DFXC `event_error`, observer `fault_now` | `response_error_or/Op1,Op2` → `safety_guard/event_error` | `dfx_controller_0_vsm_VS_0_event_error`, `response_observer_fault_now`, `response_error_or_Res` |
| `response_clear_zero/dout` | observer `safe_reset_req`, `safe_reset_confirm`, `quiescent` | `response_clear_zero_dout` |
| GMEM0/1 shutdown manager `M_AXI` | `axi_smc/S00_AXI,S01_AXI`와 observer `mon_gmem0,mon_gmem1` | `axi_shutdown_gmem{0,1}_M_AXI` |
| PS `control_smc/M00_AXI` → CTRL shutdown manager → `s_CTRL/rp_CTRL` | `isp_rp/s_axi_control` | `ps8_0_axi_periph_M00_AXI`, `axi_shutdown_ctrl_M_AXI`, `dfx_decoupler_0_rp_CTRL` |
| RP `m_axi_gmem0,1` → `rp_GMEM0,1/s_GMEM0,1` | GMEM shutdown manager `S_AXI` | `NormalISP_0_m_axi_gmem{0,1}`, `dfx_decoupler_0_s_GMEM{0,1}` |
| `checker_ip_0/m_axi_gmem0`; DFXC `M_AXI_MEM` | `checker_axi3_adapter/S_AXI`; `axi_smc/S02_AXI` | `checker_ip_0_m_axi_gmem1`(키 이름), `dfx_controller_0_M_AXI_MEM` |
| DFXC `icap_csib`, `icap_o`, `icap_rdwrb` | `icap_dfx_bridge_0`의 같은 이름 핀 | `dfx_controller_0_icap_{csib,o,rdwrb}` |
| 브리지 `icap_avail`, `icap_i`, `icap_prdone`, `icap_prerror` | DFXC의 같은 이름 핀 | `icap_dfx_bridge_0_icap_{avail,i,prdone,prerror}` |

## 보드 실험 및 재현 이미지

`unified_final_v2/SHA256SUMS` 7개를 검사해 모두 일치했다. TF의 `gate/export/dfx_zcu104_timeout_fixed_normal.xsa`와 `unified_final_v2`의 동명 XSA도 SHA-256이 같았다(`84becc37…`). 보드 재현 사본의 부팅 이미지와 두 파셜은 `2026-10-v2-board/artifacts.sha256:2–4`에 기록된 10월 파일과 일치했다. 이 사본의 11/19 보드 결과는 `DFXISP-2026-10-yolo-replay/verification/board-run.0UUDZV/verification.json`에서 600프레임, 2,400 검출 기록 및 전환 93회를 확인했다.

| 파일 | 10월 기록·11/19 보관본 SHA-256 | TF 결과와 비교 |
| --- | --- | --- |
| POR 수정 `BOOT.BIN` | `2d2a045485568b847eddf7a39d6b235f046b6c78ea15997f332d2d59ab1dbb3a` | Bootgen 헤더의 PL 구간(오프셋 `0xf190`, 길이 `0x49aa7d` 32비트 워드)을 추출했다. 동일 길이의 TF `full_normal.bit` Bootgen 변환 파일과 `cmp` 불일치(첫 차이 1,082,141바이트). 로그·비교 파일은 `build/ch2_boot/`. |
| `partial_normal_bs1.icap.bin` | `d921d7c495d6136e29f62fe2994956725317ba9095b4579edb587bf80559f8c1` | TF `partial_normal.icap.bin` SHA-256 `527020a0c0bfcd21ce0aaa395794f4181eee41c7bd3b37c17754c77efff8b708`과 다름. |
| `partial_lowlight_blc16_bs1.icap.bin` | `b739f7837e4e2c5a3592a1385d2af548322ef59ebc3822c339d73b0bea28bf1f` | TF `partial_lowlight.icap.bin` SHA-256 `60ad7095e81c41f832d14cf51da37649d3c0d025df8872e7ddc8add9491192d0`과 다름. BLC16 RM을 잠긴 보드 셸에 다시 구현한 기록은 `2026-10-v2-board/notes/2026-10-14-lowlight-isp-improvement-sweeps.md:68–72,86–91`. |

**(확인 필요)** TF와 POR 수정 보드 셸 사이의 차이를 구성 프레임 단위로 설명하는 빌드 계보, 11/19 당시 SD에서 읽은 `BOOT.BIN` 원본과 컨트롤러 모듈의 현장 해시. 위 결과는 정본의 배포·재현 파일과 실험 기록을 근거로 한다.
