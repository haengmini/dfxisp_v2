#pragma once

#include <cstdint>

// 일반 조도용 ISP RM 인터페이스 (상세: NormalISP.md)

enum NormalISPAwbMode : int {
    NORMAL_ISP_AWB_OFF = 0,  // AWB 비활성(바이패스)
    NORMAL_ISP_AWB_ON = 1,   // 프레임별 Gray-World AWB 활성
};

// 개발·분석용 최상위(AWB 모드 선택 가능)
extern "C" void NormalISP_dev(
    const uint16_t* raw_bayer,
    uint32_t* rgb_out,
    int width,
    int height,
    int awb_mode,
    int* out_width,
    int* out_height);

// 보드·DFX RM 최상위(AWB_ON 고정, LowlightISP와 동일 포트 계약)
extern "C" void NormalISP(
    const uint16_t* raw_bayer,
    uint32_t* rgb_out,
    int width,
    int height,
    int* out_width,
    int* out_height);
