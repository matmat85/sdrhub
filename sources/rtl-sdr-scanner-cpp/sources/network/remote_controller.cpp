#include "remote_controller.h"

#include <utils/utils.h>

#include <nlohmann/json.hpp>

constexpr auto LIST = "list";
constexpr auto STATUS = "status";
constexpr auto CONFIG = "config";
constexpr auto TMP_CONFIG = "tmp_config";
constexpr auto RESET_TMP_CONFIG = "reset_tmp_config";
constexpr auto SCHEDULER = "scheduler";
constexpr auto SUCCESS = "success";
constexpr auto FAILED = "failed";
constexpr auto LABEL = "remote";
constexpr auto SPECTROGRAM = "spectrogram";
constexpr auto TRANSMISSION = "transmission";

using namespace std::placeholders;

RemoteController::RemoteController(const Config& config, Mqtt& mqtt) : m_config(config), m_mqtt(mqtt) { Logger::info(LABEL, "started, id: {}", colored(GREEN, "{}", m_config.getId())); }

void RemoteController::getConfigQuery(const Mqtt::RawCallback& callback) { m_mqtt.setRawMessageCallback(fmt::format("sdr/{}", LIST), callback); }
void RemoteController::getConfigResponse(const std::string& data) { m_mqtt.publish(fmt::format("sdr/{}/{}", STATUS, m_config.getId()), data, 2); }

void RemoteController::setConfigQuery(const Mqtt::JsonCallback& callback) { m_mqtt.setJsonMessageCallback(fmt::format("sdr/{}/{}", CONFIG, m_config.getId()), callback); }
void RemoteController::setConfigResponse(const bool& success) { m_mqtt.publish(fmt::format("sdr/{}/{}/{}", CONFIG, m_config.getId(), success ? SUCCESS : FAILED), "", 2); }

void RemoteController::resetTmpConfigQuery(const Mqtt::RawCallback& callback) { m_mqtt.setRawMessageCallback(fmt::format("sdr/{}/{}", RESET_TMP_CONFIG, m_config.getId()), callback); }
void RemoteController::resetTmpConfigResponse(const bool& success) { m_mqtt.publish(fmt::format("sdr/{}/{}/{}", RESET_TMP_CONFIG, m_config.getId(), success ? SUCCESS : FAILED), "", 2); }

void RemoteController::setTmpConfigQuery(const Mqtt::JsonCallback& callback) { m_mqtt.setJsonMessageCallback(fmt::format("sdr/{}/{}", TMP_CONFIG, m_config.getId()), callback); }
void RemoteController::setTmpConfigResponse(const bool& success) { m_mqtt.publish(fmt::format("sdr/{}/{}/{}", TMP_CONFIG, m_config.getId(), success ? SUCCESS : FAILED), "", 2); }

void RemoteController::schedulerQuery(const Device& device, const std::string& query) { m_mqtt.publish(fmt::format("sdr/{}/{}/{}/get", SCHEDULER, m_config.getId(), device.getName()), query, 2); }
void RemoteController::schedulerCallback(const Device& device, const Mqtt::JsonCallback& callback) {
  m_mqtt.setJsonMessageCallback(fmt::format("sdr/{}/{}/{}/set", SCHEDULER, m_config.getId(), device.getName()), callback);
}

void RemoteController::sendSpectrogram(const Device& device, const nlohmann::json& json) {
  m_mqtt.publish(fmt::format("sdr/{}/{}/{}", SPECTROGRAM, m_config.getId(), device.getAliasName()), json.dump(), 2);
}
void RemoteController::sendTransmission(const Device& device, const nlohmann::json& json) {
  m_mqtt.publish(fmt::format("sdr/{}/{}/{}", TRANSMISSION, m_config.getId(), device.getAliasName()), json.dump(), 2);
}
