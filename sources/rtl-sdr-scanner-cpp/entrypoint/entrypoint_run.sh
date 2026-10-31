#!/bin/sh

sdrplay_apiService &
/usr/bin/auto_sdr --config /app/config.json --mqtt-url "$MQTT_URL" --mqtt-user "$MQTT_USER" --mqtt-password "$MQTT_PASSWORD"
