#include "application.h"

#include <logger.h>
#include <utils/file_utils.h>

constexpr auto LABEL = "application";

Application::Application(nlohmann::json& tmpJson, const ArgConfig& argConfig)
    : m_reload(false),
      m_argConfig(argConfig),
      m_tmpJson(tmpJson),
      m_fileJson(m_tmpJson.empty() ? readFromFile(m_argConfig.configFile, static_cast<nlohmann::json>(FileConfig())) : m_tmpJson),
      m_fileConfig(FileConfig::fromJson(m_fileJson, m_argConfig.enumerateRemote)),
      m_config(m_argConfig, m_fileConfig),
      m_mqtt(m_config),
      m_remoteController(m_config, m_mqtt) {
  Logger::configure(m_config.consoleLogLevel(), m_config.fileLogLevel(), m_argConfig.logFileName, m_argConfig.logFileSize, m_argConfig.logFileCount, m_config.isColorLogEnabled());
  Logger::info(LABEL, "{}", colored(GREEN, "{}", "started"));
  Logger::info(LABEL, "config: {}", colored(GREEN, "{}", FileConfig::toPrint(m_fileJson).dump()));
  Logger::info(LABEL, "mqtt: {}", colored(GREEN, "{}", m_config.mqtt()));

  for (const auto& device : m_config.devices()) {
    try {
      if (!device.enabled) {
        Logger::info(LABEL, "device disabled, skipping: {}", colored(GREEN, "{}", device.getName()));
      } else if (!device.device_args.empty() && !device.connected) {
        Logger::warn(LABEL, "remote device unavailable; retrying in 10 seconds: {}", device.getName());
        m_retryRemote = true;
      } else {
        m_scanners.push_back(std::make_unique<Scanner>(m_config, device, m_remoteController));
      }
    } catch (const std::exception& exception) {
      Logger::exception(LABEL, exception, SPDLOG_LOC, "open device failed: {}", device.getName());
      if (!device.device_args.empty()) {
        m_retryRemote = true;
      }
    }
  }
  if (m_scanners.empty()) {
    Logger::warn(LABEL, "{}", colored(RED, "{}", "empty devices list"));
  }

  m_remoteController.setConfigQuery([this](const nlohmann::json& json) {
    try {
      Logger::info(LABEL, "set config: {}", colored(GREEN, "{}", FileConfig::toPrint(json).dump()));
      saveToFile(m_argConfig.configFile, FileConfig::toSave(json));
      m_reload = true;
      m_tmpJson.clear();
      m_remoteController.setConfigResponse(true);
    } catch (const std::runtime_error& exception) {
      Logger::exception(LABEL, exception, SPDLOG_LOC, "set config failed");
      m_remoteController.setConfigResponse(false);
    }
  });

  m_remoteController.resetTmpConfigQuery([this](const std::string&) {
    Logger::info(LABEL, "reset tmp config");
    m_reload = true;
    m_tmpJson.clear();
    m_remoteController.resetTmpConfigResponse(true);
  });

  m_remoteController.setTmpConfigQuery([this](const nlohmann::json& json) {
    try {
      Logger::info(LABEL, "set tmp config: {}", colored(GREEN, "{}", FileConfig::toPrint(json).dump()));
      m_reload = true;
      m_tmpJson = json;
      m_remoteController.setConfigResponse(true);
    } catch (const std::runtime_error& exception) {
      Logger::exception(LABEL, exception, SPDLOG_LOC, "set tmp config failed");
      m_remoteController.setConfigResponse(false);
    }
  });

  m_remoteController.getConfigQuery([this](const std::string&) {
    Logger::info(LABEL, "get config");
    m_remoteController.getConfigResponse(static_cast<nlohmann::json>(m_fileConfig).dump());
  });
}

Application::~Application() { Logger::info(LABEL, "{}", colored(GREEN, "{}", "stopped")); }

bool Application::reload() const { return m_reload || (m_retryRemote && std::chrono::steady_clock::now() >= m_retryAt); }
