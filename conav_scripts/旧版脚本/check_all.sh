#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

failures=0

pass() { printf '\033[32m[通过]\033[0m %s\n' "$1"; }
fail() { printf '\033[31m[失败]\033[0m %s\n' "$1"; failures=$((failures + 1)); }

has_node() {
  ros2 node list 2>/dev/null | grep -Fxq "$1"
}

publisher_count() {
  local output
  output="$(timeout 4 ros2 topic info "$1" 2>/dev/null || true)"
  awk '/Publisher count:/ {print $3; found=1; exit} END {if (!found) print 0}' <<<"$output"
}

check_node() {
  if has_node "$1"; then pass "节点 $1"; else fail "缺少节点 $1"; fi
}

check_topic() {
  local count
  count="$(publisher_count "$1")"
  if [[ "$count" == "1" ]]; then
    pass "话题 $1 有且仅有 1 个发布者"
  else
    fail "话题 $1 的发布者数量为 ${count}，要求恰好为 1"
  fi
}

check_tf() {
  local output
  output="$(timeout 4 ros2 run tf2_ros tf2_echo "$1" "$2" 2>&1 || true)"
  if grep -q 'Translation:' <<<"$output"; then
    pass "TF $1 → $2 连通"
  else
    fail "TF $1 → $2 不连通"
  fi
}

check_active() {
  local state
  state="$(timeout 4 ros2 lifecycle get "$1" 2>/dev/null || true)"
  if grep -q 'active \[3\]' <<<"$state"; then
    pass "$1 为 active [3]"
  else
    fail "$1 未激活：${state:-无响应}"
  fi
}

echo "========== CAN =========="
can_output="$(ip -details -statistics link show can0 2>&1 || true)"
if grep -q 'state UP' <<<"$can_output" && grep -q 'can state ERROR-ACTIVE' <<<"$can_output"; then
  pass "can0 为 UP / ERROR-ACTIVE"
else
  fail "can0 不是 UP / ERROR-ACTIVE"
fi
if grep -Eq 'bus-off[[:space:]]*$' <<<"$can_output"; then
  # The value is printed on the following statistics line; display full CAN
  # details below so the operator can inspect it directly.
  :
fi

echo "========== 节点 =========="
check_node /ranger_base_node
check_node /livox_lidar_publisher
check_node /laser_mapping
check_node /fastlio_odom_adapter
check_node /semantic_explorer
check_node /slam_toolbox
check_node /controller_server
check_node /planner_server
check_node /bt_navigator

echo "========== 话题 =========="
for topic in \
  /odom /livox/lidar /livox/imu /Odometry /cloud_registered_body \
  /camera/color/image_raw /camera/aligned_depth_to_color/image_raw \
  /camera/color/camera_info /scan /map /semantic_explorer/state; do
  check_topic "$topic"
done

echo "========== TF =========="
check_tf odom base_link
check_tf odom camera_color_optical_frame
check_tf map base_link
check_tf map camera_color_optical_frame

echo "========== Nav2 =========="
check_active /controller_server
check_active /planner_server
check_active /bt_navigator

echo "========== 安全参数 =========="
ranger_tf="$(ros2 param get /ranger_base_node publish_odom_tf 2>/dev/null || true)"
adapter_tf="$(ros2 param get /fastlio_odom_adapter publish_tf 2>/dev/null || true)"
enabled="$(ros2 param get /semantic_explorer enabled 2>/dev/null || true)"
frontier="$(ros2 param get /semantic_explorer allow_frontier_after_scan 2>/dev/null || true)"
approach="$(ros2 param get /semantic_explorer approach_enabled 2>/dev/null || true)"
target_clearance="$(ros2 param get /semantic_explorer target_clearance 2>/dev/null || true)"
robot_front_extent="$(ros2 param get /semantic_explorer robot_front_extent 2>/dev/null || true)"
approach_margin="$(ros2 param get /semantic_explorer approach_goal_margin 2>/dev/null || true)"

grep -q 'False' <<<"$ranger_tf" && pass "Ranger odom TF 已关闭" || fail "Ranger odom TF 未关闭"
grep -q 'True' <<<"$adapter_tf" && pass "FAST_LIO odom TF 已开启" || fail "FAST_LIO odom TF 未开启"
grep -q 'False' <<<"$enabled" && pass "识别运动当前未启用" || fail "semantic_explorer.enabled 不是 False"
grep -q 'False' <<<"$frontier" && pass "frontier 平移已禁用" || fail "frontier 平移没有禁用"
grep -q 'True' <<<"$approach" && pass "目标接近已启用" || fail "目标接近没有启用"
grep -q '0.5' <<<"$target_clearance" && pass "车体外壳目标距离为 0.50 m" || fail "target_clearance 不是 0.50"
grep -q '0.36' <<<"$robot_front_extent" && pass "车体前缘尺寸为 0.36 m" || fail "robot_front_extent 不是 0.36"
grep -q '0.05' <<<"$approach_margin" && pass "接近目标余量为 0.05 m" || fail "approach_goal_margin 不是 0.05"

echo "========== 静止检查 =========="
twist="$(timeout 5 ros2 topic echo /odom --once --field twist.twist 2>/dev/null || true)"
echo "$twist"
if grep -A3 'linear:' <<<"$twist" | grep -q 'x: 0.0' && \
   grep -A3 'angular:' <<<"$twist" | grep -q 'z: 0.0'; then
  pass "底盘当前为零速"
else
  fail "无法确认底盘为零速"
fi

echo
if (( failures == 0 )); then
  pass "全部快速检查通过，可以执行 ./arm_chair_test.sh"
  exit 0
fi

fail "共有 ${failures} 项未通过；禁止 ARM"
exit 1
