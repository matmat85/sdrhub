#include "utils.h"

#include <config.h>
#include <logger.h>
#include <math.h>
#include <spdlog/spdlog.h>
#include <time.h>

#include <algorithm>
#include <numeric>
#include <random>

std::chrono::milliseconds getTime() { return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()); }

std::string randomHex(std::size_t hex_count) {
  std::random_device rd;
  std::uniform_int_distribution<int> dist(0, 15);
  std::ostringstream oss;
  oss << std::hex << std::nouppercase;
  for (std::size_t i = 0; i < hex_count; ++i) oss << dist(rd);
  return oss.str();
}

void average(const float* input, float* output, int size, int groupSize) {
  const auto a = groupSize / 2;
  float sum = 0.0;
  int count = 0;

  auto isIndexValid = [size](int i) { return 0 <= i && i < size; };

  for (int i = -a; i < size + a - 1; ++i) {
    const auto first = i - a - 1;
    const auto last = i + a;
    if (isIndexValid(first)) {
      sum -= input[first];
      count--;
    }
    if (isIndexValid(last)) {
      sum += input[last];
      count++;
    }
    if (isIndexValid(i)) {
      output[i] = sum / count;
    }
  }
}

int roundUp(const int value, const int factor) {
  if (value % factor == 0) {
    return value;
  } else {
    return (value / factor + 1) * factor;
  }
}

int roundDown(const int value, const int factor) { return value / factor * factor; }