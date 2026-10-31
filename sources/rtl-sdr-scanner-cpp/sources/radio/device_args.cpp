#include "device_args.h"

#include <stdexcept>

SoapySDR::Kwargs getDeviceArgs(const Device& device) {
  if (device.device_args.empty()) {
    return {{"driver", device.driver}, {"serial", device.serial}};
  }
  const auto& args = device.device_args;
  const auto driver = args.find("driver");
  if (driver == args.end() || driver->second.empty()) {
    throw std::runtime_error("device_args requires a non-empty driver");
  }
  if (driver->second == "rtltcp") {
    const auto endpoint = args.find("rtltcp");
    if (endpoint == args.end() || endpoint->second.empty()) {
      throw std::runtime_error("RTL-TCP device_args requires an explicit rtltcp host[:port]");
    }
  }
  return args;
}
