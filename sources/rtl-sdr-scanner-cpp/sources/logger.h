#pragma once

#define FMT_HEADER_ONLY
#include <spdlog/spdlog.h>

constexpr auto RED = "\033[0;31m";
constexpr auto GREEN = "\033[0;32m";
constexpr auto BROWN = "\033[0;33m";
constexpr auto MAGENTA = "\033[0;35m";
constexpr auto CYAN = "\033[0;36m";
constexpr auto YELLOW = "\033[0;93m";
constexpr auto BLUE = "\033[0;94m";
constexpr auto NC = "\033[0m";

#define SPDLOG_LOC \
  spdlog::source_loc { __FILE__, __LINE__, SPDLOG_FUNCTION }

template <typename... Args>
using format_string = fmt::format_string<Args...>;

template <typename... Args>
std::string colored(const char* color, fmt::format_string<Args...> fmt, Args&&... args);

class Logger {
 private:
  Logger() = delete;
  ~Logger() = delete;

 public:
  static void configure(
      const spdlog::level::level_enum logLevelConsole, const spdlog::level::level_enum logLevelFile, const std::string& logFile, int fileSize, int filesCount, bool isColorLogEnabled);
  static bool isColorLogEnabled();

  template <typename... Args>
  static void trace(const char* label, fmt::format_string<Args...> fmt, Args&&... args) {
    auto msg = fmt::format(fmt, std::forward<Args>(args)...);
    spdlog::trace("[{:12}] {}", label, msg);
  }

  template <typename... Args>
  static void debug(const char* label, fmt::format_string<Args...> fmt, Args&&... args) {
    auto msg = fmt::format(fmt, std::forward<Args>(args)...);
    spdlog::debug("[{:12}] {}", label, msg);
  }

  template <typename... Args>
  static void info(const char* label, fmt::format_string<Args...> fmt, Args&&... args) {
    auto msg = fmt::format(fmt, std::forward<Args>(args)...);
    spdlog::info("[{:12}] {}", label, msg);
  }

  template <typename... Args>
  static void warn(const char* label, fmt::format_string<Args...> fmt, Args&&... args) {
    auto msg = fmt::format(fmt, std::forward<Args>(args)...);
    spdlog::warn("[{:12}] {}", label, msg);
  }

  template <typename... Args>
  static void error(const char* label, fmt::format_string<Args...> fmt, Args&&... args) {
    auto msg = fmt::format(fmt, std::forward<Args>(args)...);
    spdlog::error("[{:12}] {}", label, msg);
  }

  template <typename... Args>
  static void critical(const char* label, fmt::format_string<Args...> fmt, Args&&... args) {
    auto msg = fmt::format(fmt, std::forward<Args>(args)...);
    spdlog::critical("[{:12}] {}", label, msg);
  }

  template <typename... Args>
  static void exception(const char* label, const std::exception& exception, const spdlog::source_loc& loc, fmt::format_string<Args...> fmt, Args&&... args) {
    auto msg = fmt::format(fmt, std::forward<Args>(args)...);
#ifdef __DEBUG__
    spdlog::warn("[{:12}] {}, exception: {}, {}, {}", label, colored(RED, "{}", msg), exception.what(), loc.filename, loc.line);
#else
    std::ignore = loc;
    spdlog::warn("[{:12}] {}, exception: {}", label, colored(RED, "{}", msg), exception.what());
#endif
  }

  inline static bool _isColorLogEnabled = true;
};

template <typename... Args>
std::string colored(const char* color, fmt::format_string<Args...> fmt, Args&&... args) {
  if (Logger::isColorLogEnabled()) {
    auto msg = fmt::format(fmt, std::forward<Args>(args)...);
    return fmt::format("{}{}{}", color, msg, NC);
  } else {
    return fmt::format(fmt, std::forward<Args>(args)...);
  }
}