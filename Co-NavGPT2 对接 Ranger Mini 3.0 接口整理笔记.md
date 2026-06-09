# Co-NavGPT2 对接 Ranger Mini 3.0 接口整理笔记

## 1. 当前项目目标

我现在要复现 Co-NavGPT2 项目，硬件包括：

- Ranger Mini 3.0 小车
- 另一台机器狗
- 目标是让两台机器人协同运行 Co-NavGPT2 的多机器人视觉语义导航

我目前负责的是 **Ranger Mini 3.0 小车部分**，主要任务不是重写 Co-NavGPT2 算法，而是弄清楚：

1. Co-NavGPT2 需要哪些 ROS2 topic / TF / 控制接口。
2. Ranger Mini 3.0 通过 `ranger_ros2` 提供了哪些 topic。
3. 两边接口是否匹配。
4. 如果不匹配，需要写什么 adapter / bridge。

---

## 2. 使用到的仓库

### Co-NavGPT2

仓库：

```text
https://github.com/ybgdgh/Co-NavGPT2
```

本地目录：

```text
D:\Nav_Projects\Co-NavGPT2
```

作用：

- 提供 Co-NavGPT2 的仿真和真实机器人 ROS2 代码。
- 真实机器人代码主要在：
  - `ros_single_nav.py`
  - `ros_multi_nav.py`
  - `multi_lidar_icp.py`

---

### ranger_ros2

仓库：

```text
https://github.com/agilexrobotics/ranger_ros2
```

本地目录：

```text
D:\Nav_Projects\ranger_ros2
```

作用：

- Ranger Mini / Ranger 底盘的 ROS2 封装。
- 对外提供 ROS2 topic，例如 `/cmd_vel`、`/odom`。
- 内部依赖 `ugv_sdk` 控制底盘。

---

### ugv_sdk

仓库：

```text
https://github.com/agilexrobotics/ugv_sdk
```

作用：

- AgileX 小车底层 C++ SDK。
- 负责 CAN 通信、底盘状态读取、运动命令下发。
- `ranger_ros2` 内部会调用它。
- 一般对接 Co-NavGPT2 时优先参考 `ranger_ros2`，不直接调用 `ugv_sdk`。

关系：

```text
Co-NavGPT2 / 自己写的 adapter
        ↓
ranger_ros2
        ↓
ugv_sdk
        ↓
Ranger Mini 3.0 硬件
```

---

## 3. Ranger Mini 3.0 底盘 ROS2 接口

来自 `ranger_ros2` README 和源码。

### Parameters

```text
can_device: can0
robot_model: ranger / ranger_mini_v1 / ranger_mini_v2 / ranger_mini_v3
update_rate: 50
base_frame: base_link
odom_frame: odom
publish_odom_tf: true
odom_topic_name: odom
```

### Published topics

```text
/system_state     ranger_msgs/msg/SystemState
/motion_state     ranger_msgs/msg/MotionState
/actuator_state   ranger_msgs/msg/ActuatorStateArray
/odom             nav_msgs/msg/Odometry
/battery_state    sensor_msgs/msg/BatteryState
```

### Subscribed topics

```text
/cmd_vel          geometry_msgs/msg/Twist
```

源码中对应位置大概是：

```cpp
void RangerROSMessenger::SetupSubscription() {
  system_state_pub_ =
      node_->create_publisher<ranger_msgs::msg::SystemState>("/system_state", 10);
  motion_state_pub_ =
      node_->create_publisher<ranger_msgs::msg::MotionState>("/motion_state", 10);
  actuator_state_pub_ =
      node_->create_publisher<ranger_msgs::msg::ActuatorStateArray>("/actuator_state", 10);
  odom_pub_ = node_->create_publisher<nav_msgs::msg::Odometry>(odom_topic_name_, 10);
  battery_state_pub_ =
      node_->create_publisher<sensor_msgs::msg::BatteryState>("/battery_state", 10);

  motion_cmd_sub_ = node_->create_subscription<geometry_msgs::msg::Twist>(
      "/cmd_vel", 5, std::bind(&RangerROSMessenger::TwistCmdCallback, this, std::placeholders::_1)
      );

  tf_broadcaster_ = std::make_shared<tf2_ros::TransformBroadcaster>(node_);
}
```

结论：

```text
Ranger 小车底盘真正接收控制的是 /cmd_vel。
```

---

## 4. Co-NavGPT2 目前查到的 ROS2 输入输出

### 4.1 Co-NavGPT2 的相机输入

单机器人代码 `ros_single_nav.py` 中：

```python
self.rgb_sub = message_filters.Subscriber(
    self,
    Image,
    '/robot1/camera/color/image_raw',
    qos_profile=qos_profile_reliable
)

self.depth_sub = message_filters.Subscriber(
    self,
    Image,
    '/robot1/camera/aligned_depth_to_color/image_raw',
    qos_profile=qos_profile_reliable
)
```

CameraInfo：

```python
self.create_subscription(
    CameraInfo,
    '/robot1/camera/color/camera_info',
    self.camera_info_callback,
    10
)
```

所以单机器人 Co-NavGPT2 需要：

```text
/robot1/camera/color/image_raw
/robot1/camera/aligned_depth_to_color/image_raw
/robot1/camera/color/camera_info
```

多机器人 `ros_multi_nav.py` 中，topic 是按 robot id 拼出来的：

```python
rgb_topic = f'/robot{i+1}/camera/color/image_raw'
depth_topic = f'/robot{i+1}/camera/aligned_depth_to_color/image_raw'
camera_info_topic = f'/robot{i+1}/camera/color/camera_info'
```

也就是：

```text
/robot1/camera/color/image_raw
/robot1/camera/aligned_depth_to_color/image_raw
/robot1/camera/color/camera_info

/robot2/camera/color/image_raw
/robot2/camera/aligned_depth_to_color/image_raw
/robot2/camera/color/camera_info
```

---

### 4.2 Co-NavGPT2 的 TF 输入

单机器人代码中查：

```python
transform = self.tf_buffer.lookup_transform(
    "camera_init_1",
    "body_1",
    self.global_timestamp,
    timeout=rclpy.duration.Duration(seconds=0.0)
)
```

所以 Co-NavGPT2 需要 TF：

```text
camera_init_1 -> body_1
```

多机器人时还有类似：

```text
camera_init_1 -> body_1
camera_init_1 -> body_2
camera_init_2 -> body_2
```

注意：

- TF 不是普通 `create_subscription`。
- TF 通过 `/tf` 和 `/tf_static` 传输。
- 要用 `tf2_echo` 或 `view_frames` 查。

---

### 4.3 Co-NavGPT2 的动作输出

目前查到：

```python
self.velocity_publisher = self.create_publisher(Twist, '/robot_action', 10)
```

但需要注意：

```text
/robot_action 不是 Ranger 小车会听的 topic。
Ranger 只听 /cmd_vel。
```

之前分析中还提到 Co-NavGPT2 真实机器人代码可能通过 ZMQ / socket 发送类似 Unitree Go2 的控制字符串：

```text
speedctl speed|0.3|0.0|0.0
speedctl speed|0.0|0.0|0.5
speedctl speed|0.0|0.0|-0.5
```

但我在 cmd 中用 `findstr` 搜索时，第一条命令没搜出结果，可能是 `findstr` 用法问题，所以要继续用更稳的 `/C:"关键词"` 方式确认。

---

## 5. 现在的关键判断

Co-NavGPT2 的输入 **不一定天然对应** 小车发布的 topic。

Ranger 小车底盘发布的是：

```text
/odom
/system_state
/motion_state
/actuator_state
/battery_state
```

但 Co-NavGPT2 主要需要的是：

```text
RGB 图像
Depth 图像
CameraInfo
TF: camera_init_1 -> body_1
```

这些相机 topic 通常不是 Ranger 底盘发布的，而是 RealSense 或其他 RGB-D 相机驱动发布的。

所以需要对表：

```text
Co-NavGPT2 需要什么
        ↓
实际小车 + 相机 + TF 提供什么
        ↓
对不上就需要 remap / bridge / adapter
```

---

## 6. 接下来我正在进行的步骤

### Step 1：确认 Co-NavGPT2 到底有哪些输入输出

我在 Windows cmd 里操作。

进入项目目录：

```cmd
cd /d D:\Nav_Projects
dir
```

查 ROS 订阅输入：

```cmd
findstr /S /N /I /C:"create_subscription" /C:"message_filters.Subscriber" /C:"Subscriber" Co-NavGPT2\*.py
```

查 TF：

```cmd
findstr /S /N /I /C:"lookup_transform" /C:"tf_buffer" /C:"TransformListener" Co-NavGPT2\*.py
```

查动作输出、socket、ZMQ：

```cmd
findstr /S /N /I /C:"socket" /C:"zmq" /C:"send" /C:"cmd_vel" /C:"Twist" /C:"speedctl" Co-NavGPT2\*.py
```

---

### Step 2：启动 Ranger 底盘

我尝试运行：

```cmd
ros2 launch ranger_bringup ranger_mini_v3.launch.py publish_odom_tf:=true
```

但是报错：

```text
ranger_bringup not found
```

这说明 ROS2 当前找不到 `ranger_bringup` 这个 package。

可能原因：

1. `ranger_ros2` 还没有放进标准 ROS2 workspace。
2. 没有执行过 `colcon build`。
3. build 后没有 source `install/setup.bat`。
4. 缺少依赖 `ugv_sdk`。

---

## 7. 解决 `ranger_bringup not found` 的步骤

先确认 ROS2 当前能不能看到 Ranger package：

```cmd
ros2 pkg list | findstr ranger
```

如果没有输出，说明当前 ROS2 环境没有加载 `ranger_ros2`。

推荐 workspace 结构：

```text
D:\Nav_Projects\agilex_ws
  └── src
      ├── ranger_ros2
      └── ugv_sdk
```

注意：

```text
ranger_ros2 依赖 ugv_sdk。
只放 ranger_ros2 可能不够。
```

进入 workspace 根目录：

```cmd
cd /d D:\Nav_Projects\agilex_ws
```

构建：

```cmd
colcon build
```

构建成功后，在同一个 cmd 终端 source：

```cmd
call install\setup.bat
```

再次检查：

```cmd
ros2 pkg list | findstr ranger
```

应该看到类似：

```text
ranger_base
ranger_bringup
ranger_msgs
```

然后再启动：

```cmd
ros2 launch ranger_bringup ranger_mini_v3.launch.py publish_odom_tf:=true
```

---

## 8. 启动 Ranger 后要做的检查

### 查看 topic

```cmd
ros2 topic list -t
```

### 查看节点

```cmd
ros2 node list
```

### 查看 Ranger 节点信息

```cmd
ros2 node info /ranger_base_node
```

### 查看 `/cmd_vel`

```cmd
ros2 topic info /cmd_vel -v
```

### 查看 `/odom`

```cmd
ros2 topic echo /odom --once
```

---

## 9. 手动测试小车能否通过 `/cmd_vel` 控制

注意：测试前确保小车周围安全，速度要小。

前进：

```cmd
ros2 topic pub /cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.2}, angular: {z: 0.0}}" -r 5
```

停止：

```cmd
ros2 topic pub /cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.0}, angular: {z: 0.0}}" --once
```

左转：

```cmd
ros2 topic pub /cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.0}, angular: {z: 0.3}}" -r 5
```

如果这些能控制小车，说明 Ranger 底盘接口可用。

---

## 10. 检查 TF

Co-NavGPT2 需要：

```text
camera_init_1 -> body_1
```

检查：

```cmd
ros2 run tf2_ros tf2_echo camera_init_1 body_1
```

Ranger 默认更可能是：

```text
odom -> base_link
```

检查：

```cmd
ros2 run tf2_ros tf2_echo odom base_link
```

如果：

```text
camera_init_1 -> body_1 不存在
odom -> base_link 存在
```

那说明需要 TF 适配。

一种默认理解：

```text
camera_init_1 对应 odom
body_1 对应 base_link
```

后续可以通过以下方式解决：

1. 改 Co-NavGPT2 代码里查的 frame 名。
2. 写 TF bridge。
3. 发布静态/动态 transform 让 frame 连起来。

---

## 11. 检查相机 topic

Co-NavGPT2 需要：

```text
/robot1/camera/color/image_raw
/robot1/camera/aligned_depth_to_color/image_raw
/robot1/camera/color/camera_info
```

启动相机后查：

```cmd
ros2 topic list -t
```

如果实际是：

```text
/camera/color/image_raw
/camera/aligned_depth_to_color/image_raw
/camera/color/camera_info
```

而不是 `/robot1/camera/...`，就需要 remap 或 namespace。

检查 CameraInfo：

```cmd
ros2 topic echo /robot1/camera/color/camera_info --once
```

检查图像频率：

```cmd
ros2 topic hz /robot1/camera/color/image_raw
ros2 topic hz /robot1/camera/aligned_depth_to_color/image_raw
```

---

## 12. 最可能需要写的接口

### 12.1 动作 adapter

因为：

```text
Ranger 接收 /cmd_vel
Co-NavGPT2 当前不是明确直接发 /cmd_vel
```

所以小车侧大概率需要写：

```text
Co-NavGPT2 action / robot_action / ZMQ 控制意图
        ↓
adapter
        ↓
/cmd_vel geometry_msgs/msg/Twist
        ↓
Ranger Mini 3.0
```

默认动作映射可以是：

```text
前进: linear.x = 0.3, angular.z = 0.0
左转: linear.x = 0.0, angular.z = 0.5
右转: linear.x = 0.0, angular.z = -0.5
停止: linear.x = 0.0, angular.z = 0.0
```

### 12.2 TF 适配

如果 Co-NavGPT2 查：

```text
camera_init_1 -> body_1
```

但 Ranger 提供：

```text
odom -> base_link
```

就要适配 frame 名。

### 12.3 相机 topic remap

如果实际相机 topic 没有 `/robot1` namespace，则要 remap 到 Co-NavGPT2 期望的名字。

---

## 13. 目前的结论

现在不要急着写代码。

下一步最重要的是：

1. 解决 `ranger_bringup not found`。
2. 成功启动 Ranger 底盘节点。
3. 确认 `/cmd_vel` 能手动控制小车。
4. 确认 `/odom` 和 TF 是否存在。
5. 启动相机并确认 Co-NavGPT2 需要的三个相机 topic 是否存在。
6. 最后再决定 adapter 怎么写。

目前最小正确方向：

```text
用 ranger_ros2 保持小车底盘原样运行。
写或配置 adapter，把 Co-NavGPT2 的动作输出接到 Ranger 的 /cmd_vel。
对齐相机 topic 和 TF frame。
```
```