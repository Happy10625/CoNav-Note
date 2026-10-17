#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "请使用普通用户运行，不要直接 sudo bash。" >&2
  exit 1
fi

LIVOX_BUILD="$HOME/ws/Livox-SDK2/build"
RS_SOURCE="$HOME/rs515/librealsense-2.51.1"
RS_BUILD="$RS_SOURCE/build"

test -f "$LIVOX_BUILD/cmake_install.cmake"
test -f "$RS_BUILD/cmake_install.cmake"

sudo -v
sudo apt update
sudo apt install -y libasio-dev ros-humble-controller-manager

sudo cmake --install "$LIVOX_BUILD"
sudo cmake --install "$RS_BUILD"
sudo install -m 644 "$RS_SOURCE/config/99-realsense-libusb.rules" \
  /etc/udev/rules.d/99-realsense-libusb.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo ldconfig

echo "[Livox]"
ldconfig -p | grep livox
echo "[RealSense]"
pkg-config --modversion realsense2
pkg-config --variable=prefix realsense2
ldconfig -p | grep librealsense2
echo "SDK 和补充依赖安装完成。"
