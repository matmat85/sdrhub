#include "scheduler.h"

#include <radio/help_structures.h>

#include <chrono>
#include <functional>

constexpr auto LABEL = "scheduler";
constexpr auto LOOP_TIMEOUT = std::chrono::milliseconds(100);
constexpr auto UPDATE_INITIAL_DELAY = std::chrono::seconds(10);
constexpr auto UPDATE_INTERVAL = std::chrono::minutes(60);
constexpr auto SHIFT_FREQUENCY = Frequency(100000);

using namespace std::placeholders;

Scheduler::Scheduler(const Config& config, const Device& device, RemoteController& remoteController)
    : m_config(config),
      m_device(device),
      m_remoteController(remoteController),
      m_lastUpdateTime(getTime() - UPDATE_INTERVAL + UPDATE_INITIAL_DELAY),
      m_isRefreshEnabled(true),
      m_isRunning(true),
      m_thread([this]() { worker(); }) {}

Scheduler::~Scheduler() {
  m_isRunning = false;
  m_thread.join();
}

std::vector<ScheduledTransmission> Scheduler::getTransmissions(const std::chrono::milliseconds& now, std::list<ScheduledTransmission>& scheduledTransmissions) {
  while (!scheduledTransmissions.empty() && scheduledTransmissions.front().end < now) {
    scheduledTransmissions.pop_front();
  }
  std::vector<ScheduledTransmission> transmissions;
  for (auto it = scheduledTransmissions.begin(); it != scheduledTransmissions.end() && it->begin <= now; ++it) {
    transmissions.push_back(*it);
  }
  return transmissions;
}

std::optional<std::pair<FrequencyRange, std::vector<Recording>>> Scheduler::getRecordings(
    const std::chrono::milliseconds& now, std::list<ScheduledTransmission>& scheduledTransmissions, Frequency sampleRate, Frequency shift) {
  const auto transmissions = getTransmissions(now, scheduledTransmissions);
  if (transmissions.empty()) {
    return std::nullopt;
  }
  const auto center = transmissions.front().frequency + shift;
  const auto left = center - sampleRate / 2;
  const auto right = center + sampleRate / 2;
  const FrequencyRange range(left, right);
  std::vector<Recording> recordings;
  for (const auto& transmission : transmissions) {
    const auto transmissionLeft = transmission.frequency - transmission.bandwidth / 2;
    const auto transmissionRight = transmission.frequency + transmission.bandwidth / 2;
    if (left <= transmissionLeft && transmissionRight <= right) {
      recordings.emplace_back(transmission.source, transmission.name, center, transmission.frequency, transmission.bandwidth, transmission.modulation, true);
    }
  }
  return std::pair<FrequencyRange, std::vector<Recording>>(range, recordings);
}

std::optional<std::pair<FrequencyRange, std::vector<Recording>>> Scheduler::getRecordings(const std::chrono::milliseconds& now) {
  std::unique_lock lock(m_mutex);
  return Scheduler::getRecordings(now, m_scheduledTransmissions, m_device.sample_rate, SHIFT_FREQUENCY);
}

void Scheduler::worker() {
  m_remoteController.schedulerCallback(m_device, std::bind(&Scheduler::callback, this, _1));
  while (m_isRunning) {
    const auto now = getTime();
    if (m_isRefreshEnabled && m_lastUpdateTime + UPDATE_INTERVAL <= now) {
      query();
      m_lastUpdateTime = now;
    }
    std::this_thread::sleep_for(LOOP_TIMEOUT);
  }
}

void Scheduler::query() {
  Logger::info(LABEL, "send query");
  const SchedulerQuery query(m_config.latitude(), m_config.longitude(), m_config.altitude(), m_device.satellites, m_device.crontabs);
  m_remoteController.schedulerQuery(m_device, static_cast<nlohmann::json>(query).dump());
}

void Scheduler::callback(const nlohmann::json& json) {
  Logger::info(LABEL, "received response, size: {}", colored(GREEN, "{}", json.size()));
  std::unique_lock lock(m_mutex);
  m_scheduledTransmissions = json;
}

void Scheduler::setRefreshEnabled(const bool& enabled) { m_isRefreshEnabled = enabled; }
