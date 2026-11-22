# DFXISP v2

**FPGA의 동적 부분 재구성을 이용한 조도 적응형 영상 처리 아키텍처**  
AMD ZCU104(`xczu7ev-ffvc1156-2-e`)에서 동적 부분 재구성(DFX)을 이용해 일반 조도용 `NormalISP`와 저조도용 `LowlightISP`를 단일 재구성 영역(RP)에 상호배타적으로 교체하는 하드웨어 아키텍처 정리 저장소입니다.

## 구성

```text
dfxisp_v2/
├── Description.md      # 연구 개요, 연구 흐름, ISP·DFX·AI·PetaLinux·End-to-End 상세
├── NormalISP/          # 일반 조도용 ISP RM HLS C++ 소스 (풀해상도 H×W)
├── LowlightISP/        # 저조도용 ISP RM HLS C++ 소스 (2×2 비닝 H/2×W/2)
├── vectors/            # 비트 단위 회귀 검증용 고정 기준 벡터 CSV
├── checker/            # Scene Checker HLS, RTL 및 테스트벤치
├── dfx_shell/          # DFX 전환을 제어하는 PL 정적 요소(Static Logic) RTL
└── hls/                # Tcl 빌드·패키징과 실행 결과
```

> `vectors/`의 기준 벡터 CSV(`NormalISP_vectors.csv`, `LowlightISP_vectors.csv`)는 독립 Python 구현에서 생성한 고정 회귀 픽스처입니다.

ISP 소스 4개와 `checker/checker.hpp`의 코드는 주석 정리를 제외하면 정본과 동일합니다(`g++ -E -P` 대조). 기준 벡터 CSV, `checker.cpp`, checker 및 DFX 셸 RTL은 해당 정본과 바이트 단위로 일치합니다(`cmp` 대조).

## 환경

- **보드:** AMD ZCU104 (`xczu7ev-ffvc1156-2-e`)
- **도구:** Vitis HLS 2024.1, Vivado 2024.1

자세한 연구 배경, 제안 구조, 검증 현황 및 소스 상세는 [Description.md](Description.md)를 참고하세요.

## HLS 빌드(Tcl)

저장소 루트에서 다음 명령을 실행하면 Vitis HLS 2024.1이 두 ISP를 순서대로 C-sim → C-synth → C/RTL co-sim → Vivado IP Catalog 내보내기까지 실행합니다.

```bash
mkdir -p build && (cd build && source /tools/Xilinx/Vitis_HLS/2024.1/settings64.sh && for isp in NormalISP LowlightISP; do ISP="$isp" FLOW=all vitis_hls -f ../hls/run_hls.tcl || exit; done)
```

checker도 같은 Tcl에서 실행합니다.

```bash
mkdir -p build && (cd build && source /tools/Xilinx/Vitis_HLS/2024.1/settings64.sh && ISP=checker_scan FLOW=all vitis_hls -f ../hls/run_hls.tcl)
```

`ISP`는 `NormalISP`, `LowlightISP`, `checker_scan` 중 하나이며, `FLOW`는 `csim`, `csynth`, `cosim`, `export`, `all` 중 하나입니다. `cosim`과 `export`는 먼저 C-synth를 실행합니다. 각 실행은 `build/<ISP>/` 프로젝트를 초기화하고 `solution1`을 생성합니다. 스크립트는 자체 경로로 소스와 프로젝트를 찾으며, 실행기 로그도 `build/`에 두려면 예시처럼 해당 디렉터리에서 호출합니다.

`add_files -tb`로 등록한 기준 CSV는 HLS가 C-sim과 co-sim 작업 폴더에 복사하며, 테스트벤치는 두 단계 모두 파일 이름만으로 읽습니다.

설정과 실행 결과는 [hls/RESULTS.md](hls/RESULTS.md)에 있습니다.

## checker IP 패키징(Tcl)

checker HLS 내보내기가 완료된 후 Vivado에서 `build/ip_repo/checker_ip/`를 생성합니다.

```bash
(cd build && source /tools/Xilinx/Vivado/2024.1/settings64.sh && vivado -mode batch -source ../hls/package_checker_ip.tcl)
```

최종 통합 설계와 비교한 포트 및 인터페이스는 [checker IP 패키징 결과](build/checker_ip_comparison.md)에 정리했습니다.
