#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-dry-run}"
if [[ "$MODE" != "dry-run" && "$MODE" != "--apply" ]]; then
  echo "用法: bash $0 [--apply]" >&2
  exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CORE="$SCRIPT_DIR/core"
[[ -d "$CORE" ]] || { echo "找不到 $CORE；请在解压后的迁移包根目录运行。" >&2; exit 1; }

RSYNC_ARGS=(-a --itemize-changes --mkpath)
if [[ "$MODE" == "dry-run" ]]; then
  RSYNC_ARGS+=(--dry-run)
  echo "当前为预演模式，不会写入。以下目标基于新电脑 HOME=$HOME"
else
  echo "正在恢复源码到 HOME=$HOME；不会删除目标中额外存在的文件。"
fi

restore_tree() {
  local relative="$1"
  [[ -d "$CORE/$relative" ]] || return 0
  rsync "${RSYNC_ARGS[@]}" "$CORE/$relative/" "$HOME/$relative/"
}

restore_tree agilex_ws/src
restore_tree ros2_ws/src/livox_ros_driver2
restore_tree ws/Livox-SDK2
restore_tree rs515/ros2_ws/src
restore_tree rs515/librealsense-2.51.1
restore_tree ws/FAST_LIO_ROS2
restore_tree ws/VLM_Nav

if [[ "$MODE" == "--apply" && -d "$CORE/ros_runtime/vlm_nav" ]]; then
  mkdir -p "$HOME/.ros/vlm_nav"
  rsync -a --itemize-changes "$CORE/ros_runtime/vlm_nav/" "$HOME/.ros/vlm_nav/"
fi

if [[ "$MODE" == "dry-run" ]]; then
  echo "预演结束。确认目标路径后执行: bash $0 --apply"
else
  echo "源码恢复完成。请按 README 和迁移清单安装依赖、修正路径并重新编译。"
fi
