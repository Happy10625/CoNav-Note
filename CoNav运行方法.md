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
ros2 topic echo --once /camera/aligned_depth_to_color/image_raw | grep -E"frame_id|height|width|encoding"
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

**命令**：

```
source /opt/ros/humble/setup.bash
source ~/agilex_ws/install/setup.bash

python3 ~/zmq_to_cmd_vel_adapter.py
```

正常输出：

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

命令：

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

