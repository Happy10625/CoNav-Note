#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/common.sh"

echo "先执行完整快速检查……"
"${script_dir}/check_all.sh"

echo
echo "即将允许小车旋转寻找 chair，并在识别后移动至车体前缘距目标 0.5 m 内。"
echo "必须满足：完整接近路径和目标四周无人、无台阶/落差，实体急停在手边。"
read -r -p "确认安全后输入 ARM（大写）继续：" answer
if [[ "$answer" != "ARM" ]]; then
  echo "已取消，没有启用小车。"
  exit 1
fi

ros2 param set /semantic_explorer enabled true
echo "识别和接近已启用。观察状态终端，成功标志为 SUCCEEDED。"
echo "需要停止时立即运行：${script_dir}/stop_robot.sh"
