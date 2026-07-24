#!/usr/bin/env bash

# Keep a generated terminal visible when its launch command exits with an
# error, so the operator can read the real ROS error instead of seeing a flash.
set +e
script="$1"
shift
bash "$script" "$@"
status=$?

echo
if (( status == 0 )); then
  echo "进程已结束（exit=${status}）。"
else
  echo "启动命令失败（exit=${status}）。请保留本窗口并检查上方错误。"
fi
read -r -p "按 Enter 关闭此终端……" _
exit "$status"

