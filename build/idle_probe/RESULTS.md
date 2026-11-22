# RM idle 노출 탐색 결과

Vitis HLS 2024.1, `xczu7ev-ffvc1156-2-e`, 4 ns, Vivado IP flow. V2 ISP 소스는 기준 비교에 사용했고, 후보 구현은 이 디렉터리의 복사본에서만 빌드했다.

**결론. 적용 권장안 없음.** 실험한 후보는 R1–R4를 동시에 충족하지 못했다. 아래 패치는 관측을 재현하기 위한 후보별 diff다. V2에 적용하지 않았다.

| 후보 | R1 AXI-Lite 제어 | R2 두 RM 포트 집합 | R3 픽셀·크기 검증 | R4 idle 의미 |
| --- | --- | --- | --- | --- |
| (a) `config_interface` / pragma | 기준 AP_CTRL 및 인자 맵 유지 | 기준 포트 일치 | 기준 ISP 10/10·11/11 | 공식 옵션에서 AXI-Lite에 묶인 `ap_idle`을 별도 포트로 함께 내보내는 옵션을 찾지 못했다. 기준 RTL의 `ap_idle`은 내부 신호다. |
| (b) `b_hs.patch`, return을 `ap_ctrl_hs`로 교체 | 실패. 인자 오프셋은 유지되지만 `0x00`은 reserved, AXI-Lite의 start/done/idle 및 interrupt 제거 | 일치. 양쪽에 `ap_start`, `ap_done`, `ap_idle`, `ap_ready` 추가, `interrupt` 제거 | PASS | 외부 `ap_idle`의 reset/start/done 동작 확인. PS가 이전처럼 AXI-Lite로 프레임을 시작할 수 없다. |
| (b) `b_both.patch`, return에 두 pragma 선언 | 일치. `s_axilite`가 제어를 소유 | 일치. 새 외부 핀 없음 | PASS | 내부 `ap_idle`만 변화하며 외부 핀이 없다. |
| (c) `c_none.patch`, `volatile bool* busy` + `ap_none` | 일치 | 일치. `busy[0:0]` | PASS | reset 직후 0, start 시 1. done 동안만 0이고 직후 유휴 상태에서 다시 1. 반전해도 지속되는 idle 레벨을 만들지 못했다. |
| (c) `c_vld.patch`, 같은 출력 + `ap_vld` | 일치 | 일치. `busy[0:0]`, `busy_ap_vld` | PASS | 값은 유효 펄스에서만 정의된다. reset 및 프레임 처리 중 유효 펄스가 없을 때 `X`를 관측했다. |
| (c) `c_reg.patch`, `ap_none register` | 일치 | 일치. `busy[0:0]` | PASS | start 뒤 한 사이클 늦게 1이 되고 다음 사이클부터 완료 전까지 0으로 돌아갔다. |
| (c) `c_join.patch`, `ap_none` + 단일 완료 경로 | 일치 | 일치. `busy[0:0]` | PASS | 정상 처리 완료 직후 다시 1이 되는 동작이 재현되었다. |

각 행의 실제 후보 두 ISP는 C-sim PASS 10/10·11/11 및 Verilog/XSim co-sim PASS(RTL Normal 7개, Lowlight 9개)를 기록했다. `b_hs`의 co-sim은 생성 BFM의 외부 start 입력으로 구동되므로 기존 PS의 AXI-Lite 실행 호환성을 뜻하지 않는다. C/RTL 핸드셰이크는 생성된 snapshot을 XSim에서 다시 실행해 DUT VCD를 기록했다.

- **레지스터 판정** — `syn/verilog/<ISP>_control_s_axi.v`의 주소·비트 명세를 기준 RTL과 대조했다. `b_hs`를 제외한 후보는 AP_CTRL 및 6개 인자 맵이 동일하다. `b_hs`도 인자 오프셋(`0x10/0x14`, `0x1c/0x20`, `0x28`, `0x30`, `0x38/0x3c`, `0x48/0x4c`)은 유지한다.
- **파형 근거** — 각 `<후보>/work/<ISP>/solution1/sim/verilog/idle.vcd`와 [첫 프레임 및 전체 이벤트 요약](wave_results.txt). Normal `c_none` 예에서 `ap_start` 상승 294 ns에 busy=1, `ap_done` 5966 ns에 busy=0, 5970 ns에 `ap_idle=1`인데 busy=1이다. `c_none` RTL에서 해당 정상 완료 경로는 조합 출력만 0을 쓰고 `busy_preg`를 0으로 저장하지 않았다. 두 ISP에서 같은 현상을 확인했다.
- **문서 근거** — UG1399 2024.1의 [Block-Level Control Protocols](https://docs.amd.com/r/2024.1-English/ug1399-vitis-hls/Block-Level-Control-Protocols), [S_AXILITE Control Register Map](https://docs.amd.com/r/2024.1-English/ug1399-vitis-hls/S_AXILITE-Control-Register-Map), [config_interface](https://docs.amd.com/r/2024.1-English/ug1399-vitis-hls/config_interface), [pragma HLS interface](https://docs.amd.com/r/2024.1-English/ug1399-vitis-hls/pragma-HLS-interface). 설치 도구의 `help config_interface` 출력은 `probe.log` 앞부분에 있다.
- **다시 실행한 이유** — 첫 두 시도는 HLS 프로젝트 상위 디렉터리 아래의 입력 경로를 클래식 도구가 잘못 기록해 C-sim 링크에서 설계 소스를 누락시켰다. 후보별 `work/`와 `inputs/`를 분리한 뒤 위 결과를 얻었다. 원 로그는 `probe_first.log`, `probe_second.log`에 보관했다.

| 후보 | Normal LUT / FF | Lowlight LUT / FF |
| --- | --- | --- |
| 기준 / `b_both` | 12,812 / 9,518 | 7,041 / 4,919 |
| `b_hs` | 12,812 / 9,512 | 7,041 / 4,913 |
| `c_none` | 12,824 / 9,456 | 7,053 / 4,857 |
| `c_vld` | 12,824 / 9,455 | 7,053 / 4,856 |
| `c_reg` | 12,818 / 9,455 | 7,049 / 4,856 |
| `c_join` | 12,826 / 9,519 | 7,055 / 4,920 |

모든 후보의 추정 클럭은 2.920 ns(목표 4 ns, uncertainty 1.08 ns)였다. DSP / BRAM_18K / URAM은 Normal `28 / 4 / 0`, Lowlight `14 / 4 / 0`으로 기준과 동일했다. 보고서는 `<후보>/work/<ISP>/solution1/syn/report/<ISP>_csynth.rpt`에 있다. 차이는 ISP 로직 변경 없이 제어 구조와 스케줄링에서 발생했다.
