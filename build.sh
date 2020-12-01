#!/bin/bash

export BUILDX_NO_DEFAULT_LOAD=false
docker buildx build --platform linux/arm/v7 -t ingemars/mqtt-audio-controller .