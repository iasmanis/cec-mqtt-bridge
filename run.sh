#!/bin/bash

. .env

docker stop  mqtt-audio-controller > /dev/null && docker rm mqtt-audio-controller > /dev/null

set -e

if [[ "$1" == "--pull" ]]; then
    docker pull ingemars/mqtt-audio-controller
fi

docker run -d --privileged \
    --name mqtt-audio-controller \
    --device /dev/mem:/dev/mem \
    -e MQTT_BROKER="${MQTT_BROKER}" \
    -e MQTT_PORT="${MQTT_PORT}" \
    -e MQTT_PREFIX="${MQTT_PREFIX}" \
    -e MQTT_USER="${MQTT_USER}" \
    -e MQTT_PASSWORD="${MQTT_PASSWORD}" \
    -e CEC_ENABLED="${CEC_ENABLED}" \
    -e CEC_ID="${CEC_ID}" \
    -e CEC_PORT="${CEC_PORT}" \
    -e IR_ENABLED="${IR_ENABLED}" \
    -e CEC_DEVICES="${CEC_DEVICES}" \
    -v "$(pwd)/assets/bridge.py:/app/bridge.py:ro" \
    ingemars/mqtt-audio-controller > /dev/null

docker logs -f mqtt-audio-controller
