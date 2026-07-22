# Co-Nav2 + FAST_LIO2 运行方法（chair 原地识别测试）

本文档用于当前 Ranger Mini 3.0、Livox MID-360、FAST_LIO_ROS2、RealSense RGB-D、SLAM Toolbox、Nav2 和 Co-Nav2 系统。

当前测试目标是：小车在空旷区域原地分段旋转，识别放在侧面的 `chair`，发布椅子的 `map` 坐标；识别成功后停车，不进行 frontier 平移，不接近椅子。

> 本文档不再使用旧版 `ros_single_nav.py`、ZMQ 速度适配器或 ROS 1 bridge。不要同时启动这些旧节点。

---

# 一、运行前安全要求

1. 小车中心周围至少留出 `1 m` 无障碍空间。
2. 椅子放在小车右侧约 `1.5～2.5 m`，不要放进车体旋转范围。
3. 椅子到相机的有效深度必须小于 `4 m`，并保证光照正常、主体没有被遮挡。
4. 实体急停和遥控器必须放在操作人员手边。
5. 当前模式没有启用可靠的雷达动态避障，只允许在空旷场地进行原地识别。

任何时候需要软件停止，另开终端执行：

```bash
source /opt/ros/humble/setup.bash
source /home/isee-cdh/ws/install_ros2/setup.bash

ros2 param set /semantic_explorer enabled false
ros2 action cancel /navigate_to_pose --all
ros2 topic pub --once /cmd_vel geometry_msgs/msg/Twist '{}'
```

然后确认底盘速度为零：

```bash
timeout 5 ros2 topic echo /odom --once --field twist.twist
```

通过指标：

```text
linear.x = 0.0
linear.y = 0.0
angular.z = 0.0
```

---

# 二、每个新终端都要加载的环境

每次新开终端，先执行：

```bash
source /opt/ros/humble/setup.bash
source /home/isee-cdh/ros2_ws/install/setup.bash
source /home/isee-cdh/rs515/ros2_ws/install/setup.bash
source /home/isee-cdh/agilex_ws/install/setup.bash
source /home/isee-cdh/ws/install_fastlio/setup.bash
source /home/isee-cdh/ws/install_ros2/setup.bash
```

除非文档明确说明，否则每个 launch 终端都要一直保持运行。

## 快速脚本启动

上述重复开启终端的操作已经制作成脚本。正常使用时执行：

```bash
cd /home/isee-cdh/松灵小车/conav_scripts
./start_all.sh
```

该脚本严格按照本文终端 1～9 的顺序启动，并等待关键话题后再进入下一步。它只启动节点，不会自动让小车运动。

启动完成后检查：

```bash
./check_all.sh
```

确认全部通过后启用 chair 原地识别：

```bash
./arm_chair_test.sh
```

立即软件停车：

```bash
./stop_robot.sh
```

各终端的独立脚本和详细说明见：

```text
/home/isee-cdh/松灵小车/conav_scripts/README.md
```

---

# 三、仅在修改代码后重新构建

平时启动不需要重复构建。修改 `co_nav2_nav` 后执行：

```bash
cd /home/isee-cdh/ws

python3 -m py_compile \
  Co-NavGPT2/co_nav2_nav/co_nav2_nav/semantic_explorer.py \
  Co-NavGPT2/co_nav2_nav/launch/semantic_exploration.launch.py \
  Co-NavGPT2/co_nav2_nav/launch/open_space_search.launch.py

colcon build \
  --base-paths Co-NavGPT2/co_nav2_nav \
  --packages-select co_nav2_nav \
  --build-base build/co_nav2_nav_normal \
  --install-base install_ros2
```

通过指标：

```text
Finished <<< co_nav2_nav
Summary: 1 package finished
```

不要加入 `--symlink-install`。当前 Humble colcon 与新版 setuptools 组合会出现：

```text
error: option --editable not recognized
```

---

# 四、严格启动顺序

## 终端 1：启动 RealSense RGB-D 相机

先确认没有旧相机节点：

```bash
ros2 node list | grep camera
```

如果已经存在 `/camera/camera`，不要重复启动。需要重启时，先在旧相机终端按 `Ctrl+C`。

启动相机：

```bash
ros2 launch realsense2_camera rs_launch.py \
  align_depth.enable:=true \
  enable_sync:=true \
  rgb_camera.global_time_enabled:=true \
  depth_module.global_time_enabled:=true \
  rgb_camera.profile:=1280x720x30 \
  depth_module.profile:=640x480x30
```

### 检验相机

```bash
timeout 5 ros2 topic echo /camera/color/image_raw --once \
  | grep -E 'frame_id|height|width|encoding'

timeout 5 ros2 topic echo /camera/aligned_depth_to_color/image_raw --once \
  | grep -E 'frame_id|height|width|encoding'

ros2 topic info /camera/color/camera_info --verbose \
  | grep -E 'Publisher count|Node name'

timeout 6 ros2 topic hz /camera/color/image_raw
timeout 6 ros2 topic hz /camera/aligned_depth_to_color/image_raw
timeout 6 ros2 topic delay /camera/color/image_raw
```

通过指标：

```text
RGB 和 aligned depth 都是 1280×720（原始 depth 为 640×480，对齐后投影到 RGB 尺寸）
aligned depth 的 frame_id 为 camera_color_optical_frame
三个相机话题 Publisher count 都为 1
RGB 和 aligned depth 持续发布，实际频率建议不低于 10 Hz
RGB 平均延迟建议小于 0.15 s；当前实测约 0.05 s
```

如果 RGB 与 aligned depth 尺寸不一致，或 aligned depth 持续无数据，停止后续启动。

---

## 终端 2：检查 CAN 并启动 Ranger 底盘

检查 CAN：

```bash
ip -details -statistics link show can0
```

正常应包含：

```text
UP
LOWER_UP
can state ERROR-ACTIVE
bitrate 500000
bus-off 0
```

如果 `can0` 没有启动：

```bash
sudo ip link set can0 down
sudo ip link set can0 type can bitrate 500000
sudo ip link set can0 up
```

启动 Ranger Mini 3.0：

```bash
ros2 launch ranger_bringup ranger_mini_v3.launch.py \
  port_name:=can0 \
  publish_odom_tf:=false
```

> 使用 FAST_LIO 作为主定位时，Ranger 的 `publish_odom_tf` 必须一直保持 `false`。否则 Ranger 和 FAST_LIO 适配器会同时发布 `odom → base_link`。

### 检验底盘

```bash
ros2 param get /ranger_base_node publish_odom_tf
timeout 6 ros2 topic hz /odom
timeout 5 ros2 topic echo /odom --once --field twist.twist
ip -details -statistics link show can0
```

通过指标：

```text
publish_odom_tf = False
/odom 持续发布，通常约 50 Hz
测试开始前 linear.x、linear.y、angular.z 均为 0
CAN 为 ERROR-ACTIVE，bus-off 为 0
Ranger 终端没有持续出现 Failed to send CAN frame
```

如果 CAN 为 `ERROR-PASSIVE`、`BUS-OFF`，或者底盘静止时速度不归零，停止后续启动。

---

## 终端 3：启动 Livox MID-360

```bash
ros2 launch livox_ros_driver2 msg_MID360_launch.py
```

### 检验雷达和 IMU

```bash
timeout 6 ros2 topic hz /livox/lidar
timeout 6 ros2 topic hz /livox/imu
ros2 topic info /livox/lidar --verbose | grep -E 'Publisher count|Node name'
```

通过指标：

```text
/livox/lidar 约 10 Hz
/livox/imu 约 200 Hz
/livox/lidar 的 Publisher count 为 1
```

如果提示 `livox_ros_driver2/msg/CustomMsg is invalid`，通常是当前检查终端没有加载 `/home/isee-cdh/ros2_ws/install/setup.bash`。重新加载环境后再检查。

---

## 终端 4：启动 FAST_LIO_ROS2

```bash
ros2 launch fast_lio mapping.launch.py \
  config_file:=mid360.yaml \
  rviz:=false
```

启动时可能短暂出现一次：

```text
No point, skip this scan!
```

只要随后 `/Odometry` 和注册点云持续发布，就不属于故障。

### 检验 FAST_LIO

```bash
timeout 6 ros2 topic hz /Odometry
timeout 6 ros2 topic delay /Odometry
timeout 6 ros2 topic hz /cloud_registered
timeout 5 ros2 topic echo /Odometry --once \
  | grep -E 'frame_id|child_frame_id'
ros2 topic info /Odometry --verbose \
  | grep -E 'Publisher count|Node name'
```

通过指标：

```text
/Odometry 约 10 Hz
/cloud_registered 约 10 Hz
/Odometry 平均延迟建议小于 0.05 s；当前实测约 0.02 s
frame_id = camera_init
child_frame_id = body
/Odometry Publisher count = 1，发布节点为 laser_mapping
```

如果 `/Odometry` 延迟持续增长到数百毫秒或数秒，不要继续启动 Nav2。

---

## 终端 5：启动统一定位 TF 和 Co-Nav2 识别节点（保持禁用）

先确认没有旧适配节点：

```bash
ros2 node list | grep -E 'fastlio_odom_adapter|odom_to_fastlio_world|base_to_camera|semantic_explorer'
```

完全冷启动时不应有输出。如果有输出，先到旧 launch 终端按 `Ctrl+C`，不要重复发布同一 TF。

启动统一 TF 和识别节点：

```bash
ros2 launch co_nav2_nav semantic_exploration.launch.py \
  enabled:=false \
  enable_perception:=true \
  open_space_mode:=true \
  allow_frontier_after_scan:=false \
  approach_enabled:=false \
  enable_odom_adapter:=true \
  publish_camera_tf:=true \
  publish_lidar_tf:=false \
  publish_map_odom:=false
```

此时：

```text
FAST_LIO 适配器唯一发布 odom → base_link
odom → camera_init 由适配启动文件连接
base_link → camera_link 使用实测外参 (-0.20, 0, 1.215)
识别模型开始加载，但 enabled=false，因此小车不会运动
```

### 检验统一 TF 和识别节点

```bash
ros2 param get /fastlio_odom_adapter publish_tf
ros2 param get /semantic_explorer enabled
ros2 param get /semantic_explorer target_object
ros2 param get /semantic_explorer open_space_mode
ros2 param get /semantic_explorer allow_frontier_after_scan
ros2 param get /semantic_explorer approach_enabled

timeout 5 ros2 run tf2_ros tf2_echo odom base_link
timeout 5 ros2 run tf2_ros tf2_echo odom camera_color_optical_frame

ros2 topic list -t | grep semantic_explorer
```

通过指标：

```text
fastlio_odom_adapter.publish_tf = True
semantic_explorer.enabled = False
target_object = chair
open_space_mode = True
allow_frontier_after_scan = False
approach_enabled = False
odom → base_link 连续输出
odom → camera_color_optical_frame 连续输出
/semantic_explorer/state 类型为 std_msgs/msg/String
/semantic_explorer/markers 类型为 visualization_msgs/msg/MarkerArray
```

如果显示 `two or more unconnected trees`，不要继续；先检查终端 4 的 FAST_LIO 和本终端的适配器是否都在运行。

---

## 终端 6：启动 FAST_LIO 点云二维建图

```bash
ros2 launch co_nav2_nav fastlio_mapping_2d.launch.py
```

该 launch 执行：

```text
/cloud_registered_body → pointcloud_to_laserscan → /scan
/scan → SLAM Toolbox → /map 和 map → odom
```

### 检验二维地图

```bash
timeout 8 ros2 topic hz /scan
timeout 10 ros2 topic echo /map --once --qos-durability transient_local \
  | grep -E 'frame_id|resolution|width|height'
ros2 topic info /map --verbose | grep -E 'Publisher count|Node name'
timeout 5 ros2 run tf2_ros tf2_echo map base_link
timeout 5 ros2 run tf2_ros tf2_echo map camera_color_optical_frame
```

通过指标：

```text
/scan 持续发布，通常接近 10 Hz
/map frame_id = map
/map resolution = 0.05
/map width 和 height 大于 0
/map Publisher count = 1，发布节点为 slam_toolbox
map → base_link 连续输出
map → camera_color_optical_frame 连续输出
```

如果 `ros2 topic echo /map --once` 一直没有反应，按顺序检查：

```bash
ros2 node list | grep slam_toolbox
timeout 6 ros2 topic hz /cloud_registered_body
timeout 6 ros2 topic hz /scan
timeout 5 ros2 run tf2_ros tf2_echo odom base_link
```

---

## 终端 7：启动 Nav2 空旷场地配置

```bash
ros2 launch co_nav2_nav nav2_navigation.launch.py \
  overrides_file:=/home/isee-cdh/ws/install_ros2/co_nav2_nav/share/co_nav2_nav/config/nav2_open_space.yaml
```

该配置限制速度，并使用无 Spin、无 BackUp 恢复动作的行为树。

### 检验 Nav2

等待终端出现：

```text
Managed nodes are active
```

然后执行：

```bash
ros2 lifecycle get /controller_server
ros2 lifecycle get /planner_server
ros2 lifecycle get /bt_navigator
ros2 action info /navigate_to_pose
timeout 5 ros2 topic echo /odom --once --field twist.twist
```

通过指标：

```text
controller_server = active [3]
planner_server = active [3]
bt_navigator = active [3]
/navigate_to_pose 的 Action servers 数量至少为 1
启用测试前底盘线速度和角速度均为 0
```

如果任一 Nav2 核心节点不是 `active [3]`，不要启用识别运动。

---

# 五、执行 chair 原地识别测试

## 终端 8：监听识别状态

```bash
ros2 topic echo /semantic_explorer/state
```

如果提示：

```text
topic [/semantic_explorer/state] does not appear to be published yet
```

检查终端 5：

```bash
ros2 node list | grep semantic_explorer
ros2 node info /semantic_explorer
ros2 topic list -t | grep semantic_explorer
```

该提示表示 `/semantic_explorer` 节点没有运行或已经退出，不代表“尚未识别到椅子”。

---

## 终端 9：监听底盘速度

```bash
ros2 topic echo /odom --field twist.twist
```

测试过程中只允许出现原地转向：

```text
linear.x 应接近 0
linear.y 应接近 0
angular.z 可在转向时非零
```

如果 `linear.x` 持续明显非零，立即执行软件停止并按实体急停。

---

## 正式启用识别

确认终端 1～9 全部通过检验后执行：

```bash
ros2 param set /semantic_explorer enabled true
```

预期状态首先为：

```text
data: SEARCHING
```

小车将按 8 个方向分段原地旋转。连续确认椅子后状态变为：

```text
data: TARGET_CONFIRMED
```

终端 5 应出现：

```text
State -> TARGET_CONFIRMED
```

Nav2 会取消当前旋转目标。由于 `approach_enabled=false`，小车不会接近椅子；由于 `allow_frontier_after_scan=false`，扫描结束后也不会执行 frontier 平移。

### 查看椅子全局坐标

```bash
timeout 10 ros2 topic echo /semantic_explorer/markers --once
```

识别成功时应包含：

```yaml
frame_id: map
ns: target
pose:
  position:
    x: 有限数值
    y: 有限数值
    z: 有限数值
```

### 最终通过指标

```text
状态进入 TARGET_CONFIRMED
Marker 的 frame_id 为 map、ns 为 target
识别后 Nav2 目标被取消
底盘最终 linear.x、linear.y、angular.z 全部回到 0
整个测试没有发生直线探索或目标接近
```

停止并复核：

```bash
ros2 param set /semantic_explorer enabled false
ros2 action cancel /navigate_to_pose --all
ros2 topic pub --once /cmd_vel geometry_msgs/msg/Twist '{}'
timeout 5 ros2 topic echo /odom --once --field twist.twist
```

---

# 六、最短故障排查命令

## 1. 底盘或 CAN

```bash
ip -details -statistics link show can0
ros2 param get /ranger_base_node publish_odom_tf
timeout 5 ros2 topic echo /odom --once --field twist.twist
```

## 2. 雷达和 FAST_LIO

```bash
timeout 6 ros2 topic hz /livox/lidar
timeout 6 ros2 topic hz /livox/imu
timeout 6 ros2 topic hz /Odometry
timeout 6 ros2 topic delay /Odometry
```

## 3. 相机

```bash
timeout 6 ros2 topic hz /camera/color/image_raw
timeout 6 ros2 topic hz /camera/aligned_depth_to_color/image_raw
timeout 5 ros2 topic echo /camera/color/camera_info --once
```

需要查看画面时：

```bash
ros2 run rqt_image_view rqt_image_view
```

选择 `/camera/color/image_raw`。

## 4. TF

```bash
timeout 5 ros2 run tf2_ros tf2_echo odom base_link
timeout 5 ros2 run tf2_ros tf2_echo odom camera_init
timeout 5 ros2 run tf2_ros tf2_echo base_link camera_link
timeout 5 ros2 run tf2_ros tf2_echo map camera_color_optical_frame
```

## 5. 地图

```bash
timeout 6 ros2 topic hz /cloud_registered_body
timeout 6 ros2 topic hz /scan
ros2 topic info /map --verbose
```

## 6. Co-Nav2

```bash
ros2 node list | grep semantic_explorer
ros2 node info /semantic_explorer
ros2 topic list -t | grep semantic_explorer
ros2 param get /semantic_explorer enabled
ros2 param get /semantic_explorer target_object
```

## 7. 模型和 GPU

```bash
ls -lh /home/isee-cdh/ws/Co-NavGPT2/yolov8l-world.pt
ls -lh /home/isee-cdh/ws/Co-NavGPT2/mobile_sam.pt
nvidia-smi
```

---

# 七、正确的数据与 TF 链路

```text
Livox MID-360
   ├── /livox/lidar ──→ FAST_LIO_ROS2 ──→ /Odometry
   └── /livox/imu          │              /cloud_registered_body
                           │
                           └──→ FAST_LIO odom adapter
                                      │
                                      ▼
                            odom → base_link
                                      │
                 ┌────────────────────┴────────────────────┐
                 ▼                                         ▼
           livox/body TF                         camera_link → optical frames
                 │                                         │
                 ▼                                         ▼
       pointcloud_to_laserscan                    RGB + aligned depth
                 │                                         │
                 ▼                                         ▼
              /scan                              Co-Nav2 chair detection
                 │                                         │
                 ▼                                         ▼
          SLAM Toolbox                            target Marker in map
                 │
                 ▼
        /map + map → odom ──→ Nav2 原地分段转向
```

最终 TF 必须是一棵连通树：

```text
map → odom → base_link → camera_link → camera_color_optical_frame
          └→ camera_init → body
```

同一条 TF 只能有一个发布者。当前配置中：

```text
Ranger publish_odom_tf = false
FAST_LIO adapter publish_tf = true
SLAM Toolbox 负责 map → odom
Co-Nav2 静态 TF 节点负责 base_link → camera_link
```
