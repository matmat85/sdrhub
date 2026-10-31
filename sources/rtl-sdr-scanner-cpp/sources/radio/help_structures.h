#pragma once

#include <notification.h>
#include <utils/serializers.h>

#include <complex>
#include <map>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

using Frequency = int32_t;

struct Recording {
  std::string source;
  std::string name;
  Frequency deviceFrequency;
  Frequency recordingFrequency;
  Frequency bandwidth;
  std::string modulation;
  bool flush;

  Frequency shift() const { return recordingFrequency - deviceFrequency; }
};

using TransmissionNotification = Notification<std::vector<Recording>>;

using SimpleComplex = std::complex<int8_t>;

struct FrequencyRange {
  bool operator==(const FrequencyRange&) const = default;
  bool operator!=(const FrequencyRange&) const = default;

  Frequency center() const { return (start + stop) / 2; }
  Frequency bandwidth() const { return stop - start; }
  bool contains(const Frequency& frequency) const { return start <= frequency && frequency <= stop; }

  Frequency start;
  Frequency stop;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(FrequencyRange, start, stop)

struct Satellite {
  int id;
  std::string name;
  Frequency frequency;
  Frequency bandwidth;
  std::string modulation;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(Satellite, id, name, frequency, bandwidth, modulation)

struct Gain {
  std::string name;
  double value;
  double min;
  double max;
  double step;
  std::vector<double> options;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_WITH_DEFAULT(Gain, name, value, min, max, step, options)

struct Crontab {
  std::string name;
  std::string expression;
  std::chrono::seconds duration;
  Frequency frequency;
  Frequency bandwidth;
  std::string modulation;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(Crontab, name, expression, duration, frequency, bandwidth, modulation)

struct Device {
  bool connected = false;
  bool enabled{};
  std::vector<Gain> gains{};
  std::string serial{};
  std::string driver{};
  std::string alias{};
  std::map<std::string, std::string> device_args{};
  Frequency sample_rate{};
  std::vector<FrequencyRange> ranges{};
  float start_recording_level{};
  float stop_recording_level{};
  std::vector<Satellite> satellites{};
  std::vector<Frequency> sample_rates{};
  std::vector<Crontab> crontabs;

  std::string getName() const { return driver + "_" + serial; }
  std::string getAliasName() const { return alias.empty() ? getName() : alias; }
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_WITH_DEFAULT(
    Device, connected, enabled, gains, serial, driver, alias, device_args, sample_rate, ranges, start_recording_level, stop_recording_level, satellites, sample_rates, crontabs)
