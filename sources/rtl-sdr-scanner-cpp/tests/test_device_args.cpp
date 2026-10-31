#include <gtest/gtest.h>
#include <file_config.h>
#include <radio/device_args.h>
#include <radio/sdr_device_reader.h>

TEST(DeviceArgs, LocalDeviceSelectionIsUnchanged) {
  Device device;
  device.driver = "rtlsdr";
  device.serial = "00000001";
  EXPECT_EQ(getDeviceArgs(device), (SoapySDR::Kwargs{{"driver", "rtlsdr"}, {"serial", "00000001"}}));
}

TEST(DeviceArgs, ExplicitEndpointIsNotLostOrReplacedByDisplaySerial) {
  Device device;
  device.serial = "77465553";
  device.device_args = {{"driver", "rtltcp"}, {"rtltcp", "192.168.1.50:1234"}};
  EXPECT_EQ(getDeviceArgs(device), device.device_args);
  EXPECT_EQ(getDeviceArgs(device).count("serial"), 0);
}

TEST(DeviceArgs, RejectMissingDriverAndEndpoint) {
  Device device;
  device.device_args = {{"rtltcp", "192.168.1.50:1234"}};
  EXPECT_THROW(getDeviceArgs(device), std::runtime_error);
  device.device_args = {{"driver", "rtltcp"}};
  EXPECT_THROW(getDeviceArgs(device), std::runtime_error);
  device.device_args["rtltcp"] = "";
  EXPECT_THROW(getDeviceArgs(device), std::runtime_error);
}

TEST(DeviceArgs, SaveAndReloadPreserveRemoteArguments) {
  FileConfig config;
  Device remote;
  remote.driver = "rtltcp";
  remote.serial = "77465553";
  remote.device_args = {{"driver", "rtltcp"}, {"rtltcp", "loft-pi:1234"}};
  Device local;
  local.driver = "rtlsdr";
  local.serial = "00000001";
  config.devices = {remote, local};
  nlohmann::json saved = FileConfig::toSave(config);
  EXPECT_EQ(saved["devices"][0]["device_args"], nlohmann::json(remote.device_args));
  EXPECT_EQ(saved["devices"][0]["driver"], "rtltcp");
  EXPECT_FALSE(saved["devices"][0].contains("connected"));
  EXPECT_FALSE(saved["devices"][1].contains("driver"));
  const FileConfig restored = saved.get<FileConfig>();
  EXPECT_EQ(getDeviceArgs(restored.devices[0]), remote.device_args);
}

TEST(DeviceArgs, LegacyJsonDefaultsToAutomaticSelection) {
  const Device device = nlohmann::json{{"serial", "00000001"}, {"driver", "rtlsdr"}}.get<Device>();
  EXPECT_TRUE(device.device_args.empty());
  EXPECT_EQ(getDeviceArgs(device).at("serial"), "00000001");
}

TEST(DeviceArgs, InvalidExplicitDevicesCannotBeSaved) {
  FileConfig config;
  Device device;
  device.serial = "77465553";
  device.device_args = {{"driver", "rtltcp"}, {"rtltcp", ""}};
  config.devices = {device};
  EXPECT_THROW(FileConfig::toSave(config), std::runtime_error);
  config.devices[0].device_args["rtltcp"] = "loft-pi:1234";
  config.devices[0].serial = "";
  EXPECT_THROW(FileConfig::toSave(config), std::runtime_error);
}
