#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

echo "[终端 7] 启动 Nav2 空旷场地配置"
exec ros2 launch co_nav2_nav nav2_navigation.launch.py \
  overrides_file:=/home/isee-cdh/ws/install_ros2/co_nav2_nav/share/co_nav2_nav/config/nav2_open_space.yaml

