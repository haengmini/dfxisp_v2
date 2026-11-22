# checker_ip Vivado 패키징 결과

Vivado 2024.1 batch에서 `hls/package_checker_ip.tcl`을 실행해 `build/ip_repo/checker_ip/component.xml`을 생성했다. 비교 기준은 TF의 `local_ip_repo/checker_no_user/component.xml`이다. A에서 내보낸 Verilog 6개와 V2의 checker RTL 4개를 패키징했다. Vivado `ipx::check_integrity`를 통과했고 패키지의 RTL도 `synth_design -rtl`로 정교화했다.

| 항목 | TF | 재현 결과 |
| --- | --- | --- |
| VLNV | `user.org:user:checker_ip:1.1` | 일치 |
| `s_axi_control` | AXI slave, AWADDR/ARADDR 7비트, 데이터 32비트, 포트 맵 17개, `reg0` 4 KiB | 일치 |
| `s_axi_status` | AXI slave, AWADDR/ARADDR 6비트, 데이터 32비트, 포트 맵 17개, `reg0` 4 KiB | 일치 |
| `m_axi_gmem0` | AXI master, 주소 64비트, 데이터 32비트, 포트 맵 40개, USER 포트 없음. USER 폭 파라미터 5개 모두 0 | 최초 자동 추론은 USER 폭 파라미터를 생략했다. Tcl의 `ipx::add_bus_parameter`와 `set_property`로 0을 명시한 뒤 일치 |
| `vs_hw_triggers`, `vs_rm_*`, `rm_ap_idle` | `vs_hw_triggers[1:0]` 출력, `vs_rm_shutdown_ack` 출력, `vs_rm_shutdown_req`, `vs_rm_decouple`, `rm_ap_idle` 입력 | 전부 일치 |
| 클럭·리셋 | `aclk` → 3개 AXI 인터페이스 및 `aresetn`, 리셋 `ACTIVE_LOW` | 일치 |
| IRQ 및 파라미터 | `checker_interrupt=LEVEL_HIGH`, `DWELL_FRAMES=1` | 일치 |
| 전체 포트/버스 및 메모리 | 포트 82개, 버스 인터페이스 6개, memory map 2개, master address space 1개 | 이름·방향·폭, bus별 포트 맵·파라미터 값, memory map 및 address space 값 일치 |

패키지 XML 전체는 생성 시각, UI 표시 이름·설명, 파일 목록과 Vivado가 추가한 속성 때문에 다르다. HLS가 새로 생성한 모듈 이름에는 현재 소스 줄 번호가 반영됐다. Vivado는 패키지 수준의 `FREQ_HZ`, 제품 가이드 누락 및 설명 문구 기본값을 경고했다. 기준 TF XML에도 `aclk`의 고정 `FREQ_HZ` 설정은 없고, 최종 통합 BD에서 100 MHz가 공급된다.

로그는 `build/checker_ip_package.log`와 `build/checker_ip_elab.log`에 있다. 정교화는 패키지의 소스 연결 확인이며 최종 통합 BD 재합성 및 배치·배선은 이번 결과 범위 밖이다.
