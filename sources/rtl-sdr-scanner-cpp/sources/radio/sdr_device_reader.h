#pragma once

#include <radio/help_structures.h>

#include <SoapySDR/Device.hpp>
#include <nlohmann/json.hpp>
#include <vector>

class SdrDeviceReader {
 private:
  static void updateDevice(Device& device, const SoapySDR::Kwargs args);
  static Device createDevice(const SoapySDR::Kwargs args);
  static SoapySDR::KwargsList enumerateDevices(bool enumerateRemote);

 public:
  static void updateDevices(std::vector<Device>& devices, bool enumerateRemote);
  static void clearDevices(nlohmann::json& json);
};
