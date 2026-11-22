# checker — 정적 영역 장면 조도 판정 및 DFX 전환 트리거 IP

정본(`/home/mini/Desktop/dfxisp/dfxisp_essen`)에서 수정 없이 복사한 정적 영역(Static Region) 장면 판정기 HLS 코어와 RTL 제어 모듈이다.

## 구성

1. **`checker.hpp`, `checker.cpp` (`checker_scan`, HLS)**  
   무상태(stateless) 프레임 단위 조도 측정 IP다. `AUTO` 모드에서 `raw[i] < dark_pixel_threshold` 화소 수(`dark_count`)를 누적해 `selected_mode`와 Schmitt 밴드 플래그 `hyst_flags`를 출력한다. 강제 모드(`NORMAL`/`LOW_LIGHT`)에서는 `dark_count=0`과 해당 모드에 맞는 `hyst_flags`를 반환한다.
2. **`checker_hysteresis.v` (RTL)**  
   Schmitt 히스테리시스 상태기계(`mode` 1-bit FF)와 `min-dwell` 카운터(`DWELL_FRAMES`, 기본 `1`)를 소유한다. 모드 전환 시 `pr_trigger`를 올리고 `pr_busy` ack를 수신할 때까지 유지하며, `pr_busy`가 올라오면 즉시 `pr_trigger`를 내려 컨트롤러가 `IDLE`로 복귀한 뒤 재트리거되는 것을 막는다. `pr_trigger` 대기 중이나 `pr_busy` 동안에는 프레임 판정을 동결한다.
3. **`dfxc_trigger_adapter.v` (RTL)**  
   `checker_hysteresis.v`의 `pr_trigger`/`mode`를 AMD DFX Controller(PG374)의 one-hot 하드웨어 트리거 `vs_hw_triggers`(`2'b01`: `RM_NORMAL`, `2'b10`: `RM_LOW_LIGHT`)로 변환한다. `pr_busy = vs_rm_shutdown_req | vs_rm_decouple`와 `vs_rm_shutdown_ack = vs_rm_shutdown_req & rm_ap_idle`을 합성한다.
4. **`pr_latency_probe.v` (RTL)**  
   `checker_ip.v`가 인스턴스(`u_probe`)하는 PG374 경계 지연 계측 모듈이다. 제어 경로에 개입하지 않고 `drain_cycles`(shutdown req→ack)와 `swap_cycles`(trigger→decouple 해제)를 카운트해 `meas_valid` 펄스로 래치한다.
5. **`checker_ip.v` (RTL)**  
   ①~④를 통합하는 정적 영역 래퍼다. 최종 통합 BD 기준(`timeout_fixed/local_ip_repo/checker_no_user/src/checker_ip.v`)을 채택했으며, 초기본(`hls/checker/checker_ip.v`) 대비 차이는 미사용 AXI USER 사이드밴드 포트(`AWUSER`/`WUSER`/`ARUSER`/`RUSER`/`BUSER`) 제거(출력 미연결, 입력 응답 USER `1'b0` 고정)뿐이다. `checker_scan`의 `s_axi_control`(7-bit 주소)과 `m_axi_gmem0`는 외부로 연결하고, 읽기 전용 `s_axi_status` 맵을 제공한다(쓰기 시 `SLVERR` 응답, 상태 불변).
   - `0x00`: `stable_mode` (bit 0)
   - `0x04`: `frame_cnt` (32-bit)
   - `0x08`: `swap_cnt` (32-bit)
   - `0x0C`: `drain_cycles` (32-bit)
   - `0x10`: `swap_cycles` (32-bit)
6. **`tb/` (RTL 테스트벤치 3종)**  
   `checker_hysteresis_tb.v`(히스테리시스 단위), `checker_to_dfxc_tb.v`(PG374 계약 모델 연동), `checker_ip_tb.v`(`checker_scan` RTL 통합).
   - `checker_hysteresis_tb.v`와 `checker_to_dfxc_tb.v`는 대상 RTL이 초기본과 동일해 포트가 일치한다.
   - `checker_ip_tb.v`는 초기본 `checker_ip.v` 기준으로 작성되어 미사용 AXI USER 와이어 5개(`AWUSER`/`WUSER`/`ARUSER`/`RUSER`/`BUSER`)를 선언하고 `dut(.*)`로 연결하므로, TF 최종본 `checker_ip.v`와의 컴파일·포트 호환성은 `(확인 필요)`.

## 핵심 상수 및 배선

- **히스테리시스 상수 (`checker.hpp`):** `DARK_RATIO_PCT = 62`, `HYST_ENTER_PCT = 64`, `HYST_EXIT_PCT = 60`
- **보드 실운용 `dark_pixel_threshold`:** `256` (`raw12` 기준 `16 << 4`, "dark16", 근거: `dfxisp_essen/experiment_v2/app/zcu_modes.py:33`). 정본 배치 하네스(`hls/results/tools/checker_hls_tb.cpp`)의 `4096`은 하네스 전용 값이며 보드 값이 아니다. 11/19 재현과 11/20 실행이 같은 값을 사용하는지는 `(확인 필요)`.
- **`hyst_flags` 배선:** `s_axilite` 레지스터가 아니라 `ap_vld` fabric 배선으로 `checker_hysteresis.v`에 직결된다.

## HLS와 RTL을 분리한 이유

프레임 전체 화소를 순회해 어두운 화소 비율을 계산하는 무상태 측정은 HLS(`checker_scan`)로 구현하고, `pr_busy`/`shutdown_ack` 같은 사이클 단위 비동기 핸드셰이크와 상시 동작 Schmitt FSM은 RTL(`checker_hysteresis.v`, `dfxc_trigger_adapter.v`)로 분리했다. 특히 `checker_hysteresis.v`는 코드 주석대로 `pr_busy` ack 수신 즉시 `pr_trigger`를 내려, 컨트롤러가 `DONE` 이후 `IDLE`로 복귀할 때 불필요한 재트리거가 발생하지 않도록 막는다.
