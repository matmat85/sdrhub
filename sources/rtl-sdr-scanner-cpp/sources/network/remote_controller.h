#pragma once

#include <config.h>
#include <network/mqtt.h>
#include <radio/help_structures.h>

#include <functional>
#include <nlohmann/json.hpp>

class RemoteController {
 public:
  RemoteController(const Config& config, Mqtt& mqtt);

  void getConfigQuery(const Mqtt::RawCallback& callback);
  void getConfigResponse(const std::string& data);

  void setConfigQuery(const Mqtt::JsonCallback& callback);
  void setConfigResponse(const bool& success);

  void resetTmpConfigQuery(const Mqtt::RawCallback& callback);
  void resetTmpConfigResponse(const bool& success);

  void setTmpConfigQuery(const Mqtt::JsonCallback& callback);
  void setTmpConfigResponse(const bool& success);

  void schedulerQuery(const Device& device, const std::string& query);
  void schedulerCallback(const Device& device, const Mqtt::JsonCallback& callback);

  void sendSpectrogram(const Device& device, const nlohmann::json& json);
  void sendTransmission(const Device& device, const nlohmann::json& json);

 private:
  void listCallback(const std::string& data);

  const Config& m_config;
  Mqtt& m_mqtt;
};
