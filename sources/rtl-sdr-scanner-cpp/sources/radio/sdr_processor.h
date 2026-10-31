#pragma once

#include <config.h>
#include <gnuradio/top_block.h>
#include <network/remote_controller.h>
#include <radio/connector.h>
#include <radio/help_structures.h>

#include <memory>

class SdrProcessor {
 public:
  SdrProcessor(
      const Config& config,
      const Device& device,
      RemoteController& remoteController,
      TransmissionNotification& notification,
      std::shared_ptr<gr::block> source,
      Connector& connector,
      const FrequencyRange& frequencyRange);
  ~SdrProcessor();

 private:
  Connector& m_connector;
};