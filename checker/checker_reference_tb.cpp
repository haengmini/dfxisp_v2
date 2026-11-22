#include "checker.hpp"

#include <algorithm>
#include <array>
#include <iostream>
#include <string>

extern "C" void checker_scan(
    const uint16_t* raw_bayer, int width, int height, int mode,
    uint16_t dark_pixel_threshold, int verdict_pct, int enter_pct, int exit_pct,
    int* selected_mode, int* hyst_flags, int* dark_count);

namespace {
constexpr int kWidth = 100;
constexpr int kHeight = 10;
constexpr uint16_t kThreshold = 256;
constexpr int kVerdict = 62;
constexpr int kEnter = 64;
constexpr int kExit = 60;

struct Result {
    int mode;
    int flags;
    int dark;
};

Result reference(const uint16_t* raw, int width, int height, int mode) {
    if (!raw || width <= 0 || height <= 0 || mode == DFXISP_MODE_NORMAL)
        return {DFXISP_MODE_NORMAL, DFXISP_HYST_BELOW_EXIT, 0};
    if (mode == DFXISP_MODE_LOW_LIGHT)
        return {DFXISP_MODE_LOW_LIGHT, DFXISP_HYST_ABOVE_ENTER, 0};

    const int pixels = width * height;
    const int dark = std::count_if(raw, raw + pixels,
                                   [](uint16_t pixel) { return pixel < kThreshold; });
    const int scaled = dark * 100;
    const int selected = scaled > kVerdict * pixels ? DFXISP_MODE_LOW_LIGHT : DFXISP_MODE_NORMAL;
    const int flags = (scaled > kEnter * pixels ? DFXISP_HYST_ABOVE_ENTER : 0) |
                      (scaled < kExit * pixels ? DFXISP_HYST_BELOW_EXIT : 0);
    return {selected, flags, dark};
}

bool check(const std::string& name, const uint16_t* raw, int width, int height, int mode) {
    const auto expected = reference(raw, width, height, mode);
    Result actual{-1, -1, -1};
    checker_scan(raw, width, height, mode, kThreshold, kVerdict, kEnter, kExit,
                 &actual.mode, &actual.flags, &actual.dark);
    if (actual.mode == expected.mode && actual.flags == expected.flags && actual.dark == expected.dark)
        return true;
    std::cerr << name << " expected (mode, flags, dark)=(" << expected.mode << ", "
              << expected.flags << ", " << expected.dark << ") actual=(" << actual.mode
              << ", " << actual.flags << ", " << actual.dark << ")\n";
    return false;
}
}  // namespace

int main(int argc, char** argv) {
    const bool rtl = argc == 2 && std::string(argv[1]) == "rtl";
    std::array<uint16_t, 2048> raw{};
    int passed = 0, total = 0;
    const auto run = [&](const std::string& name, const uint16_t* pixels,
                         int width, int height, int mode) {
        ++total;
        if (check(name, pixels, width, height, mode)) ++passed;
    };
    for (int dark : {0, 590, 599, 600, 601, 610, 619, 620, 621, 630,
                     639, 640, 641, 650, 1000}) {
        raw.fill(kThreshold);
        std::fill_n(raw.begin(), dark, kThreshold - 1);
        run("dark=" + std::to_string(dark), raw.data(), kWidth, kHeight, DFXISP_MODE_AUTO);
    }
    run("forced_normal", raw.data(), kWidth, kHeight, DFXISP_MODE_NORMAL);
    raw.fill(kThreshold + 1);
    run("forced_low", raw.data(), kWidth, kHeight, DFXISP_MODE_LOW_LIGHT);
    run("zero_width", raw.data(), 0, kHeight, DFXISP_MODE_LOW_LIGHT);
    run("negative_width", raw.data(), -1, kHeight, DFXISP_MODE_AUTO);
    run("zero_height", raw.data(), kWidth, 0, DFXISP_MODE_LOW_LIGHT);
    run("negative_height", raw.data(), kWidth, -1, DFXISP_MODE_AUTO);
    // The RTL co-simulation bridge marshals an AXI data buffer from the pointer.
    if (!rtl) run("null_input", nullptr, kWidth, kHeight, DFXISP_MODE_LOW_LIGHT);

    std::cout << (passed == total ? "PASS" : "FAIL") << " cases=" << passed << "/" << total << '\n';
    return passed == total ? 0 : 1;
}
