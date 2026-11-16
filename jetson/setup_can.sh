#!/bin/bash
set -e

sudo modprobe can
sudo modprobe can_raw
sudo modprobe mttcan

sudo ip link set can0 down 2>/dev/null || true
sudo ip link set can0 type can bitrate 250000 berr-reporting on restart-ms 100
sudo ip link set can0 txqueuelen 1000
sudo ip link set can0 up

ip -details link show can0

