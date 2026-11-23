# ZCU104 DPU 설정

TF는 정본 `unified_work/frame_idle_safety_gate/corrective_contract/timeout_fixed`다. 아래 BD는 `TF/project/dfx_zcu104.srcs/sources_1/bd/NormalISP_zcu104_design1/NormalISP_zcu104_design1.bd`, DPU XCI는 그 BD의 `ip/NormalISP_zcu104_design1_dpuczdx8g_0_0/NormalISP_zcu104_design1_dpuczdx8g_0_0.xci`다. 이 빌드에서는 두 파일에서 설정값을 읽었다.

| 항목 | 최종 TF 값 | 출처 |
| --- | --- | --- |
| DPU IP | `xilinx.com:ip:dpuczdx8g:4.1` | BD `design.components.dpuczdx8g_0.vlnv` |
| 구성 | `ARCH=4096`, `ARCH_PP=8`, `ARCH_ICP=16`, `ARCH_OCP=16`, `VER_DPU_NUM=1`, `SFM_ENA=0` | DPU XCI `ip_inst.parameters.component_parameters` |
| URAM과 DSP | `URAM_N_USER=46`, URAM 뱅크 IMG/WGT/BIAS 5/17/1, `SUM_DSP_NUM=710`, `SUM_BRAM_N=82.5` | BD `components.dpuczdx8g_0.parameters.URAM_N_USER`, DPU XCI component parameters |
| DPU 연산 | DepthWiseConv 활성, 평균 풀링 활성, ReLU/LeakyReLU/ReLU6, AXI4, HP 128비트 | DPU XCI `DWCV_ENA`, `POOL_AVERAGE`, `CONV_RELU_ADDON`, `AXI_PROTOCOL`, `HP_DATA_BW` |
| 클럭 위저드 | PS PL0 100 MHz → `clk_wiz_0`. `clk_out1` 600 MHz → `dpu_2x_clk`, `clk_out2` 300 MHz → `m_axi_dpu_aclk` 및 DPU SmartConnect 3개·PS HPC0/HP1/HP2. 두 출력 Matched Routing 활성 | BD `components.clk_wiz_0.parameters`, `nets.{zynq_ultra_ps_e_0_pl_clk0,clk_wiz_0_clk_out1,clk_wiz_0_clk_out2}` |
| 제어 클럭·리셋 | DPU 제어 100 MHz 독립 클럭, `rst_ps8_0_100M/peripheral_aresetn` → `s_axi_aresetn`. PL reset은 위저드와 두 DPU reset 블록에 전달 | BD `nets.{zynq_ultra_ps_e_0_pl_clk0,rst_ps8_0_100M_peripheral_aresetn,zynq_ultra_ps_e_0_pl_resetn0}`, XCI `S_AXI_CLK_INDEPENDENT=1` |
| DPU 리셋 | `clk_wiz_0/locked` → 두 reset 블록 `dcm_locked`. `rst_dpu_600M/peripheral_aresetn` → `dpu_2x_resetn`, `rst_dpu_300M/peripheral_aresetn` → `m_axi_dpu_aresetn` 및 DPU SmartConnect 3개 | BD `nets.{clk_wiz_0_locked,rst_dpu_600M_peripheral_aresetn,rst_dpu_300M_peripheral_aresetn}` |
| 명령 AXI | `DPU0_M_AXI_INSTR` → `smc_dpu_instr` → PS `S_AXI_HPC0_FPD` | BD `interface_nets.{dpuczdx8g_0_DPU0_M_AXI_INSTR,smc_dpu_instr_M00_AXI}` |
| 데이터 AXI | `DPU0_M_AXI_DATA0` → `smc_dpu_data0` → HP1, `DPU0_M_AXI_DATA1` → `smc_dpu_data1` → HP2. SmartConnect 각각 `NUM_SI=1` | BD `interface_nets.dpuczdx8g_0_DPU0_M_AXI_DATA{0,1}`, `interface_nets.smc_dpu_data{0,1}_M00_AXI`, `components.smc_dpu_*` |
| 제어 주소 | PS HPM0 → `control_smc/M02_AXI` → `dpuczdx8g_0/S_AXI`, `0xA1000000` / 16 MiB | BD `interface_nets.ps8_0_axi_periph_M02_AXI`, 주소 키 `SEG_dpuczdx8g_0_reg0`(4525–4529행) |
| 인터럽트 | `dpu0_interrupt` → `xlconcat_0/In0` → PS `pl_ps_irq0` | BD `nets.{dpuczdx8g_0_dpu0_interrupt,xlconcat_0_dout}` |
| 컴파일 지문 | `0x101000056010407` | [arch.json](arch/arch.json), 정본 `hw/NormalISP_DPU/arch.json` |

9월 계획서 `dfxisp_essen/hw/docs/NormalISP_DPU_plan.md:24–32,77–78`에는 DATA0/1이 HP0/HP1, ISP가 HP2로 기록되어 있고 `clk_out1/2`는 300/600 MHz 순이다. TF 최종 BD는 DATA0/1이 HP1/HP2, ISP와 ICAP·checker가 HP0을 공유하고, 위저드 출력 순서는 600/300 MHz다. 명령 AXI의 HPC0과 100 MHz 제어 클럭 및 `0xA1000000` 주소는 일치한다.

보드에서 `xdputil query`로 B4096, 300 MHz, 1개 코어, Softmax 비활성, 지문 `0x101000056010407`, `is_vivado_flow=true`를 확인했다. 각 해당 TF 값 및 arch와 일치한다. 이 확인은 지문과 구성의 일치에 대한 근거다. 보드가 부팅한 전체 비트스트림의 TF 빌드 계보는 (확인 필요). [보드 점검 로그](../build/ai/board_preflight.log)
