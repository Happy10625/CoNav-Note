# go2使用指南

## 关于上位机等原始配置

上位机 Python `3.8.10`、架构 `aarch64`，安装目录 `/opt/ros` 中有 `foxy`、`noetic`，选择foxy

可配置无需密钥的远程连接，之后可以'ssh unitree-go'的命令连接上位机，十分方便。

Go2 上位机里已经有现成的 XT16 驱动和相机驱动。

拔出电池查看里面会有本机SN码显示。



## 关于开机启动

+ go的电池方向是开机键在上，放入电池要用“寸劲”——来自亮神的指导
+ 启动前要摆正go的姿势，使得四足和关节贴地，之后再开机.开机最好有人看着，避免go没站稳摔倒
+ go2续航一般，还未请旭航指导。站立或走动时比较耗电，所以没事的时候就要让go趴着。同时准备或实验过程中不要让go长时间站立，会因为发热而摔倒，要时不时让它走动或者趴下;



## 关于雷达和IMU

狗嘴上的雷达是宇树自研雷达，狗背上的是HesaiXT16雷达。

已验证 XT16 雷达点云+狗体的IMU /utlidar/imu + SPARK FAST-LIO配置可用。

####  查看狗嘴上的雷达IMU /utlidar/imu：

查看狗嘴上雷达的imu输出，在**ssh连接**的终端输入

```bash
ros2 topic info -v /utlidar/imu
ros2 topic hz /utlidar/imu
```

或者在**没有进行ssh连接**的终端放下面的命令来查看

```bash
source /opt/ros/humble/setup.bash
source ~/unitree_ros2/go2_ws/install/setup.bash
export GO2_NET_IFACE=enp4s0
source ~/unitree_ros2/VLM_Nav/scripts/go2_network_env.sh
# 用下面这个来检测
timeout 10 ros2 topic hz /utlidar/imu
```

可以观察到/utlidar/imu的频率输出平均250Hz



####  开启狗背上雷达的驱动并检查：

而狗背上的雷达**启动驱动**：在**没有ssh连接**的终端输入并放置它一直输出

```bash
# 下面的是启动和检测都要用的命令
source /opt/ros/humble/setup.bash
source /home/isee-pst/Documents/liang/hesai_xt16_ws/install/setup.bash
source ~/unitree_ros2/go2_ws/install/setup.bash
export GO2_NET_IFACE=enp4s0
source ~/unitree_ros2/VLM_Nav/scripts/go2_network_env.sh
export ROS_LOG_DIR=/tmp/hesai_roslog

# 启动驱动
ros2 run hesai_ros_driver hesai_ros_driver_node \
--ros-args \
-p config_path:=/home/isee-pst/Documents/liang/hesai_xt16_ws/src/HesaiLidar_ROS_2.0/config/config.yaml

# 检查发布数
ros2 topic info --no-daemon -v /lidar_points
# 预期发布数为1
# 据说ros2 topic hz 不输出的原因是：ROS 2 Humble 的 topic hz 固定使用 sensor_data QoS，而 Hesai publisher 使用：
# RELIABLE + VOLATILE
# 在当前 CycloneDDS 环境下，hz 没有成功接收这种大尺寸 PointCloud2。
```



#### 查看机器狗机体的IMU

```bash
source /opt/ros/humble/setup.bash
source /home/isee-pst/unitree_ros2/go2_ws/install/setup.bash
source /home/isee-pst/unitree_ros2/VLM_Nav/scripts/go2_network_env.sh

# 看 /lowstate 是否存在
ros2 topic list | grep lowstate

# 看消息类型
ros2 topic type /lowstate

# 看 publisher、QoS 等
ros2 topic info /lowstate -v

# 看频率（观测到平均500Hz）
ros2 topic hz /lowstate

# 完整消息查看
ros2 topic echo /lowstate
```

输出类型：sensor_msgs/msg/Imu

Frame：body_imu

输出 QoS：RELIABLE / VOLATILE / depth 50

验证结果：

```txt
  /body_imu ≈497–500 Hz
  publisher count=1
```



+ 提供一个录点云包的方法，会保存到`~/unitree_ros2/log`,

  ```bash
  sudo timeout --signal=INT 30s tcpdump -i enp4s0 -s 0 -B 4096 \
      -w ~/unitree_ros2/log/hesai_$(date +%Y%m%d_%H%M%S).pcap \
      'udp port 2368'
  ```

  这个包用禾塞的pandarview查看。此电脑是ubuntu22.04，~~没有支持它的版本~~。现在有了

  查看使用pandarview2,命令：

  ```bash
  cd ~/unitree_ros2/PandarView2
  ./PandarView.sh
  ```

  btw'运行.bin文件的方法就是与脚本类似，以及可以`chmod +x`加可执行权限。

## 关于相机

+ 相机工作不稳定，尤其在刚启动的时候会刷新很多错误信息，之后稳定就行。（此处应有正常情况下的显示）。如果突然状态异常，把相机那端的连接线拔掉重插（插稳）即可。

+ 使用nomachine：

  ```bash
  # 在这个电脑上
  ssh unitree-go
  
  # 连上机器狗以后在里面
  sh nomachine.sh
  ```
  
  然后打开nomachine就能看到连上了。在里面可以看realsense-viewer.realsense-viewer 只是直接读取 USB 画面，不会发布 ROS 2 图像

+ 启动 ROS 相机驱动：

```
  ssh unitree-go

  source /opt/ros/foxy/setup.bash
  source ~/ros2_ws/install/setup.bash
  export ROS_DOMAIN_ID=0
  export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  export ROS_LOG_DIR=/tmp/realsense_roslog
  mkdir -p "$ROS_LOG_DIR"

  ros2 launch realsense2_camera rs_launch.py \
    depth_module.depth_profile:=640x480x15 \
    rgb_camera.color_profile:=640x480x15 \
    enable_sync:=true \
    align_depth.enable:=true
```

  保持这个终端运行。正常情况下频率约15hz.

+ 如果出现丢包，检查是否开启了检查节点。如果开了太多检查节点，会导致depth与rgb丢包，关掉就好了。



## 关于笔记本与上位机的时钟对齐

