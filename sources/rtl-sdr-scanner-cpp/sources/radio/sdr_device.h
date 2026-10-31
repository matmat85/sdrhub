#pragma once

#include <gnuradio/blocks/selector.h>
#include <gnuradio/top_block.h>
#include <network/remote_controller.h>
#include <notification.h>
#include <radio/blocks/sdr_source.h>
#include <radio/help_structures.h>
#include <radio/recorder.h>
#include <radio/sdr_processor.h>

#include <memory>
#include <set>
#include <string>

class SdrDevice {
 public:
  SdrDevice(const Config& config, const Device& device, RemoteController& remoteController, TransmissionNotification& notification, const std::vector<FrequencyRange>& ranges);
  ~SdrDevice();

  void setFrequencyRange(FrequencyRange frequencyRange);
  void updateRecordings(const std::vector<Recording> recordings);

 private:
  const Config& m_config;
  const Device m_device;
  const std::string m_zeromq;
  RemoteController& m_remoteController;
  TransmissionNotification& m_notification;
  bool m_isInitialized;

  std::shared_ptr<gr::top_block> m_tb;
  std::shared_ptr<SdrSource> m_source;
  std::shared_ptr<gr::blocks::selector> m_selector;
  Connector m_connector;
  std::vector<std::unique_ptr<SdrProcessor>> m_processors;
  std::map<Frequency, int> m_processorIndex;
  std::vector<std::unique_ptr<Recorder>> m_recorders;
  std::set<Frequency> ignoredTransmissions;
};
