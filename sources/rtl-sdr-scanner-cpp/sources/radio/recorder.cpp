#include "recorder.h"

#include <config.h>
#include <gnuradio/analog/agc2_cc.h>
#include <gnuradio/blocks/complex_to_interleaved_char.h>
#include <gnuradio/blocks/file_sink.h>
#include <gnuradio/blocks/stream_to_vector.h>
#include <gnuradio/filter/fir_filter.h>
#include <gnuradio/filter/fir_filter_blk.h>
#include <gnuradio/filter/firdes.h>
#include <gnuradio/filter/freq_xlating_fir_filter.h>
#include <gnuradio/filter/pfb_arb_resampler_ccf.h>
#include <gnuradio/filter/rational_resampler.h>
#include <gnuradio/zeromq/sub_source.h>
#include <logger.h>
#include <network/query.h>

#include <limits>

constexpr auto LABEL = "recorder";

// most blocks based on
// https://github.com/gqrx-sdr/gqrx/blob/master/src/applications/gqrx/receiver.cpp

Block buildDecimator(Frequency sampleRate, Frequency shift, int decim) {
  const auto filter = gr::filter::freq_xlating_fir_filter_ccf::make(decim, {1}, 0.0, sampleRate);
  const auto outRate = sampleRate / decim;
  const auto lpf_cutoff = 120e3;
  filter->set_center_freq(shift);
  filter->set_taps(gr::filter::firdes::low_pass(1.0, sampleRate, lpf_cutoff, outRate - 2 * lpf_cutoff, gr::fft::window::WIN_BLACKMAN_HARRIS));
  return filter;
}

Block buildResampler(Frequency inputRate, Frequency outputRate) {
  const auto rate = static_cast<double>(outputRate) / inputRate;
  const auto cutoff = rate > 1.0f ? 0.4 : 0.4 * (double)rate;
  const auto trans_width = rate > 1.0f ? 0.2 : 0.2 * (double)rate;
  const auto flt_size = 32;
  const auto d_taps = gr::filter::firdes::low_pass(flt_size, flt_size, cutoff, trans_width);
  auto resampler = gr::filter::pfb_arb_resampler_ccf::make(rate, d_taps, flt_size);
  resampler->set_output_multiple(4096);
  return resampler;
}

Recorder::Recorder(const Config& config, const Device& device, const std::string& zeromq, Frequency sampleRate, const Recording& recording, std::function<void(const nlohmann::json&)> send)
    : m_config(config), m_sampleRate(sampleRate), m_recording(recording), m_send(send), m_tb(gr::make_top_block("recorder")), m_connector(m_tb) {
  Logger::info(
      LABEL,
      "start recorder, source: {}, name: {}, frequency: {}, bandwidth: {}, modulation: {}",
      colored(BLUE, "{}", m_recording.source),
      colored(BLUE, "{}", m_recording.name),
      formatFrequency(m_recording.recordingFrequency, GREEN),
      formatFrequency(m_recording.bandwidth, GREEN),
      colored(BLUE, "{}", m_recording.modulation));

  auto source = gr::zeromq::sub_source::make(sizeof(gr_complex), 1, const_cast<char*>(zeromq.c_str()));
  std::vector<Block> blocks;
  blocks.push_back(source);
  const auto decim = std::max(1, static_cast<int>(sampleRate / RECORDER_SAMPLE_RATE_DECIMATOR));
  blocks.push_back(buildDecimator(m_sampleRate, m_recording.shift(), decim));
  blocks.push_back(buildResampler(sampleRate / decim, m_recording.bandwidth));
  auto raw = blocks.back();

  const auto samplesSize = roundUp(m_recording.bandwidth * RECORDER_FLUSH_INTERVAL.count() / 1000, 4096);
  blocks.push_back(gr::analog::agc2_cc::make(2e-3, 2e-3, 0.585, 53));
  blocks.push_back(gr::blocks::complex_to_interleaved_char::make(true, 127.0));
  blocks.push_back(gr::blocks::stream_to_vector::make(sizeof(SimpleComplex), samplesSize));
  m_buffer = std::make_shared<Buffer<SimpleComplex>>("RecorderBuffer", samplesSize);
  blocks.push_back(m_buffer);
  m_connector.connect(blocks);

  if (config.dumpRecording()) {
    const auto fileName = getRawFileName(config.workDir(), device, "recording", "fc", m_recording.recordingFrequency, m_recording.bandwidth);
    m_connector.connect<Block>(raw, gr::blocks::file_sink::make(sizeof(gr_complex), fileName.c_str()));
  }

  m_firstDataTime = getTime();
  m_lastDataTime = m_firstDataTime;
  m_tb->start();
}

Recorder::~Recorder() {
  Logger::info(LABEL, "stop recorder, frequency: {}, time: {} ms", formatFrequency(m_recording.recordingFrequency, RED), getDuration().count());
  m_tb->stop();
  m_tb->wait();
}

Recording Recorder::getRecording() const { return m_recording; }

void Recorder::flush() {
  m_lastDataTime = getTime();
  m_buffer->popSingleSample([this](const SimpleComplex* data, const int size, const std::chrono::milliseconds& time) {
    TransmissionQuery transmission(m_recording.source, m_recording.name, time, m_recording.recordingFrequency, m_recording.bandwidth, m_recording.modulation, encode_base64(data, size));
    m_send(transmission);
  });
}

std::chrono::milliseconds Recorder::getDuration() const { return m_lastDataTime - m_firstDataTime; }
