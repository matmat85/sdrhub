#pragma once

#include <config.h>
#include <gnuradio/blocks/rotator_cc.h>
#include <gnuradio/top_block.h>
#include <radio/blocks/buffer.h>
#include <radio/connector.h>
#include <radio/help_structures.h>
#include <utils/utils.h>

#include <atomic>
#include <memory>
#include <vector>

class Recorder {
 public:
  Recorder() = delete;
  Recorder(const Recorder&) = delete;
  Recorder& operator=(const Recorder&) = delete;

  Recorder(const Config& config, const Device& device, const std::string& zeromq, Frequency sampleRate, const Recording& recording, std::function<void(const nlohmann::json&)> send);
  ~Recorder();

  Recording getRecording() const;
  void flush();
  std::chrono::milliseconds getDuration() const;

 private:
  const Config& m_config;
  const Frequency m_sampleRate;
  const Recording m_recording;
  const std::function<void(const nlohmann::json&)> m_send;

  std::shared_ptr<gr::top_block> m_tb;
  std::shared_ptr<Buffer<SimpleComplex>> m_buffer;
  Connector m_connector;
  std::chrono::milliseconds m_firstDataTime;
  std::chrono::milliseconds m_lastDataTime;
};
