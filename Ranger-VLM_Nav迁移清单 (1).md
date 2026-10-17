# Ranger-VLM_Nav迁移清单

目标：在新 Ubuntu 22.04 上恢复 Ranger、MID-360、RealSense L515、FAST_LIO2、二维建图、Nav2 和 VLM_Nav，不迁移 CoNav。

依据：《使用日志.md》及 https://github.com/Happy10625/VLM_Nav0.git ，检查提交 `b01a7645a1b09afd6e0cbacdbb4b1bab5e832c2e`，日期 2026-10-06。以下命令为迁移操作说明，未在你的新电脑上实际执行。旧电脑的未提交修改和外部驱动版本应优先保留。

## 执行约定

- 按章节顺序执行。每个代码块含同一组件的查找、安装及验收命令；代码块不是“一次全部粘贴”的脚本。
- `【旧电脑】`、`【新电脑】`、`【终端 A】` 等在注释中标记执行位置。启动驱动的命令会占用终端，验收命令在另一个终端执行。
- `timeout 10 ...` 的监测命令结束时可能返回 124，仅表示达到观察时限；应查看期间有没有数据。
- 软件安装与编译失败后先解决错误，不继续下一步骤。
- 新电脑统一目录：`~/agilex_ws`、`~/ros2_ws`、`~/rs515/ros2_ws`、`~/ws/FAST_LIO_ROS2`、`~/ws/VLM_Nav`。不要复制旧 build/install/log 或旧虚拟环境。
- 下面的 SSH 复制以旧电脑可连接为前提；也可以把同样目录经移动硬盘复制到新电脑。只有旧电脑需要开启 SSH 服务。

## 1. 记录旧环境并准备传输

记录版本和修改，不复制 CoNav。旧外部驱动的具体提交无法从日志推断，需要在旧电脑查找。

```bash
# 【旧电脑】确认系统/ROS，保存版本清单
lsb_release -a
source /opt/ros/humble/setup.bash
echo "$ROS_DISTRO"
mkdir -p ~/migration_manifest
dpkg-query -W > ~/migration_manifest/dpkg-packages.txt
python3 -m pip freeze > ~/migration_manifest/python-packages.txt
uname -a > ~/migration_manifest/kernel.txt

# 查找驱动源码和配置，不搜索/输出 API 密钥
find ~/agilex_ws/src ~/ros2_ws/src ~/rs515 ~/ws/FAST_LIO_ROS2 \
  -name package.xml -o -name MID360_config.json -o -name mid360.yaml
find ~/realsenseai ~/rs515 -name CMakeCache.txt 2>/dev/null

# 各仓库执行下面三条；按实际目录替换
# git diff 文件只留本地，用于保留修正；勿把可能包含凭据的内容公开上传
cd ~/ws/FAST_LIO_ROS2
git rev-parse HEAD
git status --short
git submodule status --recursive
git diff > ~/migration_manifest/fastlio-local.patch

# 仅网络复制方式需要；旧电脑安装并启用 SSH
sudo apt update
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
hostname -I

# 【新电脑】每个执行复制操作的终端先设置；替换用户名、IP及旧用户目录
export OLD_HOST='isee-cdh@192.168.1.100'
export OLD_ROOT='/home/isee-cdh'
ssh "$OLD_HOST" 'hostname; lsb_release -ds'
```

验收：新电脑能 SSH 到旧电脑；确认路径和实际旧电脑版本。旧电脑不是 192.168.1.100 时必须修改，不能将雷达 IP 当作旧电脑 IP。

## 2. 新电脑 ROS Humble 与基础工具

仅用于已经安装完成的 Ubuntu 22.04。已经配置 ROS 软件源时，先检查现有源，不重复创建。

```bash
# 【新电脑】查找系统及已有 ROS 环境
. /etc/os-release
printf '%s %s\n' "$ID" "$VERSION_ID"
test "$ID" = ubuntu && test "$VERSION_ID" = 22.04
ls /opt/ros 2>/dev/null
locale

# 基础工具
sudo apt update
sudo apt install -y locales software-properties-common curl gnupg \
  git rsync ripgrep nano build-essential cmake pkg-config python3-pip python3-venv \
  gnome-terminal iproute2 usbutils pciutils
sudo locale-gen en_US.UTF-8
export LANG=en_US.UTF-8
sudo add-apt-repository universe

# 查找已有 ROS 软件源；已配置正常源则跳过下一段“添加源”命令
rg -n 'packages.ros.org|ros2' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null

# 仅在未配置 ROS 2 软件源时添加。密钥来自 ROS 官方仓库
sudo curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
  -o /usr/share/keyrings/ros-archive-keyring.gpg
ROS_ARCH="$(dpkg --print-architecture)"
printf 'deb [arch=%s signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu jammy main\n' \
  "$ROS_ARCH" | sudo tee /etc/apt/sources.list.d/ros2.list

# 安装；apt 若提示同一源 Signed-By 冲突，先处理重复源再继续
sudo apt update
sudo apt install -y ros-humble-desktop python3-colcon-common-extensions python3-rosdep
source /opt/ros/humble/setup.bash

# rosdep 未初始化时执行；已存在默认源则跳过 init
if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
  sudo rosdep init
fi
rosdep update

# 验收
echo "$ROS_DISTRO"
ros2 pkg prefix rclpy
ros2 pkg prefix rviz2
colcon --help
```

验收：ROS_DISTRO 为 humble，基础包可找到。ROS 安装参考：https://docs.ros.org/en/humble/Installation/Ubuntu-Install-Debians.html 。

## 3. Ranger：CAN、SDK、ROS 驱动

优先复制旧源码，因为底盘启动参数与实际车型已经联调过。旧日志使用 ranger_mini_v3，实车具体型号仍需核对。

```bash
# 【新电脑】查找 USB-CAN 与内核驱动
lsusb
ip -brief link
modinfo gs_usb

# 安装通信与调试工具
sudo apt install -y can-utils ros-humble-teleop-twist-keyboard
sudo modprobe gs_usb
lsmod | rg gs_usb

# 迁移源码（当前终端先设置第1节的 OLD_HOST、OLD_ROOT）
mkdir -p ~/agilex_ws/src
rsync -a --exclude=build --exclude=install --exclude=log \
  "$OLD_HOST:$OLD_ROOT/agilex_ws/src/" ~/agilex_ws/src/

# 查找包与旧提交
find ~/agilex_ws/src -name package.xml
# 找不到旧源码时的备用获取方式，不能与上述复制同时执行：
# git clone https://github.com/agilexrobotics/ugv_sdk.git ~/agilex_ws/src/ugv_sdk
# git clone https://github.com/agilexrobotics/ranger_ros2.git ~/agilex_ws/src/ranger_ros2
# 然后分别 checkout 第1节记录的已验证提交，并恢复本地修改

# 安装依赖并重建
source /opt/ros/humble/setup.bash
cd ~/agilex_ws
rosdep install --from-paths src --ignore-src --rosdistro humble -r -y
colcon build --symlink-install
source ~/agilex_ws/install/setup.bash
ros2 pkg prefix ranger_bringup

# 插好 USB-CAN 后查找 can0；若没有该接口，先排查设备/驱动
ip -details link show can0
# 以下仅在首次配置、未运行底盘节点时执行，之后不反复重配
sudo ip link set can0 down
sudo ip link set can0 up type can bitrate 500000
ip -details link show can0
timeout 5 candump can0

# 【终端 A】启动底盘；此命令持续运行
source /opt/ros/humble/setup.bash
source ~/agilex_ws/install/setup.bash
ros2 launch ranger_bringup ranger_mini_v3.launch.py \
  port_name:=can0 publish_odom_tf:=false

# 【终端 B】验收
source /opt/ros/humble/setup.bash
source ~/agilex_ws/install/setup.bash
ros2 node list
ros2 topic echo /odom --once
ros2 param get /ranger_base_node publish_odom_tf
# 若实际节点名不同，以 ros2 node list 为准；项目自动检查脚本使用此节点名

# 可选：确认场地可测试后低速键盘遥控，需按提示先降低速度
# ros2 run teleop_twist_keyboard teleop_twist_keyboard
```

验收：CAN 有数据、/odom 正常、publish_odom_tf 为 false。不用 ugv_sdk 演示程序做默认验收，它可能使轮子动作。

## 4. MID-360：Livox SDK2、ROS 驱动与网络

电脑旧 IP 为 192.168.1.50/24，雷达为 192.168.1.122。旧电脑若仍接在同一雷达网络，先断开或改地址，避免重复 IP。雷达链路通常不设置默认网关，保留其他接口负责互联网。

```bash
# 【新电脑】查找网卡和已有 SDK/驱动
ip -brief addr
nmcli device status
ldconfig -p | rg livox
find ~/ros2_ws/src -name package.xml 2>/dev/null

# 迁移 SDK 和雷达驱动；不要整包复制 ros2_ws/src，以免带入冲突相机库
mkdir -p ~/ws/Livox-SDK2 ~/ros2_ws/src/livox_ros_driver2
rsync -a --exclude=build --exclude=install --exclude=log \
  "$OLD_HOST:$OLD_ROOT/ws/Livox-SDK2/" ~/ws/Livox-SDK2/
rsync -a --exclude=build --exclude=install --exclude=log \
  "$OLD_HOST:$OLD_ROOT/ros2_ws/src/livox_ros_driver2/" ~/ros2_ws/src/livox_ros_driver2/

# 构建安装 SDK
cmake -S ~/ws/Livox-SDK2 -B ~/ws/Livox-SDK2/build
cmake --build ~/ws/Livox-SDK2/build -j2
sudo cmake --install ~/ws/Livox-SDK2/build
sudo ldconfig
ldconfig -p | rg livox

# 设置网卡：替换为 ip/nmcli 查到的真实接口名
export LIDAR_IF='enp5s0'
# 先检查连接是否已存在；不存在时新建。只用于 NetworkManager 管理的接口
nmcli connection show
# 若已有该名称，跳过 add，执行后面的 modify
sudo nmcli connection add type ethernet ifname "$LIDAR_IF" \
  con-name mid360 ipv4.method manual ipv4.addresses 192.168.1.50/24 \
  ipv4.never-default yes ipv6.method disabled
sudo nmcli connection modify mid360 ipv4.method manual \
  ipv4.addresses 192.168.1.50/24 ipv4.never-default yes
sudo nmcli connection up mid360
ip -brief addr show "$LIDAR_IF"
ping -c 3 192.168.1.122
# ping 无响应不能单独证明雷达故障，最终以驱动数据为准

# 找到并核对 host_net_info 与雷达 IP；若不一致，编辑该文件
rg -n '192\.168|host_net_info|lidar_ip' \
  ~/ros2_ws/src/livox_ros_driver2/config/MID360_config.json
nano ~/ros2_ws/src/livox_ros_driver2/config/MID360_config.json

# 编译：参数来自旧环境的实际成功命令
source /opt/ros/humble/setup.bash
cd ~/ros2_ws
rosdep install --from-paths src --ignore-src --rosdistro humble -r -y
colcon build --packages-select livox_ros_driver2 \
  --cmake-args -DROS_EDITION=ROS2 -DDISTRO_ROS=humble
source ~/ros2_ws/install/setup.bash
ros2 interface show livox_ros_driver2/msg/CustomMsg

# 【终端 A】持续启动
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch livox_ros_driver2 msg_MID360_launch.py

# 【终端 B】验收
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 topic type /livox/lidar
ros2 topic type /livox/imu
timeout 10 ros2 topic hz /livox/lidar
timeout 10 ros2 topic hz /livox/imu
```

验收：CustomMsg 点云约10Hz，IMU约200Hz。若新系统使用 systemd-networkd/netplan 而非 NetworkManager，改用现有管理方式设置同样静态地址，不执行 nmcli 新建连接。SDK 官方构建参考：https://github.com/Livox-SDK/Livox-SDK2 。

## 5. L515：librealsense 2.51.1 + 修正后的 wrapper 4.51.1

本节优先迁移已验证源码。日志并未记录 SDK 全部 CMake 开关，必须先检查旧构建缓存；不能凭日志唯一确定 USB 后端、内核补丁或 CUDA 配置。不要在新电脑直接 apt 安装最新 realsense2_camera 来替代旧修正版本。

```bash
# 【旧电脑】查找已验证 SDK 与 wrapper
find ~/realsenseai ~/rs515 -name CMakeCache.txt -o -name package.xml 2>/dev/null
# SDK 路径按日志为下列目录，若实际不同则替换
cd ~/realsenseai/librealsense
git describe --tags --always
git status --short
# 查找缓存中实际后端与安装选项；缓存位置按 find 结果调整
rg 'FORCE_RSUSB_BACKEND|BUILD_WITH_CUDA|BUILD_EXAMPLES|BUILD_GRAPHICAL_EXAMPLES|CMAKE_INSTALL_PREFIX' \
  build/CMakeCache.txt
# 在查到的 realsense-ros 仓库目录记录提交和本地修正
# git describe --tags --always
# git status --short
# git diff > ~/migration_manifest/realsense-wrapper-local.patch

# 【新电脑】先检查相机和已安装版本，避免混用
lsusb
ldconfig -p | rg realsense
dpkg-query -W '*realsense*' 2>/dev/null

# 迁移 SDK 和专用相机工作空间源码
mkdir -p ~/migration_src/librealsense ~/rs515/ros2_ws/src
rsync -a --exclude=build --exclude=install --exclude=log \
  "$OLD_HOST:$OLD_ROOT/realsenseai/librealsense/" ~/migration_src/librealsense/
rsync -a --exclude=build --exclude=install --exclude=log \
  "$OLD_HOST:$OLD_ROOT/rs515/ros2_ws/src/" ~/rs515/ros2_ws/src/

# 常用 SDK 构建依赖
sudo apt install -y libusb-1.0-0-dev libudev-dev libssl-dev \
  libglfw3-dev libgtk-3-dev libgl1-mesa-dev libglu1-mesa-dev

# 在当前终端设置旧缓存确认的后端，OFF/ON 以旧实测值为准
read -rp '输入旧缓存确认的FORCE_RSUSB_BACKEND值（ON或OFF）: ' RSUSB_BACKEND
# 只接受已经核对的值；未能确认则先停止，不猜测后端
case "$RSUSB_BACKEND" in ON|OFF) export RSUSB_BACKEND ;; *) echo '后端未确认，请停止本节' ;; esac
# 原后端需要内核补丁时，先按旧配置与新内核对应的 SDK 安装说明处理，
# 不能认为仅下面的 cmake 已完成内核支持。
cmake -S ~/migration_src/librealsense -B ~/migration_src/librealsense/build \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DBUILD_EXAMPLES=ON -DBUILD_GRAPHICAL_EXAMPLES=ON \
  -DFORCE_RSUSB_BACKEND="$RSUSB_BACKEND"
cmake --build ~/migration_src/librealsense/build -j2
sudo cmake --install ~/migration_src/librealsense/build
sudo install -m 644 ~/migration_src/librealsense/config/99-realsense-libusb.rules \
  /etc/udev/rules.d/99-realsense-libusb.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo ldconfig
# 拔插相机后验收，viewer 测试结束必须关闭，避免占用相机
pkg-config --modversion realsense2
realsense-viewer

# wrapper：保留 EXACT 2.51.1 与 shim include 等旧源码修正
source /opt/ros/humble/setup.bash
sudo apt install -y ros-humble-cv-bridge ros-humble-image-transport \
  ros-humble-diagnostic-updater ros-humble-xacro
cd ~/rs515/ros2_ws
colcon list
# 在这里确认源码包含 realsense2_camera/realsense2_camera_msgs；
# 若 CMake 报其他缺失包，按该 wrapper 的 package.xml 补齐，勿用最新 SDK 替代。
colcon build --symlink-install --packages-up-to realsense2_camera \
  --cmake-args -DCMAKE_PREFIX_PATH=/usr/local \
  -Drealsense2_DIR=/usr/local/lib/cmake/realsense2
source ~/rs515/ros2_ws/install/setup.bash
ros2 pkg prefix realsense2_camera
# 配置目录如不在这里，按实际 SDK 安装位置调整 realsense2_DIR

# 【终端 A】持续启动；此时还没有迁移项目配置，可直接提供参数
source /opt/ros/humble/setup.bash
source ~/rs515/ros2_ws/install/setup.bash
ros2 launch realsense2_camera rs_launch.py \
  align_depth.enable:=true enable_sync:=true \
  rgb_camera.profile:=1280x720x30 depth_module.profile:=640x480x30 \
  rgb_camera.global_time_enabled:=true depth_module.global_time_enabled:=true

# 【终端 B】验收
source /opt/ros/humble/setup.bash
source ~/rs515/ros2_ws/install/setup.bash
ros2 topic list | rg '^/camera/'
ros2 topic echo /camera/color/image_raw --once --field width
ros2 topic echo /camera/color/image_raw --once --field height
ros2 topic echo /camera/aligned_depth_to_color/image_raw --once --field width
ros2 topic echo /camera/aligned_depth_to_color/image_raw --once --field height
ros2 topic echo /camera/color/camera_info --once
ros2 param get /camera/camera rgb_camera.global_time_enabled
ros2 param get /camera/camera depth_module.global_time_enabled
timeout 10 ros2 topic delay /camera/aligned_depth_to_color/image_raw
```

验收：启动日志的 Built/Running SDK 都为2.51.1；RGB与对齐深度均为1280×720，持续运行不出现数千秒延迟。SDK后端、内核补丁和 wrapper 本地修改若无法确认，本节不能视为已完整复现。cv_bridge 在此安装，也供后面的 API 延迟测试脚本使用。

## 6. FAST_LIO2：源码、依赖、配置与定位

```bash
# 【新电脑】查找外部定位包
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 pkg prefix livox_ros_driver2

# 迁移旧 ROS2 实现及已修改 mid360.yaml
mkdir -p ~/ws/FAST_LIO_ROS2
rsync -a --exclude=build --exclude=install --exclude=log \
  "$OLD_HOST:$OLD_ROOT/ws/FAST_LIO_ROS2/" ~/ws/FAST_LIO_ROS2/
cd ~/ws/FAST_LIO_ROS2
git rev-parse HEAD
git status --short
git submodule status --recursive
# 仅缺失子模块时补齐；保留旧仓库记录的提交
# git submodule update --init --recursive

# 检查输入话题、外参、点云发布及PCD保存配置
rg -n 'lid_topic|imu_topic|extrinsic|publish|scan_body|map_en|pcd' config/mid360.yaml
nano config/mid360.yaml

# 安装依赖；source 已编译 Livox，使 rosdep 能识别该源码驱动
sudo apt install -y libeigen3-dev libpcl-dev ros-humble-pcl-ros ros-humble-pcl-conversions
rosdep install --from-paths ~/ws/FAST_LIO_ROS2 --ignore-src --rosdistro humble -r -y
cd ~/ws
colcon --log-base log_fastlio build --base-paths FAST_LIO_ROS2 \
  --build-base build_fastlio --install-base install_fastlio --symlink-install
source ~/ws/install_fastlio/setup.bash
ros2 pkg prefix fast_lio

# 【终端 A】先保证第4节Livox仍运行；持续启动FAST_LIO
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
source ~/ws/install_fastlio/setup.bash
ros2 launch fast_lio mapping.launch.py config_file:=mid360.yaml rviz:=false

# 【终端 B】验收
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
source ~/ws/install_fastlio/setup.bash
timeout 10 ros2 topic hz /Odometry
timeout 10 ros2 topic hz /cloud_registered_body
ros2 topic echo /Odometry --once --field pose.pose.position
timeout 10 ros2 run tf2_ros tf2_echo camera_init body
```

验收：定位未发散，body点云持续发布。FAST_LIO仓库参考：https://github.com/Ericsii/FAST_LIO_ROS2 。

## 7. VLM_Nav：全部包、Python依赖、路径修正与构建

本体已包含定位适配、点云过滤、建图和导航 launch。无需安装 co_nav2_nav。此处以旧日志中的实际 VLM_Nav 目录作为来源；若旧电脑项目已改名，修改 rsync 源路径。

```bash
# 【新电脑】获取项目：推荐复制旧电脑最后运行版本，保留未提交修改
mkdir -p ~/ws/VLM_Nav
rsync -a --exclude=build --exclude=install --exclude=log --exclude=.venv \
  "$OLD_HOST:$OLD_ROOT/ws/VLM_Nav/" ~/ws/VLM_Nav/
cd ~/ws/VLM_Nav
git status --short
git rev-parse HEAD

# 无法获得旧代码时的另一条获取路径，不与上述复制叠加：
# git clone https://github.com/Happy10625/VLM_Nav0.git ~/ws/VLM_Nav
# git -C ~/ws/VLM_Nav checkout b01a7645a1b09afd6e0cbacdbb4b1bab5e832c2e
# 若此版本不是旧电脑实测版本，需要另做运行行为回归验收。

# 安装明确依赖及调试/测试包
sudo apt install -y ros-humble-navigation2 ros-humble-nav2-bringup \
  ros-humble-slam-toolbox ros-humble-pointcloud-to-laserscan \
  ros-humble-pcl-ros ros-humble-pcl-conversions libpcl-dev \
  ros-humble-diagnostic-updater ros-humble-message-filters \
  ros-humble-sensor-msgs-py ros-humble-tf2-tools ros-humble-rosbag2 \
  ros-humble-cv-bridge ros-humble-ament-cmake-python \
  ros-humble-ament-cmake-gtest ros-humble-ament-cmake-pytest \
  python3-numpy python3-opencv python3-yaml python3-pytest

# Python使用系统python3，不复制旧venv；不用sudo pip
python3 -m pip install --user -r ~/ws/VLM_Nav/requirements.txt
python3 -c 'import openai, httpx, numpy, cv2, yaml; print("Python dependencies OK")'
# 若旧环境已有确切成功的openai/httpx版本，可先将requirements锁定为记录版本。

# 新电脑路径修正：只替换项目文本文件里的旧用户目录，保留备份
export NEW_USER_ROOT="$HOME"
python3 - <<'PY'
from pathlib import Path
import os
root = Path.home() / 'ws/VLM_Nav'
new = os.environ['NEW_USER_ROOT']
for p in root.rglob('*'):
    if any(x in {'.git', 'build', 'install', 'log', '.venv'} for x in p.relative_to(root).parts):
        continue
    if p.is_file() and p.suffix in {'.sh', '.py', '.yaml', '.xml', '.md', '.cfg'}:
        text = p.read_text(encoding='utf-8')
        if '/home/isee-cdh' in text:
            backup = p.with_name(p.name + '.migration-backup')
            if not backup.exists():
                backup.write_text(text, encoding='utf-8')
            p.write_text(text.replace('/home/isee-cdh', new), encoding='utf-8')
            print(p.relative_to(root))
PY
cat ~/ws/VLM_Nav/scripts/common.sh
# 确认五个setup分别指向已构建的Livox、L515、Ranger、FAST_LIO及本项目

# 安装package.xml依赖并构建混合包
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
source ~/rs515/ros2_ws/install/setup.bash
source ~/agilex_ws/install/setup.bash
source ~/ws/install_fastlio/setup.bash
rosdep install --from-paths ~/ws/VLM_Nav --ignore-src --rosdistro humble -r -y
cd ~/ws
colcon --log-base VLM_Nav/log build --base-paths VLM_Nav \
  --build-base VLM_Nav/build --install-base VLM_Nav/install --symlink-install
source ~/ws/VLM_Nav/install/setup.bash
chmod +x ~/ws/VLM_Nav/scripts/*.sh

# 构建验收：必须有三个可执行节点，不仅能import Python
ros2 pkg prefix vlm_nav
ros2 pkg executables vlm_nav
python3 -c 'import vlm_nav, rclpy; print("vlm_nav import OK")'
# 应包含：fastlio_odom_adapter、obstacle_cloud_filter、vlm_navigator

# 软件测试：不等于实机通过
bash ~/ws/VLM_Nav/scripts/test_no_hardware.sh
cd ~/ws
colcon --log-base VLM_Nav/log test --build-base VLM_Nav/build \
  --install-base VLM_Nav/install --packages-select vlm_nav \
  --event-handlers console_direct+
colcon test-result --test-result-base ~/ws/VLM_Nav/build --verbose
```

注意：本体主导航不直接使用cv_bridge，但 `scripts/qwen_latency_probe.py` 使用它，因此将它列入完整迁移工具依赖。外部驱动还可能需要 image_transport；不用因此给主导航增加新的依赖代码。

## 8. TF、点云过滤、二维地图和Nav2：启动与验收

启动前复核相机安装TF和base_to_body参数；更换电脑但未移动传感器可复用，拆装位置改变必须重新标定。不要把当前仓库中标为TODO的过滤边界视作已经通过实机校准。

```bash
# 【新电脑】查找全部链路包并核对参数
source ~/ws/VLM_Nav/scripts/common.sh
ros2 pkg prefix pointcloud_to_laserscan
ros2 pkg prefix slam_toolbox
ros2 pkg prefix nav2_bringup
ros2 pkg prefix vlm_nav
rg -n 'base_to_body|height|crop|voxel|input_topic|output_topic' ~/ws/VLM_Nav/config/robot.yaml
rg -n 'base_to_camera|--x|--y|--z|--pitch' ~/ws/VLM_Nav/launch/vlm_navigation.launch.py
nano ~/ws/VLM_Nav/config/robot.yaml
nano ~/ws/VLM_Nav/launch/vlm_navigation.launch.py
# 参数修改后重新执行第7节构建，避免修改的是源码而运行的是旧install副本。

# 查看现有节点，不重复启动硬件或地图
ros2 node list
ros2 topic info /Odometry
ros2 topic info /cloud_registered_body

# 【终端 A】第3～6节硬件仍运行时，只启动本系统。enabled=false禁用VLM自动任务
ros2 launch vlm_nav system.launch.py enabled:=false

# 【终端 B】验收；每条timeout命令分别观察
source ~/ws/VLM_Nav/scripts/common.sh
ros2 node list
ros2 param get /vlm_nav enabled
timeout 8 ros2 run tf2_ros tf2_echo map base_link
timeout 8 ros2 run tf2_ros tf2_echo base_link body
timeout 8 ros2 run tf2_ros tf2_echo base_link camera_color_optical_frame
timeout 10 ros2 topic hz /fastlio/odom
ros2 topic info -v /cloud_registered_body
timeout 10 ros2 topic hz /vlm_nav/obstacle_cloud
timeout 8 ros2 topic echo /diagnostics
timeout 10 ros2 topic hz /scan
ros2 topic echo /map --once --field info
ros2 lifecycle get /planner_server
ros2 lifecycle get /controller_server
ros2 lifecycle get /bt_navigator
ros2 action list -t
ros2 param get /behavior_server costmap_topic
bash ~/ws/VLM_Nav/scripts/check_system.sh

# 【终端 C】可视化，打开后检查TF、点云、激光、地图和costmap
source ~/ws/VLM_Nav/scripts/common.sh
bash ~/ws/VLM_Nav/scripts/start_rviz.sh
# 在监督下使用RViz的Nav2 Goal测试选点导航、取消和停车；该操作会移动底盘。

# TF监测/建树可选诊断
# timeout 10 ros2 run tf2_ros tf2_monitor odom base_link
# ros2 run tf2_tools view_frames
```

验收：base_link↔body稳定；/vlm_nav/obstacle_cloud同时供scan与Nav2使用；/map正常；Nav2生命周期active；无重复odom→base_link。第一次从新SLAM会话开始，不加载历史噪声地图。

## 9. 云端VLM：配置、API验收与任务使能

云端接口调用会产生账号用量。先测试一次接口与延迟，再使能运动。密钥通过交互读入，不写入文档或源码。

```bash
# 【新电脑】查找当前客户端与接口变量逻辑，不打印密钥
source ~/ws/VLM_Nav/scripts/common.sh
python3 -c 'import openai, httpx; print("openai", openai.__version__, "httpx", httpx.__version__)'
rg -n 'DASHSCOPE|OPENAI|PROXY' ~/ws/VLM_Nav/vlm_nav/vlm_client.py

# 当前终端安全输入；填写实际业务空间ID
read -rsp '输入百炼API Key: ' DASHSCOPE_API_KEY
printf '\n'
export DASHSCOPE_API_KEY
export DASHSCOPE_WORKSPACE_ID='替换为你的业务空间ID'
export DASHSCOPE_MODEL='qwen3-vl-flash'
# 如使用完整URL，则替代上面的WORKSPACE_ID设置：
# export DASHSCOPE_BASE_URL='https://实际业务空间ID.cn-beijing.maas.aliyuncs.com/compatible-mode/v1'
unset ALL_PROXY all_proxy
# 若确实需要且新电脑有本地代理，才设置：
# export HTTPS_PROXY='http://127.0.0.1:实际端口'

# 必须有相机RGB数据，执行1次实际VLM请求
python3 ~/ws/VLM_Nav/scripts/qwen_latency_probe.py \
  --topic /camera/color/image_raw --target chair --samples 1 --timeout 8

# 环境变量必须由启动VLM节点的进程继承；已运行节点不会读取别的终端新export。
# 若第8节节点未带API配置，回到其启动终端Ctrl+C关闭system.launch，
# 保持硬件节点运行，然后在本终端带着上述变量重启：
ros2 launch vlm_nav system.launch.py enabled:=false

# 【另一个验收终端】API和手动导航通过后才ARM；ARM会使小车扫描/导航
source ~/ws/VLM_Nav/scripts/common.sh
bash ~/ws/VLM_Nav/scripts/check_system.sh
ros2 param set /vlm_nav target_description chair
bash ~/ws/VLM_Nav/scripts/arm.sh
# 按脚本提示输入ARM；arm.sh不接收目标参数，目标在disabled状态下通过参数设置。

# 查看实时输出/诊断；需要在另一个终端执行停车命令
timeout 20 ros2 topic echo /vlm_nav/output_text
# 随时停止自动任务并发送项目停车请求
bash ~/ws/VLM_Nav/scripts/stop.sh
```

验收：API返回可解析结果，延迟符合当前robot.yaml约束，启用后无持续TF或RGB-D错误。stop.sh不能代替硬件急停。

## 10. 后续冷启动命令

所有组件安装验收完成后，可使用项目已有启动器。不要与第3～9节仍运行的同名节点重复启动。先source修正后的common.sh，API环境按第9节设置。

```bash
# 【新电脑】插好设备、确认CAN驱动和网络，再启动
source ~/ws/VLM_Nav/scripts/common.sh
sudo modprobe gs_usb
ip -details link show can0
bash ~/ws/VLM_Nav/scripts/start_hardware.sh

# 设置第9节API环境后启动导航验证窗口（保持enabled=false）
bash ~/ws/VLM_Nav/scripts/start_navigation_validation.sh

# 独立检查终端
source ~/ws/VLM_Nav/scripts/common.sh
bash ~/ws/VLM_Nav/scripts/check_system.sh

# 监督下启动任务与停止
ros2 param set /vlm_nav target_description chair
bash ~/ws/VLM_Nav/scripts/arm.sh
bash ~/ws/VLM_Nav/scripts/stop.sh
```

## 11. 数据归档与不迁移范围

```bash
# 【新电脑】可选：归档实验资料；不将旧地图自动载入首次验收
mkdir -p ~/migration_archive/bags ~/migration_archive/filter_results
# 源路径存在时再执行
# rsync -a "$OLD_HOST:$OLD_ROOT/ws/bags/" ~/migration_archive/bags/
# rsync -a "$OLD_HOST:$OLD_ROOT/ws/filter_results/" ~/migration_archive/filter_results/
# 地图PGM/YAML、ARM记录和版本清单可同样复制，检查路径后再使用。
```

不迁移：CoNav、co_nav2_nav、CoNav旧venv、ZMQ适配器、Habitat/HM3D/ObjectNav及旧识别栈。当前仓库使用云端VLM，不要求本地模型/CUDA/PyTorch。MID-360的内置IMU由Livox驱动提供，无需单独IMU驱动。pyrealsense2仅为直接SDK试验可选工具。

## 完成判据

1. 旧版本和修正可追溯，所有工作空间已在新电脑重新编译。
2. CAN、雷达、RGB-D、FAST_LIO独立验收通过。
3. TF连通且无重复发布，点云过滤、scan、地图及Nav2正常。
4. enabled=false状态下手动选点、取消、停车通过。
5. VLM接口和图像时刻TF通过，再执行监督下的目标导航。

仍需现场确认的三项：旧L515 SDK实际后端/内核配置、wrapper的完整本地修正，以及旧电脑最后运行代码与GitHub检查版本的差异。未确认这些项时，不能承诺只凭公开仓库就可完整复现。
