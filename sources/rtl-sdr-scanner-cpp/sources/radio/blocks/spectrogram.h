#pragma once

#include <gnuradio/sync_block.h>
#include <radio/help_structures.h>

#include <functional>
#include <vector>

class Spectrogram : virtual public gr::sync_block {
  struct Container {
    Container(int size);

    std::vector<float> m_sum;
    int m_counter;
    std::chrono::milliseconds m_lastDataSendTime;
  };

  using SendFunction = std::function<void(const std::chrono::milliseconds&, const Frequency&, const std::vector<int8_t>&)>;

 public:
  Spectrogram(const int itemSize, const Frequency sampleRate, std::function<Frequency()> getFrequency, SendFunction send);

  int work(int noutput_items, gr_vector_const_void_star& input_items, gr_vector_void_star& output_items) override;

 private:
  void process(Container& container, const float* data);
  void send(Container& container);

  const int m_inputSize;
  const int m_outputSize;
  const int m_decimatorFactor;
  const Frequency m_sampleRate;
  const std::function<Frequency()> m_getFrequency;
  const SendFunction m_send;
  std::map<Frequency, Container> m_containers;
};