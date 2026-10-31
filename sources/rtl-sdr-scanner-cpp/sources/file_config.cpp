#include "file_config.h"

#include <config_migrator.h>
#include <logger.h>
#include <radio/sdr_device_reader.h>
#include <radio/device_args.h>

#include <regex>

constexpr auto LABEL = "file_config";

FileConfig FileConfig::fromJson(nlohmann::json json, bool enumerateRemote) {
  ConfigMigrator::update(json);
  FileConfig fileConfig(json);
  SdrDeviceReader::updateDevices(fileConfig.devices, enumerateRemote);
  return fileConfig;
}

nlohmann::json FileConfig::toSave(nlohmann::json json) {
  for (const auto& item : json.at("devices")) {
    const Device device = item.get<Device>();
    if (!device.device_args.empty()) {
      getDeviceArgs(device);
      if (device.serial.empty()) {
        throw std::runtime_error("explicit devices require a non-empty display serial");
      }
    }
  }
  SdrDeviceReader::clearDevices(json);
  ConfigMigrator::sort(json);
  return json;
}

nlohmann::json FileConfig::toPrint(nlohmann::json json) {
  try {
    std::regex regex(R"(^(\d+)\.\d+)");
    json["position"]["latitude"] = std::regex_replace(json["position"]["latitude"].get<std::string>(), regex, "$1.********");
    json["position"]["longitude"] = std::regex_replace(json["position"]["longitude"].get<std::string>(), regex, "$1.********");
  } catch (const std::exception& exception) {
    Logger::exception(LABEL, exception, SPDLOG_LOC, "hide sensitive data failed");
  }
  return json;
}