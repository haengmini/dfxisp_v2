# ISP RM 제어 래퍼

`rm_control.v`가 기존 PS의 AXI4-Lite AP_CTRL 계약을 제공한다. 두 RM BD는 이 래퍼와 개별 HLS ISP를 함께 넣고, HLS의 두 AXI master를 RP 경계로 직접 연결한다. `rm_ap_idle`은 HLS `ap_idle`과 같은 레벨이다. TF RP와 동일하게 외부 interrupt 핀은 없다.

| 주소·비트 | 동작 |
| --- | --- |
| `0x00[0]` AP_START | 바이트 0의 스트로브와 bit 0이 모두 1이면 요청한다. `ap_ready`까지 유지하고 수락 시 내린다. 같은 사이클 새 쓰기는 유지한다. 0 쓰기는 요청을 취소하지 않는다. |
| `0x00[1]`, `[3]` | 각각 AP_DONE, AP_READY를 래치하고 AP_CTRL의 읽기 주소 핸드셰이크에서 클리어한다. 읽기와 새 이벤트가 겹치면 새 이벤트를 유지한다. |
| `0x00[2]` AP_IDLE | 코어의 현재 레벨. 읽기 주소 핸드셰이크에서 스냅샷을 잡는다. |
| `0x00[31:4]`, `0x04–0x0C` | 0으로 읽고 쓰기는 무시한다. Auto-restart 및 GIE/IER/ISR은 지원 범위 밖이다. |
| `0x10–0x7C` | 4바이트 정렬 주소를 HLS 제어 인터페이스에 전달한다. WSTRB와 코어 응답을 그대로 전달한다. |

RP의 물리 제어 주소 폭은 TF와 동일한 7비트이고 상위 주소는 BD 인터커넥트가 해석한다. 비정렬 주소는 `SLVERR`이며 코어에 전달하지 않는다. 쓰기 AW/W는 독립 포착하며 순서는 자유롭다. 읽기 1건과 쓰기 1건이 병행될 수 있고, 같은 방향의 후속 요청은 현재 응답을 받을 때까지 대기한다. 리셋은 모든 미완료 요청과 이벤트를 클리어한다.

PS 근거는 정본 `experiment_v2/app/controller.py:100–122`와 `zcu_modes.py:100–115`다. 이전 생성 `NormalISP_control_s_axi.v:51–68,329–379`의 AP_CTRL 메모리 맵을 대조했다.

두 ISP를 내보낸 뒤 저장소 루트에서 실행한다.

```bash
source /tools/Xilinx/Vivado/2024.1/settings64.sh && tclsh rm_wrapper/run_tb.tcl
```

[체크포인트 1 결과](../build/ch3_rm/CHECKPOINT1.md)
