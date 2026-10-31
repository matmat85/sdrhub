#include <gtest/gtest.h>
#include <radio/scheduler.h>

#include <chrono>

using namespace std::chrono_literals;

TEST(Scheduler, Transmissions) {
  std::list<ScheduledTransmission> scheduledTransmissions;
  const Frequency f1(700);
  const Frequency f2(800);
  const Frequency f3(800);

  scheduledTransmissions.emplace_back("", "", 100s, 200s, f1, 20, "");
  scheduledTransmissions.emplace_back("", "", 150s, 200s, f2, 20, "");
  scheduledTransmissions.emplace_back("", "", 250s, 300s, f3, 20, "");

  {
    const auto result = Scheduler::getTransmissions(10s, scheduledTransmissions);
    EXPECT_EQ(result.size(), 0);
    EXPECT_EQ(scheduledTransmissions.size(), 3);
  }
  {
    const auto result = Scheduler::getTransmissions(99s, scheduledTransmissions);
    EXPECT_EQ(result.size(), 0);
    EXPECT_EQ(scheduledTransmissions.size(), 3);
  }
  {
    const auto result = Scheduler::getTransmissions(100s, scheduledTransmissions);
    EXPECT_EQ(result.size(), 1);
    EXPECT_EQ(result[0].frequency, f1);
    EXPECT_EQ(scheduledTransmissions.size(), 3);
  }
  {
    const auto result = Scheduler::getTransmissions(150s, scheduledTransmissions);
    EXPECT_EQ(result.size(), 2);
    EXPECT_EQ(result[0].frequency, f1);
    EXPECT_EQ(result[1].frequency, f2);
    EXPECT_EQ(scheduledTransmissions.size(), 3);
  }
  {
    const auto result = Scheduler::getTransmissions(200s, scheduledTransmissions);
    EXPECT_EQ(result.size(), 2);
    EXPECT_EQ(result[0].frequency, f1);
    EXPECT_EQ(result[1].frequency, f2);
    EXPECT_EQ(scheduledTransmissions.size(), 3);
  }
  {
    const auto result = Scheduler::getTransmissions(201s, scheduledTransmissions);
    EXPECT_EQ(result.size(), 0);
    EXPECT_EQ(scheduledTransmissions.size(), 1);
  }
  {
    const auto result = Scheduler::getTransmissions(250s, scheduledTransmissions);
    EXPECT_EQ(result.size(), 1);
    EXPECT_EQ(result[0].frequency, f3);
    EXPECT_EQ(scheduledTransmissions.size(), 1);
  }
  {
    const auto result = Scheduler::getTransmissions(301s, scheduledTransmissions);
    EXPECT_EQ(result.size(), 0);
    EXPECT_EQ(scheduledTransmissions.size(), 0);
  }
}

TEST(Scheduler, Recordings) {
  std::list<ScheduledTransmission> scheduledTransmissions;
  const Frequency f1(7000);
  const Frequency f2(7500);
  const Frequency f3(8050);
  const Frequency sampleRate(2000);
  const Frequency shift(100);

  scheduledTransmissions.emplace_back("", "", 100s, 300s, f1, 100, "");
  scheduledTransmissions.emplace_back("", "", 150s, 300s, f2, 100, "");
  scheduledTransmissions.emplace_back("", "", 200s, 300s, f3, 100, "");

  {
    const auto result = Scheduler::getRecordings(125s, scheduledTransmissions, sampleRate, shift);
    EXPECT_EQ(result->first, FrequencyRange(6100, 8100));
    EXPECT_EQ(result->second.size(), 1);
    EXPECT_EQ(result->second[0].shift(), -100);
  }
  {
    const auto result = Scheduler::getRecordings(175s, scheduledTransmissions, sampleRate, shift);
    EXPECT_EQ(result->first, FrequencyRange(6100, 8100));
    EXPECT_EQ(result->second.size(), 2);
    EXPECT_EQ(result->second[0].shift(), -100);
    EXPECT_EQ(result->second[1].shift(), 400);
  }
  {
    const auto result = Scheduler::getRecordings(225s, scheduledTransmissions, sampleRate, shift);
    EXPECT_EQ(result->first, FrequencyRange(6100, 8100));
    EXPECT_EQ(result->second.size(), 3);
    EXPECT_EQ(result->second[0].shift(), -100);
    EXPECT_EQ(result->second[1].shift(), 400);
    EXPECT_EQ(result->second[2].shift(), 950);
  }
}

TEST(Scheduler, RecordingsEdgeCase) {
  std::list<ScheduledTransmission> scheduledTransmissions;
  const Frequency f1(7000);
  const Frequency f2(6149);
  const Frequency f3(6150);
  const Frequency f4(8050);
  const Frequency f5(8051);
  const Frequency sampleRate(2000);
  const Frequency shift(100);

  scheduledTransmissions.emplace_back("", "", 200s, 300s, f1, 100, "");
  scheduledTransmissions.emplace_back("", "", 200s, 300s, f2, 100, "");
  scheduledTransmissions.emplace_back("", "", 200s, 300s, f3, 100, "");
  scheduledTransmissions.emplace_back("", "", 200s, 300s, f4, 100, "");
  scheduledTransmissions.emplace_back("", "", 200s, 300s, f5, 100, "");

  {
    const auto result = Scheduler::getRecordings(250s, scheduledTransmissions, sampleRate, shift);
    EXPECT_EQ(result->first, FrequencyRange(6100, 8100));
    EXPECT_EQ(result->second.size(), 3);
    EXPECT_EQ(result->second[0].shift(), -100);
    EXPECT_EQ(result->second[1].shift(), -950);
    EXPECT_EQ(result->second[2].shift(), 950);
  }
}
