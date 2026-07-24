#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/common.sh"

if ! command -v gnome-terminal >/dev/null 2>&1; then
  echo "错误：没有找到 gnome-terminal。请分别运行 01～10 脚本。" >&2
  exit 1
fi

has_node() {
  ros2 node list 2>/dev/null | grep -Fxq "$1"
}

publisher_count() {
  local output
  output="$(timeout 4 ros2 topic info "$1" 2>/dev/null || true)"
  awk '/Publisher count:/ {print $3; found=1; exit} END {if (!found) print 0}' <<<"$output"
}

has_publisher() {
  (( $(publisher_count "$1") > 0 ))
}

require_single_publisher() {
  local topic="$1" description="$2" count
  count="$(publisher_count "$topic")"
  if [[ "$count" != "1" ]]; then
    echo "错误：${description} ${topic} 有 ${count} 个发布者，要求恰好为 1。" >&2
    echo "请关闭残留或重复 launch 后重试。" >&2
    return 1
  fi
}

wait_for_publisher() {
  local topic="$1" timeout_seconds="$2" description="$3"
  local end=$((SECONDS + timeout_seconds))
  printf '等待 %s ' "$description"
  while (( SECONDS < end )); do
    if has_publisher "$topic"; then
      echo "通过"
      return 0
    fi
    printf '.'
    sleep 1
  done
  echo
  echo "错误：${description} 在 ${timeout_seconds}s 内没有发布。请查看对应终端。" >&2
  return 1
}

open_terminal() {
  local title="$1" script="$2"
  shift 2
  echo "打开：${title}"
  gnome-terminal --window --title="$title" -- env "$@" \
    bash "${script_dir}/terminal_runner.sh" "$script"
}

echo "Co-Nav2 严格顺序启动器"
echo "本脚本只启动节点，绝不会自动 ARM 小车。"

camera_publishers="$(publisher_count /camera/color/image_raw)"
if (( camera_publishers > 1 )); then
  echo "错误：相机 RGB 有 ${camera_publishers} 个发布者，请关闭重复相机节点。" >&2
  exit 1
elif (( camera_publishers == 1 )); then
  echo "跳过终端 1：相机节点已经运行"
else
  open_terminal "CoNav-01 相机" "${script_dir}/01_camera.sh"
fi
wait_for_publisher /camera/aligned_depth_to_color/image_raw 40 "aligned depth"
require_single_publisher /camera/color/image_raw "相机"
require_single_publisher /camera/aligned_depth_to_color/image_raw "相机"

ranger_publishers="$(publisher_count /odom)"
if (( ranger_publishers > 1 )); then
  echo "错误：/odom 有 ${ranger_publishers} 个发布者，请关闭重复 Ranger 节点。" >&2
  exit 1
elif (( ranger_publishers == 1 )); then
  echo "跳过终端 2：Ranger 节点已经运行"
else
  can_output="$(ip -details link show can0 2>&1 || true)"
  if ! grep -q '^[0-9].*can0:' <<<"$can_output"; then
    echo "错误：未找到 can0，请检查 USB-CAN 连接。" >&2
    exit 1
  fi
  open_terminal "CoNav-02 Ranger" "${script_dir}/02_ranger.sh"
fi
# can0 为 DOWN 时，终端 2 会请求 sudo 密码，因此留足输入时间。
wait_for_publisher /odom 60 "Ranger /odom"
require_single_publisher /odom "Ranger"
ranger_tf="$(ros2 param get /ranger_base_node publish_odom_tf 2>/dev/null || true)"
if ! grep -q 'False' <<<"$ranger_tf"; then
  echo "错误：Ranger publish_odom_tf 不是 false。为防止 odom → base_link 双发布，停止启动。" >&2
  exit 1
fi

livox_publishers="$(publisher_count /livox/lidar)"
if (( livox_publishers > 1 )); then
  echo "错误：/livox/lidar 有 ${livox_publishers} 个发布者，请关闭重复 Livox 驱动。" >&2
  exit 1
elif (( livox_publishers == 1 )); then
  echo "跳过终端 3：Livox 节点已经运行"
else
  open_terminal "CoNav-03 Livox" "${script_dir}/03_livox.sh"
fi
wait_for_publisher /livox/lidar 30 "Livox 点云"
wait_for_publisher /livox/imu 20 "Livox IMU"
require_single_publisher /livox/lidar "Livox"
require_single_publisher /livox/imu "Livox"

odometry_publishers="$(publisher_count /Odometry)"
if (( odometry_publishers > 1 )); then
  echo "错误：/Odometry 有 ${odometry_publishers} 个发布者。请关闭重复 FAST_LIO。" >&2
  exit 1
elif (( odometry_publishers == 1 )); then
  echo "跳过终端 4：FAST_LIO 已经运行"
else
  open_terminal "CoNav-04 FAST_LIO" "${script_dir}/04_fastlio.sh"
fi
wait_for_publisher /Odometry 70 "FAST_LIO /Odometry"
wait_for_publisher /cloud_registered_body 30 "FAST_LIO body 点云"
require_single_publisher /Odometry "FAST_LIO"
require_single_publisher /cloud_registered_body "FAST_LIO"

fastlio_position="$(timeout 5 ros2 topic echo /Odometry --once --field pose.pose.position 2>/dev/null || true)"
if ! awk '
  /x:/ {x=$2; hx=1}
  /y:/ {y=$2; hy=1}
  /z:/ {z=$2; hz=1}
  END {exit !(hx && hy && hz && x>-10 && x<10 && y>-10 && y<10 && z>-10 && z<10)}
' <<<"$fastlio_position"; then
  echo "错误：FAST_LIO 初始位置缺失或超出 ±10 m，可能已经发散：" >&2
  echo "$fastlio_position" >&2
  exit 1
fi

adapter_present=false
world_present=false
camera_tf_present=false
has_node /fastlio_odom_adapter && adapter_present=true
has_node /odom_to_fastlio_world && world_present=true
has_node /base_to_camera && camera_tf_present=true

if [[ "$adapter_present" != "$world_present" ]]; then
  echo "错误：FAST_LIO TF 适配节点只启动了一部分。请关闭残留节点后重试。" >&2
  exit 1
fi

semantic_publishers="$(publisher_count /semantic_explorer/state)"
if (( semantic_publishers > 1 )); then
  echo "错误：semantic_explorer/state 有 ${semantic_publishers} 个发布者，请关闭重复识别节点。" >&2
  exit 1
elif (( semantic_publishers == 1 )); then
  echo "跳过终端 5：semantic_explorer 已经运行"
  existing_enabled="$(ros2 param get /semantic_explorer enabled 2>/dev/null || true)"
  existing_frontier="$(ros2 param get /semantic_explorer allow_frontier_after_scan 2>/dev/null || true)"
  existing_approach="$(ros2 param get /semantic_explorer approach_enabled 2>/dev/null || true)"
  if ! grep -q 'False' <<<"$existing_enabled" || \
     ! grep -q 'False' <<<"$existing_frontier" || \
     ! grep -q 'True' <<<"$existing_approach"; then
    echo "错误：现有 semantic_explorer 不是安全禁用配置。请先运行 stop_robot.sh 并关闭旧 launch。" >&2
    exit 1
  fi
else
  enable_adapter=true
  publish_camera=true
  [[ "$adapter_present" == true ]] && enable_adapter=false
  [[ "$camera_tf_present" == true ]] && publish_camera=false
  open_terminal "CoNav-05 统一TF与识别" "${script_dir}/05_semantic_tf.sh" \
    ENABLE_ODOM_ADAPTER="$enable_adapter" \
    PUBLISH_CAMERA_TF="$publish_camera"
fi

end=$((SECONDS + 90))
printf '等待 semantic_explorer '
until has_node /semantic_explorer; do
  if (( SECONDS >= end )); then
    echo
    echo "错误：semantic_explorer 启动超时。请查看终端 5。" >&2
    exit 1
  fi
  printf '.'
  sleep 1
done
echo "通过"

scan_publishers="$(publisher_count /scan)"
map_publishers="$(publisher_count /map)"
if (( scan_publishers > 1 || map_publishers > 1 )); then
  echo "错误：检测到重复二维建图发布者（scan=${scan_publishers}, map=${map_publishers}）。" >&2
  exit 1
elif (( scan_publishers == 1 && map_publishers == 0 )); then
  echo "错误：存在孤立的 /scan 发布者但没有 /map。请关闭残留 fastlio_mapping_2d launch。" >&2
  exit 1
elif (( scan_publishers == 0 && map_publishers == 1 )); then
  echo "错误：存在 /map 发布者但没有 /scan，二维建图链路不完整。" >&2
  exit 1
elif (( scan_publishers == 1 && map_publishers == 1 )); then
  echo "跳过终端 6：二维建图已经运行"
else
  open_terminal "CoNav-06 二维建图" "${script_dir}/06_mapping_2d.sh"
fi
wait_for_publisher /map 45 "二维地图 /map"
require_single_publisher /scan "二维建图"
require_single_publisher /map "二维建图"

if has_node /controller_server || has_node /planner_server || has_node /bt_navigator; then
  if has_node /controller_server && has_node /planner_server && has_node /bt_navigator; then
    echo "跳过终端 7：Nav2 核心节点已经运行"
  else
    echo "错误：Nav2 只启动了一部分。请关闭残留 Nav2 节点后重试。" >&2
    exit 1
  fi
else
  open_terminal "CoNav-07 Nav2" "${script_dir}/07_nav2.sh"
fi

end=$((SECONDS + 60))
printf '等待 Nav2 激活 '
while (( SECONDS < end )); do
  state="$(timeout 3 ros2 lifecycle get /bt_navigator 2>/dev/null || true)"
  if grep -q 'active \[3\]' <<<"$state"; then
    echo "通过"
    break
  fi
  printf '.'
  sleep 1
done
if ! grep -q 'active \[3\]' <<<"${state:-}"; then
  echo
  echo "错误：Nav2 未在 60s 内激活。请查看终端 7。" >&2
  exit 1
fi

open_terminal "CoNav-08 识别状态" "${script_dir}/08_watch_state.sh"
open_terminal "CoNav-09 底盘速度" "${script_dir}/09_watch_odom.sh"
if has_node /conav_validation_rviz; then
  echo "跳过终端 10：Co-Nav2 RViz 已经运行"
else
  open_terminal "CoNav-10 RViz验证" "${script_dir}/10_rviz.sh"
fi

echo
echo "所有节点已按顺序启动，但小车尚未 ARM。"
echo "下一步："
echo "  1. 执行 ${script_dir}/check_all.sh"
echo "  2. 检查周围空间和实体急停"
echo "  3. 执行 ${script_dir}/arm_chair_test.sh"
