#pragma once

#include <radio/help_structures.h>
#include <utils/serializers.h>

#include <nlohmann/json.hpp>
#include <vector>

struct IgnoredFrequency {
  Frequency frequency;
  Frequency bandwidth;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(IgnoredFrequency, frequency, bandwidth)

struct OutputConfig {
  bool color_log_enabled = true;
  std::string console_log_level = "info";
  std::string file_log_level = "debug";
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(OutputConfig, color_log_enabled, console_log_level, file_log_level)

struct PositionConfig {
  std::string latitude = "0.000000";
  std::string longitude = "0.000000";
  int altitude = 0;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(PositionConfig, latitude, longitude, altitude)

struct RecordingConfig {
  Frequency min_sample_rate = 32000;
  std::chrono::milliseconds min_time_ms = std::chrono::milliseconds(2000);
  std::chrono::milliseconds max_noise_time_ms = std::chrono::milliseconds(2000);
  Frequency step = 2500;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(RecordingConfig, min_sample_rate, min_time_ms, max_noise_time_ms, step)

struct FileConfig {
  std::vector<Device> devices;
  std::vector<IgnoredFrequency> ignored_frequencies;
  OutputConfig output;
  PositionConfig position;
  RecordingConfig recording;
  int version = 1;
  int workers = 0;

  static FileConfig fromJson(nlohmann::json json, bool enumerateRemote);
  static nlohmann::json toSave(nlohmann::json json);
  static nlohmann::json toPrint(nlohmann::json json);
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(FileConfig, devices, ignored_frequencies, output, position, recording, version, workers)
