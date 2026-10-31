#pragma once

#include <config.h>
#include <network/mqtt.h>
#include <network/remote_controller.h>
#include <notification.h>
#include <radio/scheduler.h>
#include <radio/sdr_device.h>

#include <atomic>
#include <memory>
#include <thread>

class Scanner {
 public:
  Scanner(const Config& config, const Device& device, RemoteController& remoteController);
  ~Scanner();

 private:
  void runScheduler(const std::optional<FrequencyRange>& activeRange);
  void worker();

  const std::vector<FrequencyRange> m_ranges;
  SdrDevice m_device;
  Scheduler m_scheduler;

  std::atomic<bool> m_isRunning;
  std::thread m_thread;
  TransmissionNotification m_notification;
};