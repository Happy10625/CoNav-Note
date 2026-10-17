# Ranger-VLM_Nav迁移清单

目标：在新电脑 Ubuntu 22.04 上恢复 Ranger + Livox MID-360 + RealSense L515 + FAST_LIO2 + 二维建图 + Nav2 + VLM_Nav 的实车链路，不迁移 CoNav。

依据：提供的《使用日志.md》及 https://github.com/Happy10625/VLM_Nav0.git 。仓库检查日期：2026-10-06；检查提交：`b01a7645a1b09afd6e0cbacdbb4b1bab5e832c2e`。已检查 README、package.xml、CMakeLists.txt、requirements.txt、launch、硬件启动脚本及配置。清单属于静态检查结果，尚未在新电脑安装或实机验证。

## 一、仓库检查后的补充与修正

- [ ] VLM_Nav 已包含 `vlm_nav/fastlio_odom_adapter.py`、二维建图及 Nav2 启动文件，不需要迁移 `co_nav2_nav`。
- [ ] 当前包是 **ament_cmake + ament_cmake_python 的 C++/Python 混合包**，不是仅通过 pip 或 setup.py 安装的 Python 项目。必须使用 colcon 构建 C++ 点云过滤节点。
- [ ] PCL、pcl_ros、pcl_conversions、diagnostic_updater 等是明确的编译依赖，不能遗漏。
- [ ] 当前过滤输出是 `/vlm_nav/obstacle_cloud`，同时提供给 Nav2 和 pointcloud_to_laserscan；不是旧实验日志中的 `/vlm_nav/filtered_obstacle_cloud`。
- [ ] 当前过滤链为 TF → PCL PassThrough → negative CropBox → VoxelGrid；无需迁移早期 A1–A5 实验启动方式、ROR、RANSAC 或 Patchwork++。
- [ ] 仓库未直接依赖 `pyrealsense2`、`cv_bridge`、`image_transport` 或 `tf2_geometry_msgs`；不把它们列为本项目必装项。外部驱动需要的传递依赖另由 rosdep 处理。
- [ ] `scripts/common.sh` 写死了旧电脑 `/home/isee-cdh/...` 的五个环境路径，必须按新电脑用户名及构建位置修改；仓库名 VLM_Nav0 与脚本预期目录 VLM_Nav 也需要统一。
- [ ] 仓库配置比使用日志更新，参数以选定运行版本为准。例如当前 `vlm_sample_rate=2.0`，不能照搬旧日志的 0.2Hz 或 README 概述中的 5Hz。

## 二、系统及开发基础

- [ ] Ubuntu 22.04，确认网卡、USB、显示和 USB-CAN 可用。
- [ ] ROS 2 Humble：建议安装 `ros-humble-desktop`，提供基础 ROS、RViz 等。
- [ ] Git、build-essential、CMake。
- [ ] `python3-colcon-common-extensions`、`python3-rosdep`。
- [ ] Python 3.10、pip；如采用虚拟环境，需让该环境能访问 Humble 的 Python 包，并使用系统兼容的 Python 版本。
- [ ] `gnome-terminal`：项目一键启动脚本直接调用它；不用图形终端时可分别运行硬件脚本。
- [ ] `iproute2`：配置 CAN 和检查网卡。
- [ ] 检查旧电脑 ROS_DOMAIN_ID、RMW_IMPLEMENTATION、DDS 配置及 source 顺序；只迁移实际使用的设置。

## 三、Ranger 底盘驱动与通信

- [ ] Linux SocketCAN 和旧 USB-CAN 所用的 `gs_usb` 内核模块。通常由内核提供，不需另外下载驱动源码；若更换适配器，重新确认驱动型号。
- [ ] `can-utils`，用于 candump 等验收。
- [ ] `ugv_sdk`：https://github.com/agilexrobotics/ugv_sdk.git 。迁移旧电脑已验证的源码提交及本地修改，重新编译。
- [ ] `ranger_ros2`：https://github.com/agilexrobotics/ranger_ros2.git 。同样保留已验证版本及本地修改。
- [ ] CAN 启动脚本、必要的设备权限/udev 配置；接口 `can0`，波特率 500000 bit/s。
- [ ] 当前项目使用 `ranger_mini_v3.launch.py`，参数 `port_name:=can0 publish_odom_tf:=false`。旧日志对底盘车型有疑问，保持原来可用配置并确认实车型号。
- [ ] 可选调试包 `ros-humble-teleop-twist-keyboard`，用于独立底盘低速测试。

验收：can0 为 UP，candump 可接收数据，Ranger 驱动节点正常；底盘不重复发布 odom→base_link。

## 四、Livox MID-360 雷达

- [ ] Livox-SDK2：迁移旧电脑 `~/ws/Livox-SDK2` 的版本并安装 SDK 库。
- [ ] `livox_ros_driver2`：迁移旧电脑 `~/ros2_ws/src/livox_ros_driver2` 的 Humble 可用版本。
- [ ] `MID360_config.json`、相关 launch 及 SDK 测试配置。
- [ ] 重新设置新电脑有线网卡静态 IP。旧配置电脑为 192.168.1.50/24，雷达为 192.168.1.122；网卡名不一定仍是 enp5s0。
- [ ] 配置中的 `host_net_info` 与新电脑实际 IP 一致；保留雷达 IP，除非实际设备配置已改变。
- [ ] 启动 `msg_MID360_launch.py`，保持 Livox CustomMsg 模式，不能未经适配改成普通 PointCloud2 输入 FAST_LIO。

验收：`/livox/lidar` 为 `livox_ros_driver2/msg/CustomMsg`，约 10Hz；`/livox/imu` 为 sensor_msgs/msg/Imu，约 200Hz。MID-360 内置 IMU 由该驱动提供，不需另装独立 IMU 驱动。

## 五、RealSense L515 相机

- [ ] **librealsense 2.51.1**：使用日志中已经能识别 L515 的版本作为复现基线。
- [ ] **realsense-ros tag 4.51.1**：迁移旧电脑源码及针对 2.51.1 的 CMake/头文件路径修正，重新编译。不能只克隆原版 tag 而漏掉修正。
- [ ] L515 的 USB 权限规则及 SDK 实际使用的后端/内核配置；不要未经确认改变相机固件。
- [ ] 与 SDK 配套的 realsense-viewer，独立检查设备、RGB 和深度。
- [ ] 确认 wrapper 编译头文件、链接库和运行库都为 2.51.1，避免 `/opt/ros/humble` 与 `/usr/local` 混装覆盖。日志已记录新旧库混用造成 undefined symbol。
- [ ] 保留 `config/realsense.yaml`：RGB 和深度 `global_time_enabled=true`。
- [ ] 保留 `scripts/01_camera.sh`：开启深度对齐及同步，RGB profile 1280x720x30、原始深度 profile 640x480x30。应验收**对齐后的深度**与 RGB 同尺寸，而非要求原始 depth profile 相同。
- [ ] 话题为 `/camera/color/image_raw`、`/camera/aligned_depth_to_color/image_raw`、`/camera/color/camera_info`；光学坐标系为 camera_color_optical_frame。
- [ ] pyrealsense2 仅为直接 SDK 检查脚本可选安装，VLM_Nav 本体通过 ROS 话题取图，不需要它。

验收：wrapper 报告 Built/Running with LibRealSense v2.51.1；RGB-D 配对、尺寸和 CameraInfo 正确；持续运行检查延迟与图像时刻 TF。旧日志中的时间戳异常尚不能视为已彻底解决。

## 六、FAST_LIO2 定位

- [ ] **Ericsii/FAST_LIO_ROS2**：迁移旧电脑 `~/ws/FAST_LIO_ROS2` 的完整源码、提交和子模块；不要换成其他 FAST-LIO 移植版。
- [ ] FAST_LIO 的编译依赖，包括对应实现需要的 PCL、Eigen 等；以其 package.xml/CMake 和原环境为准。
- [ ] 迁移修改后的 `config/mid360.yaml`，包括输入话题、雷达/IMU 外参、点云发布、保存等设置。
- [ ] 确认 `/cloud_registered_body` 必须发布，项目过滤器依赖它；历史配置提到 `map_en` 调整，应核对旧实机最终文件，不直接套用某一天的片段。
- [ ] 当前启动为 `ros2 launch fast_lio mapping.launch.py config_file:=mid360.yaml rviz:=false`。
- [ ] 重新构建并修改 common.sh 对应的 FAST_LIO 环境路径；旧路径为 `~/ws/install_fastlio/setup.bash`。

验收：/Odometry、/cloud_registered_body 及 camera_init→body 正常更新，频率和延迟稳定。

## 七、VLM_Nav 的 ROS 与 PCL 依赖

以下根据仓库 package.xml、CMakeLists.txt 和 import 核对；多数由 ROS desktop、Nav2 或 rosdep 传递安装，不要求逐个手动操作。

- [ ] 构建：ament_cmake、ament_cmake_python。
- [ ] C++/运行：rclcpp、rclpy、rmw、rcl_interfaces。
- [ ] 诊断与同步：diagnostic_msgs、diagnostic_updater、message_filters。
- [ ] 点云：pcl_ros、pcl_conversions、PCL 开发库；Ubuntu 中通常为 `libpcl-dev`。package.xml 的 `libpcl-all-dev` 是 rosdep 依赖键，不能直接当作 apt 包名。
- [ ] TF：tf2、tf2_ros。
- [ ] 消息：sensor_msgs、sensor_msgs_py、geometry_msgs、nav_msgs、nav2_msgs、std_msgs、action_msgs、visualization_msgs。
- [ ] 启动：launch、launch_ros、ament_index_python。
- [ ] NumPy、OpenCV、PyYAML，仓库声明的系统包为 python3-numpy、python3-opencv、python3-yaml。
- [ ] OpenAI Python SDK：requirements.txt 声明 `openai>=1.40`；优先记录并复现旧电脑实测版本。
- [ ] httpx：vlm_client.py 直接 import；通常由 openai 传递安装，但必须确认可导入。
- [ ] 测试依赖：ament_cmake_gtest、ament_cmake_pytest、python3-pytest。当前 CMake 在 BUILD_TESTING 开启时需要这些包。

VLM_Nav 的依赖可在 source Humble 后通过 rosdep 按 package.xml 解析安装；外部硬件源码仍须另行准备，requirements.txt 不能代替完整 ROS/PCL 依赖安装。

## 八、二维建图、Nav2 和可视化

- [ ] `ros-humble-pointcloud-to-laserscan`：当前输入 `/vlm_nav/obstacle_cloud`，输出 `/scan`。
- [ ] `ros-humble-slam-toolbox`：在线二维建图，发布 /map 与 map→odom；迁移 config/slam_toolbox.yaml。
- [ ] `ros-humble-navigation2`、`ros-humble-nav2-bringup`：保留 Humble 的导航组件，包括规划器、控制器、行为服务器、BT navigator、costmap、生命周期及速度平滑等组件。
- [ ] 迁移 config/nav2_overrides.yaml、nav2_easy_case.yaml 及 behavior_trees/easy_case_no_recovery.xml。
- [ ] RViz2 及 config/vlm_nav.rviz。
- [ ] 可选验收工具 tf2_tools、rosbag2；ros2 bag 用于重复验证定位与过滤链。

当前在线建图链不单独启动 AMCL 或离线 map_server；不把它们作为额外运行步骤。Nav2 安装时附带相关包不影响使用。

## 九、需要迁移的项目代码与配置

- [ ] 整个 VLM_Nav 仓库，而非仅 vlm_navigator.py。
- [ ] Python 模块 `vlm_nav/`：导航状态机、VLM 客户端、geometry、exploration、models、latest_frame_worker、arm_image_recorder、fastlio_odom_adapter。
- [ ] C++ `src/` 与 `include/`：obstacle_cloud_filter 和过滤 pipeline。
- [ ] `launch/`：system、mapping、navigation、vlm_navigation、easy_case。
- [ ] `config/`、`behavior_trees/`、全部 scripts、resource、package.xml、CMakeLists.txt、requirements.txt、测试文件和构建说明。
- [ ] 旧电脑尚未提交到 Git 的修改；仓库版本不一定等于最后成功实验的版本，迁移前比较 git status 和 diff。
- [ ] 修改 common.sh 中的五个 setup.bash 路径；统一克隆目录与构建输出目录。
- [ ] 使用 colcon 重建。不要复制旧 build/install/log 当作新电脑可运行环境，也不要直接复制旧 .venv。
- [ ] 定位适配器使用 `/Odometry` 输入、`/fastlio/odom` 输出，并唯一发布 odom→base_link；由项目发布 odom→camera_init 单位静态 TF。
- [ ] robot.yaml 中 base_to_body_xyz/rpy 和 launch/vlm_navigation.launch.py 中硬编码的相机安装 TF 必须迁移并复核；传感器未移动可复用，经拆装则重新标定。
- [ ] 当前仓库的高度过滤、CropBox、VoxelGrid 参数仍标有实机校准 TODO，不应将“文件已复制”等同于“参数已经验证”。

## 十、数据、API 与环境设置

- [ ] 云端 VLM 账号配置：DASHSCOPE_API_KEY、DASHSCOPE_WORKSPACE_ID 或 DASHSCOPE_BASE_URL、DASHSCOPE_MODEL；按当前客户端支持的变量设置，不把密钥写入源码或清单。
- [ ] 若使用 OpenAI 兼容备用配置，迁移实际使用的 OPENAI 环境变量设置；以 vlm_client.py 的优先级为准。
- [ ] 重新确认网络及 HTTP_PROXY/HTTPS_PROXY。旧电脑 127.0.0.1:7897 只是当地代理端口，不能默认新电脑同样存在；启动器会清除 ALL_PROXY/all_proxy。
- [ ] 可选归档旧地图及 YAML、bag、filter_results、ARM 图片记录。它们是实验资料，不是驱动依赖。
- [ ] 首次障碍链验收按当前 README 从新 SLAM 会话开始，不加载旧噪声地图。若后续要使用旧地图，需要另行验证定位启动方式与坐标一致性。
- [ ] 保存旧电脑外部仓库 commit、diff、软件包及 Python 版本清单，特别是 RealSense 本地修正。

## 十一、不需要迁移的内容

- [ ] 不迁移 CoNav / Co-NavGPT2 / co_nav2_nav 主程序、旧虚拟环境及 ZMQ→cmd_vel 适配器。
- [ ] 不安装 Habitat-Lab、Habitat-Sim、HM3D、ObjectNav episodes 或 CoNav 仿真依赖。
- [ ] 不因使用云端 VLM 而额外安装本地模型、CUDA、PyTorch 或模型权重；现仓库未显示这类必需依赖。桌面显卡驱动按新电脑实际需要安装。
- [ ] 不额外安装 YOLO/Ultralytics 等旧识别栈，当前项目使用云端 VLM。
- [ ] 不安装独立相机 IMU 驱动或独立雷达 IMU 驱动来替代 MID-360 的 /livox/imu。

## 十二、迁移后验收顺序

1. ROS Humble 环境及全部外部工作空间可被找到。
2. Ranger CAN 通信与低速遥控正常，底盘 odom TF 已关闭。
3. Livox CustomMsg/IMU 数据正常；FAST_LIO 定位和 body 点云正常。
4. 相机 RGB、对齐深度、CameraInfo 和长时间时间戳正常。
5. fastlio_odom_adapter、相机安装 TF 连通；base_link↔body 是稳定刚体关系，没有重复 TF 发布者。
6. obstacle_cloud_filter 输出 /vlm_nav/obstacle_cloud；诊断、QoS、障碍高度和车体剔除合理。
7. /scan、/map、map→odom 正常，从新地图会话验收。
8. 保持 VLM_Nav enabled=false，进行 Nav2 手动选点、取消和停车测试。
9. 用项目脚本检查 API、系统状态，再 ARM 启用 VLM_Nav，完成目标导航。
10. 运行仓库提供的无硬件测试及 colcon 测试；实机验收另外记录结果。

最终链路：MID-360 → livox_ros_driver2 → FAST_LIO_ROS2 → VLM_Nav 定位适配与 PCL 过滤 → pointcloud_to_laserscan / SLAM Toolbox / Nav2；L515 → librealsense + realsense-ros → RGB-D + 图像时刻 TF → VLM_Nav 云端决策 → Nav2 → Ranger。
