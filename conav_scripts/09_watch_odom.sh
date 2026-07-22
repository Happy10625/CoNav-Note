#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

echo "[监控] 底盘速度；本测试只允许 linear.x≈0、转向时 angular.z 非零"
exec ros2 topic echo /odom --field twist.twist

