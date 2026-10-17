#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "请使用普通用户运行本脚本，不要直接 sudo bash。" >&2
  exit 1
fi

. /etc/os-release
if [[ "$ID" != "ubuntu" || "$VERSION_ID" != "22.04" ]]; then
  echo "本脚本仅适用于 Ubuntu 22.04；当前为 $ID $VERSION_ID。" >&2
  exit 1
fi

echo "将为用户 $USER 安装 ROS 2 Humble 和 Ranger-VLM_Nav 依赖。"
sudo -v

sudo apt update
sudo apt install -y \
  locales software-properties-common curl gnupg ca-certificates \
  git rsync ripgrep nano build-essential cmake pkg-config \
  python3-pip python3-venv gnome-terminal iproute2 usbutils pciutils

sudo locale-gen en_US.UTF-8
sudo add-apt-repository -y universe

if ! grep -RqsE 'packages\.ros\.org/ros2' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
  sudo curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /usr/share/keyrings/ros-archive-keyring.gpg
  arch="$(dpkg --print-architecture)"
  printf 'deb [arch=%s signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu jammy main\n' \
    "$arch" | sudo tee /etc/apt/sources.list.d/ros2.list >/dev/null
fi

sudo apt update
sudo apt install -y \
  ros-humble-desktop \
  python3-colcon-common-extensions python3-rosdep \
  can-utils ros-humble-teleop-twist-keyboard \
  libusb-1.0-0-dev libudev-dev libssl-dev libglfw3-dev libgtk-3-dev \
  libgl1-mesa-dev libglu1-mesa-dev \
  libeigen3-dev libpcl-dev \
  ros-humble-cv-bridge ros-humble-image-transport \
  ros-humble-diagnostic-updater ros-humble-xacro \
  ros-humble-pcl-ros ros-humble-pcl-conversions \
  ros-humble-navigation2 ros-humble-nav2-bringup \
  ros-humble-slam-toolbox ros-humble-pointcloud-to-laserscan \
  ros-humble-message-filters ros-humble-sensor-msgs-py \
  ros-humble-tf2-tools ros-humble-rosbag2 \
  ros-humble-ament-cmake-python ros-humble-ament-cmake-gtest \
  ros-humble-ament-cmake-pytest \
  python3-numpy python3-opencv python3-yaml python3-pytest

if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
  sudo rosdep init
fi
rosdep update

set +u
source /opt/ros/humble/setup.bash
set -u
echo "ROS_DISTRO=$ROS_DISTRO"
ros2 pkg prefix rclpy
ros2 pkg prefix rviz2
colcon version-check 2>/dev/null || colcon --help >/dev/null
echo "基础环境安装完成。"
