#include "logger.h"

#include <spdlog/sinks/basic_file_sink.h>
#include <spdlog/sinks/daily_file_sink.h>
#include <spdlog/sinks/rotating_file_sink.h>
#include <spdlog/sinks/stdout_color_sinks.h>

void Logger::Logger::configure(
    const spdlog::level::level_enum logLevelConsole, const spdlog::level::level_enum logLevelFile, const std::string& logFile, int fileSize, int filesCount, bool isColorLogEnabled) {
  std::shared_ptr<spdlog::logger> logger = std::make_shared<spdlog::logger>("auto_sdr");

  if (logLevelConsole != spdlog::level::off) {
    auto consoleLogger = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
    consoleLogger->set_level(logLevelConsole);
    logger->sinks().push_back(consoleLogger);
  }

  if (logLevelFile != spdlog::level::off && !logFile.empty() && 0 < fileSize && 0 < filesCount) {
    auto fileLogger = std::make_shared<spdlog::sinks::rotating_file_sink_mt>(logFile, fileSize, filesCount);
    fileLogger->set_level(logLevelFile);
    logger->sinks().push_back(fileLogger);
  }

  isColorLogEnabled = isColorLogEnabled;
  logger->set_level(std::min(logLevelConsole, logLevelFile));
  logger->set_pattern("[%Y-%m-%d %H:%M:%S.%f] [%-7l] %v");
  spdlog::flush_every(std::chrono::seconds(30));
  spdlog::flush_on(spdlog::level::warn);
  spdlog::set_default_logger(logger);
}

bool Logger::isColorLogEnabled() { return _isColorLogEnabled; }