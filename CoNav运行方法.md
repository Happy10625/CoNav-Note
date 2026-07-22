# 需要开的终端

每次新开终端，要先执行：

source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash

## 1.相机  

```cd ~/rs515/ros2_ws
cd ~/rs515/ros2_ws
source install/setup.bash
ros2 launch realsense2_camera rs_launch.py align_depth.enable:=true
```

显示error:resource temporarily unavailable是正常的

ros2 launch realsense2_camera rs_launch.py \
  align_depth.enable:=true \
  rgb_camera.profile:=640x480x30 \
  depth_module.profile:=640x480x30

### (1)每次启动前先确认没有旧相机节点

启动相机前可以查：

```
ros2 node list | grep camera
```

如果你要重启相机，先在原相机 launch 终端 `Ctrl+C`，再确认：

```
ros2 node list | grep camera
```

没有 `/camera/camera` 后再重新启动。

### (2)每次跑 Co-NavGPT2 前做“三项检查”

不要只看 topic 名，要看尺寸。

```
ros2 topic echo --once /camera/color/image_raw | grep -E "frame_id|height|width|encoding"
ros2 topic echo --once /camera/aligned_depth_to_color/image_raw | grep -E "frame_id|height|width|encoding"
ros2 topic info /camera/aligned_depth_to_color/image_raw -v
```

期望：

```
Publisher count: 1
RGB 和 aligned depth 尺寸一致
aligned depth 的 frame_id 是 camera_color_optical_frame
```

### (3)跑 20 帧稳定性检查

建议以后每次正式跑前都做：

```
for i in {1..20}; do
  echo "---- frame $i ----"
  ros2 topic echo --once /camera/aligned_depth_to_color/image_raw | grep -E "frame_id|height|width|encoding"
done
```

如果 20 次都一致，再跑 Co-NavGPT2。

# 2.启动 Ranger 底盘

### 启动 Ranger 前先检查

每次开小车前先执行：

```
ip -details -statistics link show can0
```

如果看到：

```
state DOWN
can state STOPPED
```

就执行：

```
sudo ip link set can0 up type can bitrate 500000
```

如果看到：

```
state UP
can state ERROR-ACTIVE
```

### 启动 Ranger Mini 3.0 底盘 ROS2 节点，发布 `/odom`，监听 `/cmd_vel`。

```
source /opt/ros/humble/setup.bash
source ~/agilex_ws/install/setup.bash

ros2 launch ranger_bringup ranger_mini_v3.launch.py publish_odom_tf:=true
```

这个终端保持运行。

正常时会看到类似：

```
Start listening to port: can0
```

不要出现：

```
Failed to send CAN frame
```

如果出现这个，优先查 CAN 线、急停、遥控/控制模式、`can0` 状态。

### 检查底盘状态

作用：确认 `/odom`、TF、CAN 状态正常。

```
source /opt/ros/humble/setup.bash
source ~/agilex_ws/install/setup.bash
```

检查 `/odom`：

```
ros2 topic hz /odom
```

正常应约：

```
average rate: 50
```

检查 TF：

```
ros2 run tf2_ros tf2_echo odom base_link
```

正常会持续输出 Translation / Rotation。

检查 CAN：

```
ip -details -statistics link show can0
```

当前状态应为：

```
can state ERROR-ACTIVE
```



如果是：

```
ERROR-WARNING
ERROR-PASSIVE
BUS-OFF
```

先不要跑 Co-NavGPT2，先重置 CAN：

```
sudo ip link set can0 down
sudo ip link set can0 up type can bitrate 500000
```

再查：

```
ip -details -statistics link show can0
```



# 3.启动 ZMQ → `/cmd_vel` adapter

作用：接收 Co-NavGPT2 发出的：`speedctl speed|vx|vy|yaw`

并转换成 Ranger 的：`/cmd_vel geometry_msgs/msg/Twist`



## adpter工作模式

### 1. 默认是 `dry_run` 安全模式

直接运行：

```
source /opt/ros/humble/setup.bash
source ~/agilex_ws/install/setup.bash
python3 zmq_to_cmd_vel_adapter_safe.py
```

默认 **不会发布 `/cmd_vel`**。

它只会：

```
接收 ZMQ speedctl
解析 vx / vy / yaw
打印原始速度
打印限幅后的速度
不让小车动
```

这个模式适合调试 Co-Nav2：

```
Co-Nav2 可以正常启动
adapter 能看到它想发什么速度
但 Ranger 不会动
```

### 2. 真车运行模式 `real_run`

确认输出合理后，再运行：

```
python3 zmq_to_cmd_vel_adapter_safe.py --real-run
python3 zmq_to_cmd_vel_adapter_safe.py --real-run --max-linear-x 0.05 --max-angular-z 0.15 --command-timeout 5.0
```

这个模式才会真正发布 `/cmd_vel`，小车会动。

默认速度限制是：

```
linear.x  最大 ±0.08 m/s
angular.z 最大 ±0.25 rad/s
linear.y  固定为 0
```

也就是原来的：

```
linear.x ±0.2
angular.z ±0.4
```

更保守。

### 3. 自动停车 watchdog

我加了超时保护：

```
如果 real_run 模式下 0.5 秒没有收到新的 speedctl，
adapter 会自动发布一次 0 速度 /cmd_vel。
```

也可以改：

```
python3 zmq_to_cmd_vel_adapter_safe.py --real-run --command-timeout 0.3
```

这能避免 Co-Nav2 或 ZMQ 中断后，小车保持上一次速度继续动。

------

### 4. 关闭 adapter 时会发 0 速度

在 `real_run` 模式下，如果你 Ctrl+C 关闭 adapter，它会尝试发布一次：

```
linear.x = 0
angular.z = 0
```

让小车停下。



### 正常输出：

```
Adapter started: ZMQ speedctl -> /cmd_vel
Listening on tcp://127.0.0.1:5557
```

这个终端保持运行。

后面如果 Co-NavGPT2 发动作，会看到：

```
raw: speedctl speed|...
published /cmd_vel: linear.x=..., angular.z=...
```



# 4.运行 Co-NavGPT2

作用：运行修改过的 `ros_single_nav.py`。

这里要进入 `.venv`，因为你昨天确认 `.venv` 里有：

```
torch GPU
open3d
rclpy
message_filters
tf_transformations
pyzmq
```

**命令**：

```
cd ~/ws/Co-NavGPT2

source /opt/ros/humble/setup.bash
source ~/agilex_ws/install/setup.bash
source ~/rs515/ros2_ws/install/setup.bash
source .venv/bin/activate

python3 ros_single_nav.py --visualize 1 --num_agents 1 --frame_width 1280 --frame_height 720
//python ros_single_nav.py
```

正常现象：

```
socket connected(?) to port 5557
FspNode init done.
received tf
Action published: ...
```

adapter 终端应看到：

```
raw: speedctl speed|...
published /cmd_vel: ...
```

Ranger 终端不要出现：

```
Failed to send CAN frame
```

**CoNav2适配器**的开启命令为

```
cd /home/isee-cdh/ws/Co-NavGPT2
source /opt/ros/humble/setup.bash
source install_ros2/setup.bash

ros2 launch co_nav2_nav semantic_exploration.launch.py \
  enable_odom_adapter:=true \
  publish_camera_tf:=true \
  publish_lidar_tf:=false \
  publish_map_odom:=false \
  enable_perception:=false
```



## 五.启动 Livox MID-360

```
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch livox_ros_driver2 msg_MID360_launch.py
```

确认雷达数据正常：

```
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 topic hz /livox/lidar
ros2 topic hz /livox/imu
```

正常应该大概是：

```
/livox/lidar   约 10 Hz
/livox/imu     约 200 Hz
```

## 六.启动 FAST-LIO2

```
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch fast_lio mapping.launch.py config_file:=mid360.yaml rviz:=false
```

其中`rviz:=false`不开rviz

如果启动正常，你应该能看到类似：

```
IMU Initial Done
Node init finished
```

偶尔出现一次：

```
No point, skip this scan!
```

不一定是问题，只要后面有 `/Odometry` 输出即可

## 检查 FAST-LIO2 输出

```
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 topic list | grep -E "Odometry|cloud|path|tf"
```

重点看有没有：

```
/Odometry
/cloud_registered
/cloud_registered_body
/path
/tf
```

再检查频率：

```
ros2 topic hz /Odometry
ros2 topic hz /cloud_registered
ros2 topic hz /path
```

正常大概是：

```
/Odometry             约 10 Hz
/cloud_registered     约 10 Hz
/path                 约 1 Hz
```

当前基础导航链已经成功运行：

```
Livox → FAST_LIO → odom/base_link
                     ↓
cloud_registered_body → /scan → SLAM Toolbox
                                      ↓
                              /map + map→odom
                                      ↓
                                    Nav2
```

**形成如下TF树的启动顺序**是 Livox 驱动 --> FAST_LIO --> Co-Nav2 适配器

```
odom
├── camera_init → body
└── base_link
    └── camera_link → camera_color_optical_frame
```
