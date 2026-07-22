#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

echo "[终端 2] 启动 Ranger；publish_odom_tf 必须保持 false"
exec ros2 launch ranger_bringup ranger_mini_v3.launch.py \
  port_name:=can0 \
  publish_odom_tf:=false

