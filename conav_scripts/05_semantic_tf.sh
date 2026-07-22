#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

enable_adapter="${ENABLE_ODOM_ADAPTER:-true}"
publish_camera="${PUBLISH_CAMERA_TF:-true}"

echo "[终端 5] 启动统一 TF 与 Co-Nav2（保持 enabled=false）"
echo "enable_odom_adapter=${enable_adapter}, publish_camera_tf=${publish_camera}"

exec ros2 launch co_nav2_nav semantic_exploration.launch.py \
  enabled:=false \
  enable_perception:=true \
  open_space_mode:=true \
  allow_frontier_after_scan:=false \
  approach_enabled:=false \
  enable_odom_adapter:="${enable_adapter}" \
  publish_camera_tf:="${publish_camera}" \
  publish_lidar_tf:=false \
  publish_map_odom:=false

