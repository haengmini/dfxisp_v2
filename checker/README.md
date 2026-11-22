# checker — 정적 영역 장면 조도 판정 및 DFX 전환 트리거 IP

정본(`/home/mini/Desktop/dfxisp/dfxisp_essen`)에서 수정 없이 복사한 정적 영역(Static Region) 장면 판정기 HLS 코어와 RTL 제어 모듈이다.

> [!WARNING]
> `checker_ip.v`는 `pr_latency_probe` 모듈을 인스턴스(`u_probe`)한다. 현재 `dfxisp_v2`에 `pr_latency_probe.v`가 없으므로 `checker_ip.v` 단독으로는 컴파일되지 않는다(`pr_latency_probe.v` 편입 여부 `(확인 필요)`).

## 구성

1. **`checker.hpp`, `checker.cpp` (`checker_scan`, HLS)**  
   무상태(stateless) 프레임 단위 조도 측정 IP다. `AUTO` 모드에서 `raw[i] < dark_pixel_threshold` 화소 수(`dark_count`)를 누적해 `selected_mode`와 Schmitt 밴드 플래그 `hyst_flags`를 출력한다. 강제 모드(`NORMAL`/`LOW_LIGHT`)에서는 `dark_count=0`과 해당 모드에 맞는 `hyst_flags`를 반환한다.
2. **`checker_hysteresis.v` (RTL)**  
   Schmitt 히스테리시스 상태기계(`mode` 1-bit FF)와 `min-dwell` 카운터(`DWELL_FRAMES`, 기본 `1`)를 소유한다. 모드 전환 시 `pr_trigger`를 올리고 `pr_busy` ack를 수신할 때까지 유지하며, `pr_busy`가 올라오면 즉시 `pr_trigger`를 내려 컨트롤러가 `IDLE`로 복귀한 뒤 재트리거되는 것을 막는다. `pr_trigger` 대기 중이나 `pr_busy` 동안에는 프레임 판정을 동결한다.
3. **`dfxc_trigger_adapter.v` (RTL)**  
   `checker_hysteresis.v`의 `pr_trigger`/`mode`를 AMD DFX Controller(PG374)의 one-hot 하드웨어 트리거 `vs_hw_triggers`(`2'b01`: `RM_NORMAL`, `2'b10`: `RM_LOW_LIGHT`)로 변환한다. `pr_busy = vs_rm_shutdown_req | vs_rm_decouple`와 `vs_rm_shutdown_ack = vs_rm_shutdown_req & rm_ap_idle`을 합성한다.
4. **`checker_ip.v` (RTL)**  
   ①②③을 통합하는 정적 영역 래퍼다. `checker_scan`의 `s_axi_control`(7-bit 주소)과 `m_axi_gmem0`를 외부로 직접 연결하고, 읽기 전용 `s_axi_status` 맵을 제공한다(쓰기 시 `SLVERR` 응답, 상태 불변).
   - `0x00`: `stable_mode` (bit 0)
   - `0x04`: `frame_cnt` (32-bit)
   - `0x08`: `swap_cnt` (32-bit)
   - `0x0C`: `drain_cycles` (32-bit)
   - `0x10`: `swap_cycles` (32-bit)
5. **`tb/` (RTL 테스트벤치 3종)**  
   `checker_hysteresis_tb.v`(히스테리시스 단위), `checker_to_dfxc_tb.v`(PG374 계약 모델 연동), `checker_ip_tb.v`(`checker_scan` RTL 통합).

## 핵심 상수 및 배선

- **히스테리시스 상수 (`checker.hpp`):** `DARK_RATIO_PCT = 62`, `HYST_ENTER_PCT = 64`, `HYST_EXIT_PCT = 60`
- **보드 실운용 `dark_pixel_threshold`:** `256` (`raw12` 기준 `16 << 4`, "dark16", 근거: `dfxisp_essen/experiment_v2/app/zcu_modes.py:33`). 정본 배치 하네스(`hls/results/tools/checker_hls_tb.cpp`)의 `4096`은 하네스 전용 값이며 보드 값이 아니다.
- **`hyst_flags` 배선:** `s_axilite` 레지스터가 아니라 `ap_vld` fabric 배선으로 `checker_hysteresis.v`에 직결된다.

## HLS와 RTL을 분리한 이유

프레임 전체 화소를 순회해 어두운 화소 비율을 계산하는 무상태 측정은 HLS(`checker_scan`)로 구현하고, `pr_busy`/`shutdown_ack` 같은 사이클 단위 비동기 핸드셰이크와 상시 동작 Schmitt FSM은 RTL(`checker_hysteresis.v`, `dfxc_trigger_adapter.v`)로 분리했다. 특히 `checker_hysteresis.v`는 `pr_busy` ack 수신 즉시 `pr_trigger`를 내려 재구성 완료 후 `IDLE` 복귀 시 중복 트리거가 발생하지 않도록 보장한다.

## 확인 필요 항목

- **통합 BD의 `rm_ap_idle` 실제 연결 및 PS `permit`/`commit`과의 관계 `(확인 필요)`:**  
  `dfxc_trigger_adapter.v`는 `vs_rm_shutdown_ack = vs_rm_shutdown_req & rm_ap_idle`로 정의한다. 정본 안전 게이트 보고서(`dfxisp_essen/unified_work/frame_idle_safety_gate/safety_gate_report_ko.md`)에는 당시 통합 BD에서 `rm_ap_idle` 핀이 실제 RM의 `ap_idle`이 아니라 AXI GPIO(`0xA3020000`, 1-bit 출력, 기본값 0)에 연결되고 최종 ACK가 `request & GPIO permit & CTRL.in_shutdown & GMEM0.in_shutdown & GMEM1.in_shutdown`으로 합성된다고 기록되어 있다. 다만 최종 10월 보드 실운용 BD/XSA에서의 배선 일치 여부와 PS(`controller.py`)의 `permit`/`commit` 제어와의 정확한 관계는 `(확인 필요)`.
- **`pr_latency_probe.v`의 `dfxisp_v2` 편입 여부 `(확인 필요)`**
