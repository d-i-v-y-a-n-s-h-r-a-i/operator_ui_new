#!/bin/bash
set -e

GCS_HOST="${1:-192.168.1.50}"
GCS_PORT="${2:-5000}"
CAM_DEV="${3:-/dev/video0}"

gst-launch-1.0 -v \
    v4l2src device="${CAM_DEV}" ! \
    video/x-raw, width=1920, height=1080, framerate=60/1 ! \
    nvvidconv ! \
    "video/x-raw(memory:NVMM), format=NV12" ! \
    nvv4l2h265enc bitrate=4500000 maxperf-enable=1 preset-level=1 insert-sps-pps=1 control-rate=1 ! \
    rtph265pay config-interval=1 pt=96 ! \
    udpsink host="${GCS_HOST}" port="${GCS_PORT}" sync=false async=false

