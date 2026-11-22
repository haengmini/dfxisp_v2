# ISP HLS 빌드 결과

**2026-11-23 (KST)** · Vitis HLS 2024.1 (SW Build 5069499) · `xczu7ev-ffvc1156-2-e` · 4 ns · `vivado` · `ip_catalog`

```bash
(cd build && source /tools/Xilinx/Vitis_HLS/2024.1/settings64.sh && for isp in NormalISP LowlightISP; do ISP="$isp" FLOW=all vitis_hls -f ../hls/run_hls.tcl > "$isp.all.log" 2>&1 || exit; done)
(cd build && source /tools/Xilinx/Vitis_HLS/2024.1/settings64.sh && ISP=checker_scan FLOW=all vitis_hls -f ../hls/run_hls.tcl > checker_scan.all.log 2>&1)
```

| ISP | C-sim | C-synth latency · interval (cycles, min–max) | Est. clock (4 ns 대비) | LUT / FF / DSP / BRAM_18K / URAM | C/RTL co-sim | Export |
| --- | --- | --- | --- | --- | --- | --- |
| NormalISP | PASS 10/10 | 1–20,736,324 · 2–20,736,325 | 2.920 ns · slack 0.00 ns | 12,812 (5.56%) / 9,518 (2.07%) / 28 (1.62%) / 4 (0.64%) / 0 (0%) | PASS · RTL 7/7 | PASS · `impl/export.zip` |
| LowlightISP | PASS 11/11 | 1–8,294,434 · 2–8,294,435 | 2.920 ns · slack 0.00 ns | 7,041 (3.06%) / 4,919 (1.07%) / 14 (0.81%) / 4 (0.64%) / 0 (0%) | PASS · RTL 9/9 | PASS · `impl/export.zip` |
| checker_scan | PASS 22/22 | 1–2,073,618 · 2–2,073,619 | 2.920 ns · slack 0.00 ns | 2,380 (1.03%) / 2,354 (0.51%) / 12 (0.69%) / 1 (0.16%) / 0 (0%) | PASS · RTL 21/21 | PASS · `impl/export.zip` |

- **타이밍·자원** — 세 설계의 uncertainty는 1.08 ns이며 유효 예산 2.92 ns에서 HLS 타이밍 위반은 없었다. 자원 비율의 분모는 디바이스 가용량 230,400 / 460,800 / 1,728 / 624 / 96이다. 배치·배선 후 타이밍은 (확인 필요).
- **루프 II**
  - LowlightISP는 `PIPELINE II=1`을 요청했고 II=16을 달성했다. 비닝 출력 화소당 2×2 셀 × RGGB 4샘플로 RAW를 16회 읽으며, `gmem0`의 사이클당 1회 읽기 제약에서 16사이클이 하한이다. 최대 지연은 8,294,434사이클(≈ 960×540×16)이다.
  - NormalISP는 명시적 `PIPELINE` 없이 자동 파이프라인되었다. 3×3 창 RAW 읽기로 RGB 루프 II=9이며, `HLS 200-885` 경고는 `v_*_req` 요청을 가리킨다. AWB 스캔은 II=1이다. 최대 지연은 20,736,324사이클(≈ 1920×1080×(1+9))이다.
  - 두 설계는 10월 보드 실험과 같은 연산 구조를 사용한다. 라인 버퍼 없이 화소마다 `m_axi`를 읽는 기준 구현이며 처리량 최적화는 이 연구 범위 밖이다. 정본 기록(`dfxisp_essen/hw/docs/LowlightISP.md:401`)에서 NormalISP의 100 MHz, 602×400 프레임 실측은 142.2 ms이며 원 측정 파일은 (확인 필요). LowlightISP의 대응 실측값은 확인되지 않았다.
- **인터페이스** — 두 top의 인자 6개와 순서가 같다. `const uint16_t* raw_bayer`는 읽기용 `m_axi_gmem0`, `uint32_t* rgb_out`은 쓰기용 `m_axi_gmem1`에 매핑된다. 두 포인터의 오프셋과 `int width`, `int height`, `int* out_width`, `int* out_height`는 `s_axi_control`에 매핑된다. AXI4-Lite 레지스터 맵도 일치했다.
- **기준 벡터 검증** — C-sim은 모든 `_dev` 케이스의 픽셀과 출력 크기를 CSV와 비교했다. XSIM/Verilog co-sim은 고정 모드(AWB_ON 7개, BINNING 9개)에서 RTL 출력을 C 기준과 비교했다. 두 AXI 테스트 버퍼를 각각 2,048원소로 할당해 `depth=2048` 설정으로 co-sim을 완료했다. `add_files -tb`가 `csim/build/`, `sim/wrapc/`, `sim/wrapc_pc/`에 복사한 CSV는 V2 벡터와 바이트 단위로 일치했다.
- **checker_scan** — 합성 RAW 1,000화소와 임계값 256으로 자동 모드의 60/62/64% 경계 및 ±1화소, 강제 모드, 비양수 너비·높이를 검증했다. 널 포인터는 C-sim에서만 검증했다. RTL은 `raw_bayer`에 `m_axi_gmem0`(depth 2048), 인자와 블록 제어에 `s_axi_control`(주소 7비트)을 사용한다. `hyst_flags[31:0]`와 1비트 `hyst_flags_ap_vld`는 독립 출력 포트다(`syn/verilog/checker_scan.v:165–166`).

| 산출물 | V2 기준 경로 |
| --- | --- |
| 전체 실행 로그 | `build/<ISP>.all.log` |
| C-sim / C-synth / 인터페이스·II | `build/<ISP>/solution1/csim/report/<ISP>_csim.log`, `build/<ISP>/solution1/syn/report/{<ISP>_csynth.rpt,csynth.rpt}` |
| Co-sim | `build/<ISP>/solution1/sim/report/<ISP>_cosim.rpt` |
| Vivado IP | `build/<ISP>/solution1/impl/export.zip`, `build/<ISP>/solution1/impl/ip/` 안의 `component.xml`과 `xilinx_com_hls_<ISP>_1_0.zip` |

두 IP ZIP에 Verilog와 VHDL, AXI4-Lite 드라이버, OOC 제약 및 IP 설명자가 들어 있으며 압축 무결성 검사를 통과했다.

ISP 소스 4개와 `checker/checker.hpp`는 주석 정리를 제외한 코드가 정본과 일치했다(`g++ -E -P` 대조). 기준 벡터 CSV 2개, `checker.cpp`, checker RTL 4개, DFX 셸 RTL 4개는 해당 정본과 바이트 단위로 일치했다(`cmp` 대조). CSV 로더는 V2에서 `hls/reference_csv.hpp`로 이름과 코드 표기를 정리했다.
