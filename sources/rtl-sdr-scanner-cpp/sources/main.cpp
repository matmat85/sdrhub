#include <SoapySDR/Logger.h>
#include <application.h>
#include <logger.h>
#include <signal.h>

#include <CLI/CLI.hpp>
#include <memory>
#include <thread>

constexpr auto LABEL = "main";

volatile bool isRunning{true};

void handler(int) {
  Logger::warn(LABEL, "{}", colored(RED, "{}", "received stop signal"));
  isRunning = false;
}

int main(int argc, char** argv) {
  CLI::App app("sdr-scanner");
  argv = app.ensure_utf8(argv);

  ArgConfig argConfig;
  app.add_option("--config", argConfig.configFile, "config file")->required();
  app.add_option("--id", argConfig.id);
  app.add_option("--log-file", argConfig.logFileName, "log file");
  app.add_option("--log-file-count", argConfig.logFileCount, "log file count")->check(CLI::PositiveNumber);
  app.add_option("--log-file-size", argConfig.logFileSize, "log file size")->check(CLI::PositiveNumber);
  app.add_option("--mqtt-url", argConfig.mqttUrl, "mqtt url")->required();
  app.add_option("--mqtt-user", argConfig.mqttUser, "mqtt username")->required();
  app.add_option("--mqtt-password", argConfig.mqttPassword, "mqtt password")->required();
  app.add_option("--work-dir", argConfig.workDir, "work directory");
  app.add_option("--remote", argConfig.enumerateRemote, "enable remote device enumeration");
  app.add_option("--dump-source", argConfig.dumpSource, "dump source raw IQ");
  app.add_option("--dump-recording", argConfig.dumpRecording, "dump recording raw IQ");
  CLI11_PARSE(app, argc, argv);

  dup2(fileno(fopen("/dev/null", "w")), fileno(stderr));
  SoapySDR_setLogLevel(SoapySDRLogLevel::SOAPY_SDR_WARNING);
  signal(SIGINT, handler);
  signal(SIGTERM, handler);

  try {
    Logger::configure(spdlog::level::info, spdlog::level::info, argConfig.logFileName, argConfig.logFileSize, argConfig.logFileCount, true);
    Logger::info(LABEL, "{}", colored(GREEN, "{}", "started"));
    nlohmann::json tmpJson;
    while (isRunning) {
      Application application(tmpJson, argConfig);
      while (isRunning && !application.reload()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
      }
    }
    Logger::info(LABEL, "{}", colored(GREEN, "{}", "stopped"));
  } catch (const std::exception& exception) {
    Logger::exception(LABEL, exception, SPDLOG_LOC, "crash");
  }
  return 0;
}
