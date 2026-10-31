#include "sdr_device_reader.h"

#include <config.h>
#include <logger.h>
#include <radio/device_args.h>
#include <utils/utils.h>

#include <memory>

constexpr auto LABEL = "sdr_reader";

std::vector<Frequency> getSampleRates(SoapySDR::Device* sdr) {
  std::vector<Frequency> sampleRates;
  for (const auto value : sdr->listSampleRates(SOAPY_SDR_RX, 0)) {
    const auto sampleRate = static_cast<Frequency>(value);
    Logger::info(LABEL, "  supported sample rate: {}", formatFrequency(sampleRate));
    sampleRates.emplace_back(sampleRate);
  }
  std::sort(sampleRates.begin(), sampleRates.end());
  if (sampleRates.empty()) {
    throw std::runtime_error("SDR driver reported no supported sample rates");
  }
  return sampleRates;
}

std::vector<Gain> getGains(SoapySDR::Device* sdr) {
  std::vector<Gain> gains;
  for (const auto& gain : sdr->listGains(SOAPY_SDR_RX, 0)) {
    const auto gainRange = sdr->getGainRange(SOAPY_SDR_RX, 0, gain);
    Logger::info(
        LABEL,
        "  supported gain: {}, min: {}, max: {}, step: {}",
        colored(GREEN, "{}", gain),
        colored(GREEN, "{}", gainRange.minimum()),
        colored(GREEN, "{}", gainRange.maximum()),
        colored(GREEN, "{}", gainRange.step()));
    std::vector<double> options;
    const auto optionsCount = (gainRange.maximum() - gainRange.minimum()) / gainRange.step();
    if (!std::isnan(optionsCount) && optionsCount < 1000) {
      for (double value = gainRange.minimum(); value <= gainRange.maximum(); value += gainRange.step()) {
        options.push_back(value);
      }
    } else if (sdr->getDriverKey() == "RTLSDR" && gain == "TUNER") {
      options = {0.0, 0.9, 1.4, 2.7, 3.7, 7.7, 8.7, 12.5, 14.4, 15.7, 16.6, 19.7, 20.7, 22.9, 25.4, 28.0, 29.7, 32.8, 33.8, 36.4, 37.2, 38.6, 40.2, 42.1, 43.4, 43.9, 44.5, 48.0, 49.6};
    } else {
      options.push_back(gainRange.minimum());
      options.push_back(gainRange.maximum());
    }
    gains.emplace_back(gain, gainRange.maximum(), gainRange.minimum(), gainRange.maximum(), gainRange.step(), options);
  }
  std::sort(gains.begin(), gains.end(), [](const Gain& g1, Gain& g2) { return g1.name < g2.name; });
  return gains;
}

void SdrDeviceReader::updateDevice(Device& device, const SoapySDR::Kwargs args) {
  const auto serial = device.serial;
  const auto driver = args.at("driver");
  Logger::info(LABEL, "update device, driver: {}, serial: {}", colored(GREEN, "{}", driver), colored(GREEN, "{}", serial));

  std::unique_ptr<SoapySDR::Device, void (*)(SoapySDR::Device*)> sdr(SoapySDR::Device::make(args), &SoapySDR::Device::unmake);
  if (sdr == nullptr) {
    throw std::runtime_error("open device failed");
  }

  device.driver = driver;
  device.sample_rates = getSampleRates(sdr.get());
  const auto backupGains = device.gains;
  device.gains = getGains(sdr.get());
  for (auto& gain : device.gains) {
    for (auto& backupGain : backupGains) {
      if (gain.name == backupGain.name) {
        gain.value = backupGain.value;
      }
    }
  }

  device.connected = true;
}

Device SdrDeviceReader::createDevice(const SoapySDR::Kwargs args) {
  const auto serial = args.at("serial");
  const auto driver = args.at("driver");
  Logger::info(LABEL, "creating device, driver: {}, serial: {}", colored(GREEN, "{}", driver), colored(GREEN, "{}", serial));

  std::unique_ptr<SoapySDR::Device, void (*)(SoapySDR::Device*)> sdr(SoapySDR::Device::make(args), &SoapySDR::Device::unmake);
  if (sdr == nullptr) {
    throw std::runtime_error("open device failed");
  }

  Device device;
  device.connected = true;
  device.driver = driver;
  device.serial = serial;
  device.enabled = true;
  device.start_recording_level = DEFAULT_RECORDING_START_LEVEL;
  device.stop_recording_level = DEFAULT_RECORDING_STOP_LEVEL;
  device.sample_rates = getSampleRates(sdr.get());
  device.gains = getGains(sdr.get());

  auto addSampleRate = [&device](Frequency start, Frequency stop, Frequency sampleRate) {
    const auto contains = std::find(device.sample_rates.begin(), device.sample_rates.end(), sampleRate) != device.sample_rates.end();
    if (device.ranges.empty() && contains) {
      device.ranges.emplace_back(start, stop);
      device.sample_rate = sampleRate;
    }
  };

  addSampleRate(140000000, 160000000, 20480000);
  addSampleRate(140000000, 160000000, 20000000);
  addSampleRate(144000000, 146000000, 2048000);
  addSampleRate(144000000, 146000000, 2000000);
  addSampleRate(144000000, 146000000, 1024000);
  addSampleRate(144000000, 146000000, 1000000);
  addSampleRate(144000000, 146000000, *device.sample_rates.rbegin());

  return device;
}

SoapySDR::KwargsList SdrDeviceReader::enumerateDevices(bool enumerateRemote) {
  SoapySDR::KwargsList results = SoapySDR::Device::enumerate(enumerateRemote ? "" : "remote=");
  Logger::info(LABEL, "total devices: {}", colored(GREEN, "{}", results.size()));
  try {
    std::map<std::string, int> serialCount;
    for (const auto& result : results) {
      serialCount[result.at("serial")]++;
    }
    const auto it = std::remove_if(results.begin(), results.end(), [&serialCount](const auto& result) {
      auto serial = result.at("serial");
      auto driver = result.at("driver");
      return 1 < serialCount[serial] && driver == "remote";
    });
    results.erase(it, results.end());
  } catch (const std::exception& exception) {
    Logger::exception(LABEL, exception, SPDLOG_LOC, "enumerate devices failed");
  }
  Logger::info(LABEL, "devices after filtering: {}", colored(GREEN, "{}", results.size()));
  return results;
}

void SdrDeviceReader::updateDevices(std::vector<Device>& devices, bool enumerateRemote) {
  Logger::info(LABEL, "scanning connected devices");
  for (auto& device : devices) {
    if (device.device_args.empty()) {
      continue;
    }
    device.connected = false;
    try {
      const auto args = getDeviceArgs(device);
      device.driver = args.at("driver");
      if (device.enabled) {
        updateDevice(device, args);
      }
    } catch (const std::exception& exception) {
      Logger::exception(LABEL, exception, SPDLOG_LOC, "update explicit device failed: {}", device.serial);
    }
  }
  const SoapySDR::KwargsList results = enumerateDevices(enumerateRemote);

  for (const auto& args : results) {
    try {
      const auto serial = args.at("serial");
      const auto f = [serial](const Device& device) { return device.device_args.empty() && device.serial == serial; };
      const auto it = std::find_if(devices.begin(), devices.end(), f);
      if (it != devices.end()) {
        updateDevice(*it, args);
      } else {
        devices.push_back(createDevice(args));
      }
    } catch (const std::exception& exception) {
      Logger::exception(LABEL, exception, SPDLOG_LOC, "update device failed");
    }
  }
}

void SdrDeviceReader::clearDevices(nlohmann::json& json) {
  for (auto& device : json.at("devices")) {
    device.erase("connected");
    if (!device.contains("device_args") || device.at("device_args").empty()) {
      device.erase("driver");
    }
    device.erase("sample_rates");

    for (auto& gain : device.at("gains")) {
      gain.erase("min");
      gain.erase("max");
      gain.erase("step");
      gain.erase("options");
    }
  }
}
