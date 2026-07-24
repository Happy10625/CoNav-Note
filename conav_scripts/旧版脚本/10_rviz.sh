#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

share_dir="$(ros2 pkg prefix co_nav2_nav)/share/co_nav2_nav"
rviz_config="${share_dir}/rviz/co_nav2_validation.rviz"

if [[ ! -f "$rviz_config" ]]; then
  echo "错误：找不到 RViz 配置：${rviz_config}" >&2
  echo "请先重新构建 co_nav2_nav 到 /home/isee-cdh/ws/install_ros2。" >&2
  exit 1
fi

echo "[终端 10] 启动 RViz 辅助验证"
echo "Fixed Frame=map；显示地图、TF、点云、scan、目标 Marker、里程计和 RGB。"
exec ros2 run rviz2 rviz2 -d "$rviz_config" \
  --ros-args -r __node:=conav_validation_rviz
