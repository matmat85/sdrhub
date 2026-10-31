#include "file_utils.h"

#include <fstream>

nlohmann::json readFromFile(const std::string& path, const nlohmann::json& defaultValue) {
  std::ifstream stream(path);
  if (stream) {
    try {
      return nlohmann::json::parse(stream);
    } catch (const std::runtime_error&) {
      return defaultValue;
    }
  } else {
    return defaultValue;
  }
}

void saveToFile(const std::string& path, const nlohmann::json& json) {
  std::ofstream stream(path);
  if (stream) {
    stream << std::setw(4) << json << std::endl;
  }
}