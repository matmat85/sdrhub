#pragma once

#include <config.h>
#include <mqtt/client.h>

#include <atomic>
#include <functional>
#include <mutex>
#include <queue>
#include <set>
#include <string>
#include <thread>
#include <vector>

class Mqtt {
 public:
  using RawCallback = std::function<void(const std::string&)>;
  using JsonCallback = std::function<void(const nlohmann::json&)>;

  Mqtt(const Config& config);
  ~Mqtt();

  void publish(const std::string& topic, const std::string& data, int qos = 0);
  void publish(const std::string& topic, const std::vector<uint8_t>& data, int qos = 0);
  void publish(const std::string& topic, const std::vector<uint8_t>&& data, int qos = 0);
  void setRawMessageCallback(const std::string& topic, const RawCallback& callback);
  void setJsonMessageCallback(const std::string& topic, const JsonCallback& callback);

 private:
  void connect();
  void onConnected();
  void onDisconnected();
  void onMessage(const std::string& topic, const std::string& data);
  void subscribe(const std::string& topic);

  const Config& m_config;
  mqtt::client m_client;
  std::atomic_bool m_isRunning;
  std::thread m_thread;
  std::mutex m_mutex;
  std::queue<std::tuple<std::string, std::vector<uint8_t>, int>> m_messages;
  std::set<std::string> m_topics;
  std::set<std::string> m_waitingTopics;
  std::vector<std::pair<std::string, RawCallback>> m_rawCallbacks;
  std::vector<std::pair<std::string, JsonCallback>> m_jsonCallbacks;
};
