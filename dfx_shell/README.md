# dfx_shell — PL 정적 요소 DFX 제어·안전·ICAP 브리지 RTL

PL 정적 요소(Static Logic) RTL 4개는 정본의 최종 통합 설계 `timeout_fixed`와 바이트 단위로 일치한다(`cmp` 대조). ICAP 브리지는 TF 프로젝트의 `sources_1/imports/rtl/`에서, 나머지 3개는 TF 루트에서 대조했다.

## 역할 구분: AMD IP vs 사용자 안전 로직

`dfx_safety_guard`는 AMD DFX Controller가 요구하는 필수 IP가 아니다. AMD 제공 IP와 본 연구의 사용자 로직의 역할은 다음과 같이 구분된다.

- **AMD IP가 수행하는 일:**
  - **DFX Controller (PG374):** hardware shutdown `req`/`ack` 프로토콜, DDR 비트스트림 fetch, ICAP 구동, RP 격리(`decouple`) 및 리셋. PG374에 따라 일단 접수된 하드웨어 트리거는 취소할 수 없다(*"Triggers cannot be canceled"*).
  - **DFX AXI Shutdown Manager (PG377):** RP 경계의 진행 중 AXI 트랜잭션 완료 대기(`in_shutdown`으로 drain 완료 표시) 및 shutdown 중 신규 요청 차단·응답 처리.
- **사용자 로직(`dfx_shell/`)이 수행하는 일:**
  - RM 유휴 상태 및 3개 AXI 경로 drain 확인 후 `shutdown_ack` 생성, 트리거 발행 이전에만 취소 가능한 `permit`/`commit` 게이트, AXI 오류 응답(`SLVERR`/`DECERR`) 감시 및 fault 래치, 타임아웃 감지.
- **근거 문서:**
  - AMD PG374 (`dfxisp_essen/unified_work/frame_idle_safety_gate/corrective_contract/pg374.pdf`, v1.0, 2020 — 설계에 사용한 Vivado 2024.1 버전과의 완전 일치 여부는 `(확인 필요)`), AMD PG377 (`in_shutdown` 정의).
  - 설계 안전 정책 근거: `dfxisp_essen/unified_work/frame_idle_safety_gate/safety_gate_report_ko.md` (반례 #22: 오류 후 isolation 해제 시 재트리거 위험, 반례 #23: RM 동작 중 잘못된 SW permit 시 ACK 발행 위험). 이 보고서는 `dfx_safety_guard`가 도입되기 전의 `dfxc_trigger_adapter` 기반 설계를 검토한 결과다.

---

## 모듈별 상세

### 1. `icap_dfx_bridge.v`
- **역할:** DFX Controller와 Zynq UltraScale+ `ICAPE3` 프리미티브를 연결하는 PL 정적 요소 브리지다.
- **포트(신호명은 DFX Controller 기준):**
  - 입력: `icap_clk` → `ICAPE3.CLK`, `icap_o[31:0]` → `ICAPE3.I`, `icap_csib` → `ICAPE3.CSIB`, `icap_rdwrb` → `ICAPE3.RDWRB`
  - 출력: `icap_i[31:0]` ← `ICAPE3.O`, `icap_avail` ← `ICAPE3.AVAIL`, `icap_prdone` ← `ICAPE3.PRDONE`, `icap_prerror` ← `ICAPE3.PRERROR`

### 2. `dfx_safety_guard.v`
- **파라미터:** RTL 기본값은 `TIMEOUT_CYCLES=1024`이며, 최종 BD는 `TIMEOUT_CYCLES=10000000`으로 설정한다(`TF/edit_bd.tcl:8–12`).
- **입출력:**
  - 입력: `clk`, `rst_n`, `ctrl[7:0]`, `candidate[1:0]`, `rm_idle`, `drain_ctrl`, `drain_read`, `drain_write`, `shutdown_req`, `decouple`, `event_error`, `status_valid`, `dfx_status[31:0]`
  - 출력: `hw_triggers[1:0]`, `shutdown_ack`, `guard_status[31:0]`
- **`ctrl[7:0]` 비트 정의 (등록된 MMIO 입력 전제):**
  - `[0]=enable`, `[1]=permit`, `[2]=commit`(상승 에지), `[3]=cancel`, `[4]=fault`, `[5]=recover`(상승 에지), `[6]=recovery_verified`
- **핵심 조건 및 동작:**
  - `busy = shutdown_req | decouple`, `status_error = status_valid && (dfx_status[6:3] != 0)`, `full_ok = status_valid && !dfx_status[7] && !status_error && (dfx_status[2:0] == 7)`, `hazard = event_error | status_error | ctrl[4]`, `safe = rm_idle && drain_ctrl && drain_read && drain_write`.
  - **`hw_triggers`:** `enabled && !fault && !hazard && ctrl[0] && ctrl[1] && rm_idle && !ctrl[3]`일 때만 `pulse`(1사이클)를 출력한다. `pulse`는 `commit` 상승 에지 && `pending && !inflight && !busy && ctrl[1] && rm_idle && full_ok` 조건에서 `target`으로 적재된다.
  - **`shutdown_ack`:** `enabled && !fault && !hazard && ctrl[0] && ctrl[1] && shutdown_req && safe` 조건을 모두 만족할 때만 1이 된다.
  - **취소 규칙 (`"Cancellation is ONLY possible before the DFXC rising-edge trigger"`):** `ctrl[3]`(cancel)이 `pending` 상태(트리거 발행 전)에 들어오면 `pending <= 0`으로 안전하게 취소한다. 그러나 이미 트리거가 발행된 `inflight` 상태에서 `ctrl[3]`이 들어오면 DFXC 내부의 접수된 트리거는 취소할 수 없으므로 `fault <= 1`, `enabled <= 0`으로 fail-closed 래치한다.
  - **타임아웃 및 복구:** `inflight` 중 `TIMEOUT_CYCLES - 1`에 도달하면 `fault <= 1`, `enabled <= 0`, `pending <= 0`을 래치하며 `inflight`를 유지한다. 복구는 `!hazard` 상태에서 `recover` 상승 에지 && `ctrl[6]`(`recovery_verified`) && `!ctrl[0] && !ctrl[1] && candidate==0 && !busy && !pending && !inflight && full_ok`일 때만 `fault <= 0`을 허용한다.
  - **`guard_status[7:0]`:** `{seen_busy, (target==2), inflight, pending, fault, enabled, shutdown_ack, ready_idle}` (상위 24비트는 0).

### 3. `axi_response_error_observer.v`
- **역할:** 정적 PL 클럭에서 동작하는 수동(passive) AXI 응답 오류 감시기다(RM 리셋과 분리). `RRESP`/`BRESP`의 `2'b00`(OKAY)·`2'b01`(EXOKAY)은 허용하고, `rresp[1]`/`bresp[1]`이 1인 `2'b10`(SLVERR)·`2'b11`(DECERR)을 fail-closed로 감지한다.
- **신호:**
  - `read_error = rvalid && rready && rresp[1]` → `read_fault` 래치
  - `write_error = bvalid && bready && bresp[1]` → `write_fault` 래치
  - `fault_hold = read_fault | write_fault`, `fault_now = fault_hold | read_error | write_error` (에지 경쟁 방지를 위한 조합 선행 출력)
  - 클리어 조건: `safe_reset_req && safe_reset_confirm && quiescent && !rvalid && !bvalid`일 때만 `read_fault`/`write_fault` 해제.
- **보조 모듈 `response_authorization_gate`:** `guard_event_error = existing_event_error | response_fault_now`, `start_authorized`, `recovery_authorized` 정책 신호를 생성한다.

### 4. `axi_response_monitor_wrapper.v`
- **역할:** Vivado BD에서 기존 AXI 연결을 끊지 않고 수동 감시하기 위해 두 개의 `MONITOR` 모드 AXI4 인터페이스(`mon_gmem0`, `mon_gmem1`, 전 포트 입력)를 노출하고 내부에 `axi_response_error_observer`를 인스턴스한다.
- **감시 대상:** `mon_gmem0`의 읽기 응답(`RVALID`/`RREADY`/`RRESP`)과 `mon_gmem1`의 쓰기 응답(`BVALID`/`BREADY`/`BRESP`)을 `u_observer`에 연결한다.

---

## 최종 통합 BD 연결

TF의 `project/dfx_zcu104.srcs/sources_1/bd/NormalISP_zcu104_design1/NormalISP_zcu104_design1.bd`에서 `design.nets`와 `design.interface_nets`를 대조했다. [최종 BD 연결과 IP 설정](../build/ch2_facts.md)

| 출발 핀 / 인터페이스 | 도착 핀 / 인터페이스 | 비고 |
|---|---|---|
| `axi_shutdown_gmem0/M_AXI` | `response_observer/mon_gmem0` | AXI4 MONITOR 수동 연결 (`rresp`/`rvalid`/`rready` 감시) |
| `axi_shutdown_gmem1/M_AXI` | `response_observer/mon_gmem1` | AXI4 MONITOR 수동 연결 (`bresp`/`bvalid`/`bready` 감시) |
| `safety_guard/clk`, `rst_n` | `response_observer/clk`, `rst_n` | 동일 정적 클럭·리셋 공유 |
| `response_clear_zero/dout` (`1'b0`) | `response_observer/{safe_reset_req, safe_reset_confirm, quiescent}` | 런타임 클리어 비활성화(fault 유지) |
| `dfx_controller_0/vsm_VS_0_event_error` | `response_error_or/Op1` | 1-bit OR (`util_vector_logic`) |
| `response_observer/fault_now` | `response_error_or/Op2` | 조합 선행 오류 신호 |
| `response_error_or/Res` | `safety_guard/event_error` | DFXC 오류 또는 AXI 오류 시 가드 fault 래치 |
| `isp_rp/rm_ap_idle` | `safety_guard/rm_idle`, `checker_ip_0/rm_ap_idle` | BD 키 `isp_rp_rm_ap_idle`. 정본은 두 ISP의 HLS 생성 Verilog에 `assign rm_ap_idle = ap_idle;`을 삽입했다(`TF/idle_ip_repo/NormalISP/hdl/verilog/NormalISP.v:277`, LowlightISP도 277행). |
| `checker_ip_0/vs_hw_triggers` → `safety_guard/candidate` | `safety_guard/hw_triggers` → DFXC `vsm_VS_0_hw_triggers` | checker 내부 `dfxc_trigger_adapter`가 후보를 생성하고 가드가 전환 요청을 승인한다. |
| `safety_guard/shutdown_ack` | DFXC `vsm_VS_0_rm_shutdown_ack` | 가드는 요청, permit, RM idle, 세 경로의 drain 및 오류 상태로 ACK를 산출한다(`TF/dfx_safety_guard.v:28–31`). |
| permit GPIO `gpio_io_o[7:0]`; 가드 `guard_status[31:0]` | `safety_guard/ctrl`; GPIO `gpio2_io_i` | BD 키 `frame_idle_permit_gpio_gpio_io_o`, `safety_guard_guard_status` |
| DFXC `icap_o`, `icap_rdwrb`, `icap_csib`; 브리지 `icap_i`, `icap_avail`, `icap_prdone`, `icap_prerror` | 상대 모듈의 같은 이름 핀 | BD 키 `dfx_controller_0_icap_*`, `icap_dfx_bridge_0_icap_*` |

`safety_gate_report_ko.md:30`의 GPIO에서 `rm_ap_idle`을 공급하는 배선은 가드 도입 이전 설계 기준이다. 최종 BD는 RM idle과 PS permit을 가드의 별도 입력으로 받는다. PS는 GPIO로 permit/commit을 쓰고 `GPIO+8`에서 상태를 폴링한다(`experiment_v2/app/controller.py:124–158`).

10월 실험과 11월 19일 재현의 보관 부팅 이미지 및 두 파셜은 10월 매니페스트와 SHA-256이 일치한다. 두 파셜과 부팅 이미지의 PL 페이로드는 TF의 해당 산출물과 바이트가 다르다. [비트스트림 비교와 출처](../build/ch2_facts.md)

## 확인 필요 항목

- TF에서 POR 수정 보드 셸로 이어지는 구성 프레임 수준의 차이와 11월 19일 SD·보드 파일의 현장 해시 `(확인 필요)`.
- 로컬 PG374 문서(`pg374.pdf`, v1.0, 2020)와 Vivado 2024.1 `dfx_controller` IP 동작의 완전 일치 여부 `(확인 필요)`.
