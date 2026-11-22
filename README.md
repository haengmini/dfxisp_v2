# DFXISP v2

**FPGA의 동적 부분 재구성을 이용한 조도 적응형 영상 처리 아키텍처**  
AMD ZCU104(`xczu7ev-ffvc1156-2-e`)에서 동적 부분 재구성(DFX)을 이용해 일반 조도용 `NormalISP`와 저조도용 `LowlightISP`를 단일 재구성 영역(RP)에 상호배타적으로 교체하는 하드웨어 아키텍처 정리 저장소입니다.

## 구성

```text
dfxisp_v2/
├── Description.md      # 연구 종합 문서 (연구 개요, 연구 흐름, HLS C++ 소스 상세)
├── NormalISP/          # 일반 조도용 ISP RM HLS C++ 소스 (풀해상도 H×W)
├── LowlightISP/        # 저조도용 ISP RM HLS C++ 소스 (2×2 비닝 H/2×W/2)
└── vectors/            # 비트 단위 회귀 검증용 고정 골든 벡터 CSV
```

> `vectors/`의 골든 벡터 CSV(`NormalISP_vectors.csv`, `LowlightISP_vectors.csv`)는 독립 Python 구현에서 생성한 고정 회귀 픽스처입니다.

## 환경

- **보드:** AMD ZCU104 (`xczu7ev-ffvc1156-2-e`)
- **도구:** Vitis HLS 2024.1, Vivado 2024.1

자세한 연구 배경, 제안 구조, 검증 현황 및 소스 상세는 [Description.md](Description.md)를 참고하세요.
