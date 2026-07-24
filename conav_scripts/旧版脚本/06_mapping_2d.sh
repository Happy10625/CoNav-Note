#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

echo "[终端 6] 启动 FAST_LIO 点云二维建图"
exec ros2 launch co_nav2_nav fastlio_mapping_2d.launch.py

