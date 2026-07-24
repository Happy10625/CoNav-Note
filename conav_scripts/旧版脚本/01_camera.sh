#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

echo "[终端 1] 启动 RealSense RGB-D 相机"
exec ros2 launch realsense2_camera rs_launch.py \
  align_depth.enable:=true \
  enable_sync:=true \
  rgb_camera.global_time_enabled:=true \
  depth_module.global_time_enabled:=true \
  rgb_camera.profile:=1280x720x30 \
  depth_module.profile:=640x480x30
