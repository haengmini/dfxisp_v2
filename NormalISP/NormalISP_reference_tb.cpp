#include "NormalISP.hpp"
#include "../hls/reference_csv.hpp"

namespace {
constexpr std::size_t kCaseCount = 10;
// C/RTL co-simulation transfers the full depth declared on each m_axi port.
constexpr std::size_t kAxiDepth = 2048;

bool check_value(const ReferenceCase& test, const char* function, const std::string& index,
                 uint32_t expected, uint32_t actual) {
    if (expected == actual) return true;
    std::cerr << test.name << " " << function << " index=" << index
              << " expected=" << expected << " actual=" << actual << '\n';
    return false;
}

bool check_output(const ReferenceCase& test, const char* function,
                  int expected_width, int expected_height, int width, int height,
                  const std::vector<uint32_t>& expected, const std::vector<uint32_t>& actual) {
    bool ok = check_value(test, function, "out_w", expected_width, width);
    ok &= check_value(test, function, "out_h", expected_height, height);
    for (std::size_t i = 0; i < test.expected.size(); ++i) {
        if (expected[i] != actual[i]) {
            ok &= check_value(test, function, std::to_string(i), expected[i], actual[i]);
        }
    }
    return ok;
}
}  // namespace

int main() {
    const char* csv = "NormalISP_vectors.csv";
    const auto cases = load_reference_csv(csv);
    if (cases.size() != kCaseCount) {
        std::cerr << "FAIL " << csv << " cases=" << cases.size() << "/" << kCaseCount << '\n';
        return 1;
    }

    std::size_t passed = 0;
    for (const auto& test : cases) {
        const int in_w = test.param("in_w");
        const int in_h = test.param("in_h");
        const int awb_mode = test.param("awb_mode");
        auto raw = test.raw;
        raw.resize(kAxiDepth);
        std::vector<uint32_t> rgb(kAxiDepth, UINT32_MAX);
        int out_w = 0, out_h = 0;
        NormalISP_dev(raw.data(), rgb.data(), in_w, in_h, awb_mode, &out_w, &out_h);
        bool ok = check_output(test, "NormalISP_dev", test.param("out_w"), test.param("out_h"),
                               out_w, out_h, test.expected, rgb);

        if (awb_mode == NORMAL_ISP_AWB_ON) {
            std::vector<uint32_t> top_rgb(kAxiDepth, UINT32_MAX);
            int top_w = 0, top_h = 0;
            NormalISP(raw.data(), top_rgb.data(), in_w, in_h, &top_w, &top_h);
            ok &= check_output(test, "NormalISP", out_w, out_h, top_w, top_h, rgb, top_rgb);
        }
        if (ok) ++passed;
    }

    const bool ok = passed == kCaseCount;
    std::cout << (ok ? "PASS" : "FAIL") << " cases=" << passed << "/" << kCaseCount << '\n';
    return ok ? 0 : 1;
}
