#pragma once

#include <chrono>
#include <nlohmann/json.hpp>

namespace nlohmann {
template <>
struct adl_serializer<std::chrono::seconds> {
  static inline void to_json(nlohmann::json& json, const std::chrono::seconds& seconds) { json = seconds.count(); }
  static inline void from_json(const nlohmann::json& json, std::chrono::seconds& seconds) { seconds = std::chrono::seconds(json.get<int64_t>()); }
};

template <>
struct adl_serializer<std::chrono::milliseconds> {
  static inline void to_json(nlohmann::json& json, const std::chrono::milliseconds& milliseconds) { json = milliseconds.count(); }
  static inline void from_json(const nlohmann::json& json, std::chrono::milliseconds& milliseconds) { milliseconds = std::chrono::milliseconds(json.get<int64_t>()); }
};
}  // namespace nlohmann
