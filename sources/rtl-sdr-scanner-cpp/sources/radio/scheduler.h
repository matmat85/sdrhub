#pragma once

#include <config.h>
#include <network/query.h>
#include <network/remote_controller.h>
#include <radio/sdr_device.h>

#include <list>
#include <mutex>
#include <optional>

class Scheduler {
 public:
  Scheduler(const Config& config, const Device& device, RemoteController& remoteController);
  ~Scheduler();

  static std::vector<ScheduledTransmission> getTransmissions(const std::chrono::milliseconds& now, std::list<ScheduledTransmission>& scheduledTransmissions);
  static std::optional<std::pair<FrequencyRange, std::vector<Recording>>> getRecordings(
      const std::chrono::milliseconds& now, std::list<ScheduledTransmission>& scheduledTransmissions, Frequency sampleRate, Frequency shift);
  std::optional<std::pair<FrequencyRange, std::vector<Recording>>> getRecordings(const std::chrono::milliseconds& now);

  void setRefreshEnabled(const bool& enabled);

 private:
  void worker();
  void mergeScheduledTransmissions();

  void query();
  void callback(const nlohmann::json& json);

  const Config& m_config;
  const Device m_device;
  RemoteController& m_remoteController;
  std::list<ScheduledTransmission> m_scheduledTransmissions;
  std::chrono::milliseconds m_lastUpdateTime;
  std::atomic<bool> m_isRefreshEnabled;
  std::atomic<bool> m_isRunning;
  std::thread m_thread;
  std::mutex m_mutex;
};
