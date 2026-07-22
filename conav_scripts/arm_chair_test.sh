#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/common.sh"

echo "先执行完整快速检查……"
"${script_dir}/check_all.sh"

echo
echo "即将允许小车原地分段旋转寻找 chair。"
echo "必须满足：四周至少 1 m 空间、实体急停在手边、无人靠近车体。"
read -r -p "确认安全后输入 ARM（大写）继续：" answer
if [[ "$answer" != "ARM" ]]; then
  echo "已取消，没有启用小车。"
  exit 1
fi

ros2 param set /semantic_explorer enabled true
echo "识别已启用。观察状态终端，成功标志为 TARGET_CONFIRMED。"
echo "需要停止时立即运行：${script_dir}/stop_robot.sh"

