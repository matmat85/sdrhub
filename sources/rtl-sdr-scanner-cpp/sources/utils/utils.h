#pragma once

#include <radio/help_structures.h>
#include <utils/collection_utils.h>
#include <utils/radio_utils.h>

#include <boost/beast/core/detail/base64.hpp>
#include <chrono>
#include <string>

std::chrono::milliseconds getTime();

std::string randomHex(std::size_t hex_count);

void average(const float* input, float* output, int size, int groupSize);

int roundUp(const int value, const int factor);

int roundDown(const int value, const int factor);

template <typename T>
std::string encode_base64(const T* data, std::size_t size) {
  const auto bytes = sizeof(T) * size;
  std::string out;
  out.resize(boost::beast::detail::base64::encoded_size(bytes));
  std::size_t written = boost::beast::detail::base64::encode(out.data(), data, bytes);
  out.resize(written);
  return out;
}