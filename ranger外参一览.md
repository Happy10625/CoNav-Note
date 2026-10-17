# Ranger 外参一览

核对日期：2026-10-17。以下整理当前 Ranger 启动链保留的配置及默认值，**不代表本次已重新标定，也不保证运行参数未被覆盖**。包括 VLM_Nav 仓库内的数值，以及硬件脚本实际调用的外部驱动配置；不包含 Go2 外参。

约定：`T_A_B` 表示 B 在 A 中的位姿，将 B 中的点变换到 A：`p_A = R_A_B × p_B + t_A_B`。下表平移单位为米，RPY顺序为 `[roll, pitch, yaw]`、单位为弧度，旋转矩阵为 `Rz(yaw) Ry(pitch) Rx(roll)`。车体 `base_link` 的轴向为 x前、y左、z上。

## 1. VLM_Nav 中保存的固定关系

| 关系 | 平移 `[x,y,z]`（m） | RPY（rad） | 含义与用途 | 数值来源 |
|---|---|---|---|---|
| `T_base_link_body` | `[0.299, -0.02329, 0.32088]` | `[0, 0, 3.141592653589793]` | FAST-LIO的IMU/body原点位于车体参考点前方29.9 cm、右侧2.329 cm、上方32.088 cm；绕z转180°。把FAST-LIO的机体位姿换算为Nav2使用的车体位姿。 | [config/robot.yaml](../config/robot.yaml:8)；[适配器默认值](../vlm_nav/fastlio_odom_adapter.py:78) |
| `T_base_link_camera_link` | `[-0.16, 0, 1.185]` | `[0, 0.45204034, 0]` | 相机安装参考系位于车体参考点后方16 cm、上方118.5 cm；正pitch约25.90°，在此轴向约定下为朝前下俯。用于将RGB-D观测关联到车体及地图。高度相对base_link原点，不自动等于离地高度。 | [launch/vlm_navigation.launch.py](../launch/vlm_navigation.launch.py:43) |
| `T_odom_camera_init` | `[0, 0, 0]` | `[0, 0, 0]` | 将Nav2的odom与FAST-LIO启动时的世界参考系camera_init设为重合。这是坐标系衔接约定，不是相机安装外参；camera_init这个名称不指RGB相机。 | [launch/vlm_navigation.launch.py](../launch/vlm_navigation.launch.py:36) |

`base_to_body` **只在适配器内部作为固定矩阵使用，不直接广播 `base_link→body` 静态TF**。适配器实际计算：

```text
T_odom_base_link = T_camera_init_body × inverse(T_base_link_body)
```

这里使用了 `T_odom_camera_init = I`。结果发布为 `/fastlio/odom`，并在 `publish_tf=true` 时广播动态 `odom→base_link`。直接把 `base_to_body_xyz` 取负，不能代替完整的刚体变换求逆。

相机静态TF由 `/base_to_camera` 发布，受 `publish_camera_tf` 控制；`odom→camera_init` 和适配器受 `enable_odom_adapter` 控制，默认均启用。参数来源是启动时实际加载的robot.yaml，新协作入口通过 [ranger_local.launch.py](../launch/ranger_local.launch.py) 复用上述启动链。

## 2. Ranger 硬件依赖中保存的外参

| 配置 | 保存值 | 含义与用途 | 来源 |
|---|---|---|---|
| FAST-LIO：LiDAR→IMU/body，`T_IMU_LiDAR` | `mapping.extrinsic_T=[-0.011,-0.02329,0.04412] m`；`mapping.extrinsic_R=I₃`，等效RPY为`[0,0,0]` | 将雷达测得的点换到MID-360的IMU/body坐标系：`p_IMU=R×p_LiDAR+t`。雷达原点在IMU系中的坐标为上述平移；它与“整颗传感器安装在车体哪里”的base_to_body是两层不同的外参。`mapping.extrinsic_est_en=false`，当前使用固定配置，不在线估计。 | [mid360.yaml](/home/isee601/ws/FAST_LIO_ROS2/config/mid360.yaml:36)；[变换实现](/home/isee601/ws/FAST_LIO_ROS2/src/laserMapping.cpp:215) |
| Livox驱动：输出点坐标外参，`lidar_configs[].extrinsic_parameter` | `x=y=z=0`、`roll=pitch=yaw=0` | 当前为单位变换，不额外平移或旋转驱动输出点。驱动字段原生单位是**毫米、角度**，区别于ROS参数表的米、弧度。该配置本身不是一个静态TF发布器，也不是base_link安装外参。 | [MID360_config.json](/home/isee601/ros2_ws/src/livox_ros_driver2/config/MID360_config.json)；[驱动单位定义](/home/isee601/ros2_ws/src/livox_ros_driver2/src/comm/comm.h:215) |

[04_fastlio.sh](../scripts/04_fastlio.sh) 调用 `fast_lio mapping.launch.py config_file:=mid360.yaml`。当前安装路径 `/home/isee601/ws/install_fastlio/fast_lio/share/fast_lio/config/mid360.yaml` 解析到上述源码文件。[03_livox.sh](../scripts/03_livox.sh) 调用 `msg_MID360_launch.py`，该launch选择上述JSON。外部工作空间不是本仓库随代码复制的文件，部署到其他主机时需重新核对。

## 3. RealSense 内部 TF：驱动读取设备，仓库未保存设备数值

这些关系由 `/camera/camera` 根据设备内参/外参和启用的流发布，来源为本机 [base_realsense_node.cpp](/home/isee601/rs515/ros2_ws/src/realsense-ros/realsense2_camera/src/base_realsense_node.cpp:875)。实际存在的frame以驱动版本、启用流和TF树为准。

| 关系 | 保存/生成方式 | 含义 |
|---|---|---|
| `camera_link→camera_color_frame` | 从设备读取流间外参，驱动转换成ROS轴向；VLM_Nav没有固定数值 | 相机安装参考系到彩色相机参考系的偏移与旋转。 |
| `camera_link→camera_depth_frame` | 同上，受深度流及驱动发布方式影响 | 安装参考系到深度相机参考系。不能因深度已对齐就把它设为零。 |
| `camera_link→camera_infra_frame` | 同上，受红外流是否启用影响 | 安装参考系到红外相机参考系。 |
| `camera_link→camera_confidence_frame` | 同上，受confidence流是否启用影响 | 安装参考系到置信度图参考系。 |
| `camera_color_frame→camera_color_optical_frame` | 平移`[0,0,0]`，RPY=`[-π/2,0,-π/2]` | 彩色图像的光学轴约定：x右、y下、z朝镜头前方；Ranger VLM定位使用此optical frame。 |
| `camera_depth_frame→camera_depth_optical_frame` | 同一固定光学旋转，零平移 | 深度图光学坐标轴转换。 |
| `camera_infra_frame→camera_infra_optical_frame` | 同一固定光学旋转，零平移 | 红外图光学坐标轴转换。 |
| `camera_confidence_frame→camera_confidence_optical_frame` | 同一固定光学旋转，零平移 | 置信度图光学坐标轴转换。 |

光学旋转对应四元数 `[x,y,z,w]=[-0.5,0.5,-0.5,0.5]`（整体取负等价）。相机安装外参的下俯角与这里的光学轴转换分别使用，不能互相替代。驱动可能还生成aligned-depth相关参考系；Ranger默认读取已对齐到彩色几何的深度，其定位所需整条 `base_link→camera_color_optical_frame` 由安装TF与驱动内部TF复合得到，不能只套用第一节camera_link的六个数值。

[config/realsense.yaml](../config/realsense.yaml) 保存启动设备重置和时间戳相关设置，没有保存上述设备流间外参或图像内参K。[01_camera.sh](../scripts/01_camera.sh) 启用对齐深度；内参K属于像素投影参数，不是TF外参。

## 4. 动态定位与协作对齐：不要当成固定安装值

```text
map ──AMCL动态定位──> odom
                       ├──固定单位变换──> camera_init ──FAST-LIO动态──> body
                       └──适配器动态──> base_link ──固定安装──> camera_link
                                                               └──设备流间外参──> camera_color_frame
                                                                                   └──光学轴转换──> camera_color_optical_frame
```

| 关系 | 当前处理 |
|---|---|
| `map→odom` | AMCL根据地图、扫描和初始位姿估计，随定位更新；没有可在这里罗列的固定xyz/rpy。 |
| `camera_init→body` | FAST-LIO输出动态IMU/body位姿，不能作为安装外参保存。 |
| `odom→base_link` | 适配器利用第一节安装外参换算得到。底盘入口 [02_ranger.sh](../scripts/02_ranger.sh) 设置 `publish_odom_tf=false`，避免重复发布。 |
| Ranger本地地图→`lab_ref` | [alignment.yaml](../cooperative_ws/src/multi_agent_nav/config/alignment.yaml) 中Ranger的 `transform=null`、`validated=false`，尚无可用实测SE(2)对齐值。单机 `local_only` 内存中的`[0,0,0]`仅表示采用本机地图作参考，不是双机标定结果，也不会据此发布安装TF。 |

## 5. 只读核对运行值

每个新终端先加载公共环境。以下命令不发布TF、不改变初始位姿；`timeout`到期返回124属于采样结束。

```bash
source /home/isee601/ws/VLM_Nav/RangerVLM_env.bash
ros2 param get /fastlio_odom_adapter base_to_body_xyz
ros2 param get /fastlio_odom_adapter base_to_body_rpy
ros2 param get /laser_mapping mapping.extrinsic_T
ros2 param get /laser_mapping mapping.extrinsic_R
ros2 param get /laser_mapping mapping.extrinsic_est_en
timeout 6 ros2 run tf2_ros tf2_echo odom camera_init
timeout 6 ros2 run tf2_ros tf2_echo base_link body
timeout 6 ros2 run tf2_ros tf2_echo base_link camera_link
timeout 6 ros2 run tf2_ros tf2_echo camera_color_frame camera_color_optical_frame
timeout 6 ros2 run tf2_ros tf2_echo base_link camera_color_optical_frame
```

`base_link→body` 的查询值来自动态TF链复合及插值，不证明存在直接静态发布者，也不宜拿动态插值误差直接替换配置常量。修改安装外参应追溯对应源文件及实际加载路径；本文只整理现存值，不改动运行配置。
