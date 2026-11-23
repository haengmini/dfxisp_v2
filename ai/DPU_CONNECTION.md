# ZCU104의 DPU 연결

정본 TF의 BD·XCI 연결을 아래 순서로 읽는다. 세부 설정과 출처 키는 [DPU_CONFIG.md](DPU_CONFIG.md)에 있다.

```text
1. 클럭·리셋
   PS PL0 100 MHz ─┬─→ DPU S_AXI 제어 클럭·100 MHz 리셋
                   └─→ clk_wiz_0 ─┬─→ 600 MHz → dpu_2x_clk·리셋
                                   └─→ 300 MHz → m_axi_dpu_aclk·리셋
   clk_wiz_0.locked → 300/600 MHz 리셋 블록의 dcm_locked

2. 명령·데이터 AXI
   DPU0_M_AXI_INSTR → smc_dpu_instr → PS HPC0
   DPU0_M_AXI_DATA0 → smc_dpu_data0 → PS HP1
   DPU0_M_AXI_DATA1 → smc_dpu_data1 → PS HP2

3. 제어 주소
   PS HPM0 → control_smc/M02_AXI → DPU S_AXI 0xA1000000 / 16 MiB

4. 인터럽트
   dpu0_interrupt → xlconcat_0/In0 → PS pl_ps_irq0

5. 보드 확인
   xdputil query → B4096, 300 MHz, 1코어, 지문 0x101000056010407
   ls -l /dev/dpu → DPU 문자 디바이스
   ls -d /sys/class/uio/uio* → uio0–uio8
```

| 확인 항목 | 정본 TF 근거 | 4장 보드 명령 출력 |
| --- | --- | --- |
| DPU 구성 | DPU XCI `ARCH=4096`, `VER_DPU_NUM=1` | `xdputil query` → `DPUCZDX8G_ISA1_B4096`, 코어 1개 |
| 클럭 | BD `clk_wiz_0` 300 MHz AXI, 600 MHz 2×, 100 MHz 제어 | `DPU Frequency (MHz): 300`, `XRT Frequency (MHz): 100`. 600 MHz와 리셋 배선의 출처는 BD |
| 지문·실행 경로 | [arch.json](arch/arch.json) `0x101000056010407` | 같은 지문, `is_vivado_flow: true`. `/dev/dpu`는 문자 디바이스 |
| AXI·제어 주소·IRQ | BD 연결 및 주소 맵 `SEG_dpuczdx8g_0_reg0` | 위 보드 명령은 AXI 배선·주소·IRQ를 직접 대조하지 않는다. UIO는 9개 열거됨 |

보드 부팅 비트스트림의 TF 빌드 계보는 (확인 필요). [보드 조회 로그](../build/ai/ch4/preflight.log) · [보드 추론 결과](RESULTS.md)
