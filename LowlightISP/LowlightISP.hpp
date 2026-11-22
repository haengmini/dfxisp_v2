#pragma once

#include <cstdint>

// 저조도용 ISP RM 인터페이스 (상세: LowlightISP.md)

enum LowlightISPBinning : int {
    LOWLIGHT_ISP_BIN_SUBSAMPLE = 0,  // 단일 RGGB 셀 서브샘플링
    LOWLIGHT_ISP_BIN_BINNING = 1,    // 2x2 RGGB 셀 평균 비닝
};

// 개발·분석용 최상위(비닝 모드 선택 가능)
extern "C" void LowlightISP_dev(
    const uint16_t* raw_bayer,
    uint32_t* rgb_out,
    int width,
    int height,
    int bin_mode,
    int* out_width,
    int* out_height);

// 보드·DFX RM 최상위(BINNING 고정, NormalISP와 동일 포트 계약)
extern "C" void LowlightISP(
    const uint16_t* raw_bayer,
    uint32_t* rgb_out,
    int width,
    int height,
    int* out_width,
    int* out_height);
