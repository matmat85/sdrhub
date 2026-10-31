#pragma once

#include <radio/help_structures.h>
#include <utils/serializers.h>

struct SchedulerQuery {
  std::string latitude;
  std::string longitude;
  int altitude;
  std::vector<Satellite> satellites;
  std::vector<Crontab> crontabs;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(SchedulerQuery, latitude, longitude, altitude, satellites, crontabs)

struct ScheduledTransmission {
  std::string source;
  std::string name;
  std::chrono::seconds begin;
  std::chrono::seconds end;
  Frequency frequency;
  Frequency bandwidth;
  std::string modulation;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(ScheduledTransmission, source, name, begin, end, frequency, bandwidth, modulation)

struct SpectrogramQuery {
  std::string source;
  std::chrono::milliseconds time;
  Frequency frequency;
  Frequency sample_rate;
  std::string data;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_ONLY_SERIALIZE(SpectrogramQuery, source, time, frequency, sample_rate, data)

struct TransmissionQuery {
  std::string source;
  std::string name;
  std::chrono::milliseconds time;
  Frequency frequency;
  Frequency bandwidth;
  std::string modulation;
  std::string data;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_ONLY_SERIALIZE(TransmissionQuery, source, name, time, frequency, bandwidth, modulation, data)
