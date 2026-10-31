#include "sdr_device.h"

#include <config.h>
#include <gnuradio/block_detail.h>
#include <gnuradio/blocks/copy.h>
#include <gnuradio/blocks/file_sink.h>
#include <gnuradio/blocks/null_sink.h>
#include <gnuradio/soapy/source.h>
#include <gnuradio/zeromq/pub_sink.h>
#include <logger.h>
#include <network/remote_controller.h>
#include <notification.h>
#include <radio/blocks/sdr_source.h>
#include <radio/help_structures.h>
#include <radio/recorder.h>
#include <radio/sdr_processor.h>

#include <filesystem>

constexpr auto LABEL = "sdr";

SdrDevice::SdrDevice(const Config& config, const Device& device, RemoteController& remoteController, TransmissionNotification& notification, const std::vector<FrequencyRange>& ranges)
    : m_config(config),
      m_device(device),
      m_zeromq(fmt::format("ipc://{}/{}_{}_zeromq_stream.sock", std::filesystem::canonical(m_config.workDir()).string(), device.driver, device.serial)),
      m_remoteController(remoteController),
      m_notification(notification),
      m_isInitialized(false),
      m_tb(gr::make_top_block("device")),
      m_source(std::make_shared<SdrSource>(device)),
      m_selector(gr::blocks::selector::make(sizeof(gr_complex), 0, 0)),
      m_connector(m_tb) {
  Logger::info(LABEL, "starting");
  Logger::info(LABEL, "driver: {}, serial: {}, sample rate: {}", colored(GREEN, "{}", device.driver), colored(GREEN, "{}", device.serial), formatFrequency(device.sample_rate));
  Logger::info(LABEL, "zeromq: {}", colored(GREEN, "{}", m_zeromq));

  m_connector.connect<Block>(m_source, gr::zeromq::pub_sink::make(sizeof(gr_complex), 1, const_cast<char*>(m_zeromq.c_str())));
  m_connector.connect<Block>(m_source, m_selector, gr::blocks::null_sink::make(sizeof(gr_complex)));

  int index = 1;
  for (const auto& range : ranges) {
    Logger::info(LABEL, "creating processor, index: {}, range: {}", index, formatFrequencyRange(range, GREEN));
    auto forward = gr::blocks::copy::make(sizeof(gr_complex));
    auto processor = std::make_unique<SdrProcessor>(m_config, m_device, m_remoteController, m_notification, forward, m_connector, range);
    m_connector.connect(m_selector, forward, index, 0);
    m_processors.push_back(std::move(processor));
    m_processorIndex[range.center()] = index++;
  }

  if (config.dumpSource()) {
    const auto fileName = getRawFileName(config.workDir(), device, "source-all", "fc", ranges.front().center(), device.sample_rate);
    m_connector.connect<Block>(m_source, gr::blocks::file_sink::make(sizeof(gr_complex), fileName.c_str()));
  }

  m_tb->start();
  Logger::info(LABEL, "started");
}

SdrDevice::~SdrDevice() {
  m_tb->stop();
  m_tb->wait();
  std::remove(m_zeromq.c_str());
  Logger::info(LABEL, "stopped");
}

void SdrDevice::setFrequencyRange(FrequencyRange frequencyRange) {
  if (!m_isInitialized) {
    Logger::info(LABEL, "waiting, initial sleep: {}", colored(GREEN, "{} ms", INITIAL_DELAY.count()));
    std::this_thread::sleep_for(INITIAL_DELAY);
    Logger::info(LABEL, "finished, initial sleep");
    m_isInitialized = true;
  }

  m_selector->set_output_index(0);
  const auto frequency = frequencyRange.center();
  if (m_source->setCenterFrequency(frequency)) {
    Logger::debug(LABEL, "set frequency range: {}, center frequency: {}", formatFrequencyRange(frequencyRange), formatFrequency(frequency));
  } else {
    Logger::warn(LABEL, "set frequency range failed: {}, center frequency: {}", formatFrequencyRange(frequencyRange), formatFrequency(frequency));
  }
  std::this_thread::sleep_for(std::chrono::milliseconds(1));
  auto it = m_processorIndex.find(frequencyRange.center());
  if (it != m_processorIndex.end()) {
    m_selector->set_output_index(it->second);
  }
}

void SdrDevice::updateRecordings(const std::vector<Recording> recordings) {
  const auto findRecorder = [this](const Recording& recording) {
    return std::find_if(m_recorders.begin(), m_recorders.end(), [recording](const std::unique_ptr<Recorder>& recorder) {
      // improve auto formatter
      return recording.recordingFrequency == recorder->getRecording().recordingFrequency;
    });
  };

  const auto isRecordingActive = [recordings](const Recording& recording1) {
    return std::find_if(recordings.begin(), recordings.end(), [recording1](const Recording& recording2) {
             // improve auto formatter
             return recording1.recordingFrequency == recording2.recordingFrequency;
           }) != recordings.end();
  };

  std::erase_if(m_recorders, [isRecordingActive](const std::unique_ptr<Recorder>& recorder) { return !isRecordingActive(recorder->getRecording()); });

  if (m_recorders.size() < static_cast<size_t>(m_config.recordersCount())) {
    ignoredTransmissions.clear();
  }

  for (const auto& recording : recordings) {
    const auto it = findRecorder(recording);
    if (it != m_recorders.end()) {
      if (recording.flush) {
        (*it)->flush();
      }
    } else {
      if (m_recorders.size() < static_cast<size_t>(m_config.recordersCount())) {
        const auto sampleRate = m_device.sample_rate;
        m_recorders.push_back(
            std::make_unique<Recorder>(m_config, m_device, m_zeromq, sampleRate, recording, std::bind(&RemoteController::sendTransmission, m_remoteController, m_device, std::placeholders::_1)));
      } else {
        if (!ignoredTransmissions.count(recording.recordingFrequency)) {
          Logger::info(LABEL, "maximum recorders limit reached, frequency: {}", formatFrequency(recording.recordingFrequency, RED));
          ignoredTransmissions.insert(recording.recordingFrequency);
        }
      }
    }
  }
}
