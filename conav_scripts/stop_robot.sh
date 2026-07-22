#!/usr/bin/env bash
set -u
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

echo "停用 Co-Nav2、取消 Nav2 目标并发布零速度……"
ros2 param set /semantic_explorer enabled false 2>/dev/null || true
ros2 action cancel /navigate_to_pose --all 2>/dev/null || true
ros2 topic pub --once /cmd_vel geometry_msgs/msg/Twist '{}' >/dev/null 2>&1 || true

echo "当前 /odom 速度："
timeout 5 ros2 topic echo /odom --once --field twist.twist || true
echo "软件停车命令已完成；紧急情况下仍应使用实体急停。"

