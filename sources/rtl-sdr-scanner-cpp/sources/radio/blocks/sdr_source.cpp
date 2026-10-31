#include "sdr_source.h"

#include <SoapySDR/Formats.h>
#include <logger.h>
#include <radio/device_args.h>
#include <utils/utils.h>

#include <SoapySDR/Errors.hpp>
#include <memory>

constexpr auto LABEL = "source";

SdrSource::SdrSource(const Device& device)
    : gr::sync_block("SdrSource", gr::io_signature::make(0, 0, 0), gr::io_signature::make(1, 1, sizeof(gr_complex))), m_configDevice(device), m_device(nullptr), m_stream(nullptr) {
  std::unique_ptr<SoapySDR::Device, void (*)(SoapySDR::Device*)> sdr(SoapySDR::Device::make(getDeviceArgs(device)), &SoapySDR::Device::unmake);
  if (sdr == nullptr) {
    throw std::runtime_error("open device failed: " + device.getName());
  }
  sdr->setGainMode(SOAPY_SDR_RX, 0, false);
  for (const auto& gain : device.gains) {
    Logger::info(LABEL, "set gain, name: {}, value: {}", colored(GREEN, "{}", gain.name), colored(GREEN, "{}", gain.value));
    sdr->setGain(SOAPY_SDR_RX, 0, gain.name.c_str(), gain.value);
  }
  Logger::info(LABEL, "sample rate: {}", formatFrequency(device.sample_rate));
  sdr->setSampleRate(SOAPY_SDR_RX, 0, device.sample_rate);
  m_device = sdr.release();
}

SdrSource::~SdrSource() {
  stop();
  SoapySDR::Device::unmake(m_device);
}

int SdrSource::work(int noutput_items, gr_vector_const_void_star&, gr_vector_void_star& output_items) {
  int flags = 0;
  long long int time_ns = 0;
  const long timeout_us = 500000;  // 0.5 sec

  std::lock_guard<std::mutex> lock(m_mutex);
  const auto result = m_device->readStream(m_stream, output_items.data(), noutput_items, flags, time_ns, timeout_us);
  if (0 <= result) {
    return result;
  } else {
    Logger::error(LABEL, "soapy error: {}", SoapySDR::errToStr(result));
    exit(1);
    return 0;
  }
}

int SdrSource::general_work(int noutput_items, gr_vector_int&, gr_vector_const_void_star& input_items, gr_vector_void_star& output_items) {
  consume_each(noutput_items);
  return work(noutput_items, input_items, output_items);
}

bool SdrSource::start() {
  std::lock_guard<std::mutex> lock(m_mutex);
  m_stream = m_device->setupStream(SOAPY_SDR_RX, SOAPY_SDR_CF32);
  set_max_noutput_items(std::max(static_cast<size_t>(1024), m_device->getStreamMTU(m_stream)));
  m_device->activateStream(m_stream);
  return true;
}

bool SdrSource::stop() {
  std::lock_guard<std::mutex> lock(m_mutex);
  if (m_stream) {
    m_device->deactivateStream(m_stream);
    m_device->closeStream(m_stream);
    m_stream = nullptr;
  }
  return true;
}

bool SdrSource::setCenterFrequency(Frequency frequency) {
  std::lock_guard<std::mutex> lock(m_mutex);
  for (int i = 0; i < 10; ++i) {
    try {
      m_device->setFrequency(SOAPY_SDR_RX, 0, frequency);
      return true;
    } catch (const std::exception&) {
    }
  }
  return false;
}