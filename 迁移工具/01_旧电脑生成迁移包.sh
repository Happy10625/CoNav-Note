#!/usr/bin/env bash
set -euo pipefail

OLD_ROOT="/home/isee-cdh"
WORKSPACE="$OLD_ROOT/松灵小车"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_ROOT="$WORKSPACE/迁移输出"
BUNDLE="$OUT_ROOT/Ranger-VLM_Nav_core_$STAMP"
CORE="$BUNDLE/core"
MANIFEST="$BUNDLE/manifest"

mkdir -p "$CORE" "$MANIFEST/git"

copy_tree() {
  local source="$1"
  local relative="$2"
  if [[ ! -d "$source" ]]; then
    printf 'MISSING\t%s\n' "$source" >> "$MANIFEST/missing-paths.tsv"
    return 0
  fi
  mkdir -p "$CORE/$relative"
  rsync -a \
    --exclude='build/' --exclude='build*/' \
    --exclude='install/' --exclude='log/' --exclude='log_fastlio/' \
    --exclude='.venv/' --exclude='__pycache__/' --exclude='.pytest_cache/' \
    --exclude='bags/' \
    "$source/" "$CORE/$relative/"
}

# 驱动、SDK、定位与主项目。保留各仓库 .git 和所有未提交文件。
copy_tree "$OLD_ROOT/agilex_ws/src" "agilex_ws/src"
copy_tree "$OLD_ROOT/ros2_ws/src/livox_ros_driver2" "ros2_ws/src/livox_ros_driver2"
copy_tree "$OLD_ROOT/ws/Livox-SDK2" "ws/Livox-SDK2"
copy_tree "$OLD_ROOT/rs515/ros2_ws/src" "rs515/ros2_ws/src"
copy_tree "$OLD_ROOT/rs515/librealsense-2.51.1" "rs515/librealsense-2.51.1"
copy_tree "$OLD_ROOT/ws/FAST_LIO_ROS2" "ws/FAST_LIO_ROS2"
copy_tree "$OLD_ROOT/ws/VLM_Nav" "ws/VLM_Nav"

# 运行记录很小，保留诊断输出与 ARM 记录；不复制 ROS 全局缓存。
if [[ -d "$OLD_ROOT/.ros/vlm_nav" ]]; then
  mkdir -p "$CORE/ros_runtime/vlm_nav"
  rsync -a "$OLD_ROOT/.ros/vlm_nav/" "$CORE/ros_runtime/vlm_nav/"
fi

# 迁移与实车资料；显式排除凭据文件和 CoNav 主程序资料。
mkdir -p "$CORE/docs"
for name in \
  'Ranger-VLM_Nav迁移清单 (1).md' \
  'Ranger-VLM_Nav迁移清单.md' \
  '使用日志.md' '数据链路一览.md' '文件指示.md' '文件结构示意.md' \
  '错误总结.md' '小车使用手册.md' '小技巧.txt' '为什么会来回旋转.md' \
  'ros2_readme.md' 'gitinfo.txt'; do
  [[ -f "$WORKSPACE/$name" ]] && cp -a "$WORKSPACE/$name" "$CORE/docs/"
done
[[ -d "$WORKSPACE/gallery" ]] && rsync -a "$WORKSPACE/gallery/" "$CORE/docs/gallery/"

# 文档日志中可能曾粘贴过 sk- 前缀的真实凭据；只脱敏迁移副本。
# 32 字符阈值可避开普通英文技术文本中的短误报。
find "$CORE/docs" -type f -print0 | xargs -0 -r perl -pi -e \
  's/sk-[A-Za-z0-9_-]{32,}/[REDACTED_API_KEY]/g'

# 系统与软件版本清单，不记录任何密钥值。
lsb_release -a > "$MANIFEST/lsb_release.txt" 2>&1 || true
uname -a > "$MANIFEST/kernel.txt"
dpkg-query -W -f='${binary:Package}\t${Version}\n' > "$MANIFEST/dpkg-packages.tsv"
python3 -m pip freeze > "$MANIFEST/python-packages.txt" 2>&1 || true
printf 'ROS_DISTRO=%s\n' "${ROS_DISTRO:-humble}" > "$MANIFEST/ros-environment.txt"
printf 'ROS_DOMAIN_ID=%s\n' "${ROS_DOMAIN_ID:-<unset>}" >> "$MANIFEST/ros-environment.txt"
printf 'RMW_IMPLEMENTATION=%s\n' "${RMW_IMPLEMENTATION:-<unset>}" >> "$MANIFEST/ros-environment.txt"
ip -brief address > "$MANIFEST/network-addresses.txt" 2>&1 || true
ip -details link show can0 > "$MANIFEST/can0.txt" 2>&1 || true
lsusb > "$MANIFEST/usb-devices.txt" 2>&1 || true

if command -v pkg-config >/dev/null && pkg-config --exists realsense2; then
  {
    printf 'version='; pkg-config --modversion realsense2
    printf 'prefix='; pkg-config --variable=prefix realsense2
  } > "$MANIFEST/realsense-installed.txt"
fi
find "$OLD_ROOT/realsenseai" "$OLD_ROOT/rs515" -name CMakeCache.txt -type f -print0 2>/dev/null |
  while IFS= read -r -d '' cache; do
    printf '\n[%s]\n' "$cache"
    rg '^(FORCE_RSUSB_BACKEND|BUILD_WITH_CUDA|BUILD_EXAMPLES|BUILD_GRAPHICAL_EXAMPLES|CMAKE_INSTALL_PREFIX):' "$cache" || true
  done > "$MANIFEST/realsense-cmake-flags.txt"

repos=(
  "$OLD_ROOT/agilex_ws/src/ugv_sdk"
  "$OLD_ROOT/agilex_ws/src/ranger_ros2"
  "$OLD_ROOT/ros2_ws/src/livox_ros_driver2"
  "$OLD_ROOT/ws/Livox-SDK2"
  "$OLD_ROOT/ws/FAST_LIO_ROS2"
  "$OLD_ROOT/ws/VLM_Nav"
)
printf 'path\thead\tdescribe\torigin\n' > "$MANIFEST/git-repositories.tsv"
for repo in "${repos[@]}"; do
  [[ -d "$repo/.git" ]] || continue
  label="$(printf '%s' "$repo" | sed 's#^/##; s#/#__#g')"
  head="$(git -C "$repo" rev-parse HEAD)"
  describe="$(git -C "$repo" describe --tags --always 2>/dev/null || true)"
  origin="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
  printf '%s\t%s\t%s\t%s\n' "$repo" "$head" "$describe" "$origin" >> "$MANIFEST/git-repositories.tsv"
  git -C "$repo" status --short > "$MANIFEST/git/${label}.status.txt"
  git -C "$repo" diff --binary > "$MANIFEST/git/${label}.working-tree.patch"
  git -C "$repo" diff --cached --binary > "$MANIFEST/git/${label}.index.patch"
  git -C "$repo" submodule status --recursive > "$MANIFEST/git/${label}.submodules.txt" 2>&1 || true
done

cat > "$BUNDLE/README_新电脑恢复.txt" <<'EOF'
这是旧电脑生成的核心迁移包，不含 build/install/log、旧虚拟环境、CoNav、rosbag 和明文 API 密钥。

1. 将整个解压目录复制到新电脑。
2. 在新电脑运行：bash 02_新电脑恢复源码.sh
   默认只显示 rsync 预演；确认后运行：bash 02_新电脑恢复源码.sh --apply
3. 按 docs/Ranger-VLM_Nav迁移清单 (1).md 从 ROS Humble 和依赖安装章节继续，所有工作空间必须重新编译。
4. API 密钥使用密码管理器或加密介质另行迁移，不要放进普通压缩包。
5. rosbag 位于旧电脑 ~/ws/VLM_Nav/bags（约 8.9 GB），按需单独 rsync。
EOF

cp -a "$WORKSPACE/迁移工具/02_新电脑恢复源码.sh" "$BUNDLE/"

archive="$BUNDLE.tar.zst"
tar --zstd -cf "$archive" -C "$OUT_ROOT" "$(basename "$BUNDLE")"
(cd "$OUT_ROOT" && sha256sum "$(basename "$archive")") > "$archive.sha256"

printf 'BUNDLE_DIR=%s\nARCHIVE=%s\nCHECKSUM=%s\n' \
  "$BUNDLE" "$archive" "$archive.sha256"
du -sh "$BUNDLE" "$archive"
