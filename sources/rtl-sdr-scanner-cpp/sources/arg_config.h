#pragma once

#include <string>

struct ArgConfig {
  std::string configFile;
  std::string id;
  std::string logFileName = "sdr_scanner.log";  // default log filename
  int logFileCount = 9;                         // default keep last n log files
  int logFileSize = 10 * 1024 * 1024;           // default single log file max size
  std::string mqttUrl;
  std::string mqttUser;
  std::string mqttPassword;
  std::string workDir = ".";
  bool enumerateRemote = false;
  bool dumpSource = false;
  bool dumpRecording = false;
};