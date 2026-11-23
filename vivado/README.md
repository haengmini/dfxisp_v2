# Vivado Tcl DFX 빌드

Vivado 2024.1, ZCU104(`xczu7ev-ffvc1156-2-e`). NormalISP와 LowlightISP의 HLS IP Catalog 내보내기 및 `build/ip_repo/checker_ip/`가 필요하다. HLS와 Vivado는 순서대로 실행한다.

```bash
mkdir -p build/vivado && (cd build/vivado && source /tools/Xilinx/Vivado/2024.1/settings64.sh && vivado -mode batch -source ../../vivado/build_static_bd.tcl > cp2.log 2>&1 && { n=2; for stage in synth impl bits; do n=$((n+1)); vivado -mode batch -source ../../vivado/build_dfx.tcl -tclargs "$stage" > "cp$n.log" 2>&1 || exit; done; })
```

| 단계 | 내용 | 결과 위치 |
| --- | --- | --- |
| 체크포인트 1 | RP 경계 비교와 XSim 래퍼 테스트 | `build/ch3_rm/`, [래퍼 계약](../rm_wrapper/README.md) |
| 체크포인트 2 | 두 RM과 통합 BD 생성 및 검증 | `build/vivado/project/`, `build/vivado/cp2.log` |
| 체크포인트 3 | PL 정적 요소 및 두 RM 합성 | `build/vivado/project/dfx_ch2.runs/` 및 `build/vivado/reports/` |
| 체크포인트 4 | 두 DFX 구성 배치·배선 및 타이밍·DRC 보고서 | `build/vivado/reports/` |
| 체크포인트 5 | `pr_verify` 후 전체 및 부분 비트스트림 | `build/vivado/reports/pr_verify.log`, `build/vivado/bitstreams/` |

`rm_bd.tcl`은 두 RM의 같은 RP 계약을 만든다. `bd_parameters.tcl`은 TF JSON에서 조회한 IP 파라미터다. `build_static_bd.tcl`은 새 프로젝트에서 BD를 구성하며, DPU와 그 전용 클럭·AXI·IRQ 경로를 제외한다. PS의 PL0은 100 MHz다. TF와 같은 pblock 클럭 리전 및 DFXC 주소·크기 설정을 사용한다. 명령과 중간 결과는 빌드 디렉터리의 체크포인트 보고서에 기록한다.

[체크포인트 1](../build/ch3_rm/CHECKPOINT1.md) · [체크포인트 2](../build/vivado/reports/CHECKPOINT2.md) · [체크포인트 3](../build/vivado/reports/CHECKPOINT3.md) · [체크포인트 4](../build/vivado/reports/CHECKPOINT4.md) · [체크포인트 5](../build/vivado/reports/CHECKPOINT5.md)
