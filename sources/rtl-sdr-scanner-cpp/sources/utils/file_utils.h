#pragma once

#include <nlohmann/json.hpp>

nlohmann::json readFromFile(const std::string& path, const nlohmann::json& defaultValue = {});

void saveToFile(const std::string& path, const nlohmann::json& json);