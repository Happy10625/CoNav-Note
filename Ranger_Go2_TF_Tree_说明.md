# Ranger Mini 3.0 与 Unitree Go2 TF 树说明

> 目的：记录当前工程中两台机器人使用的主要 TF 链，以及各坐标系原点在物理/算法上的含义。
>
> 约定：
> - 对机体坐标系，默认采用 ROS 常用约定：`+x` 向前、`+y` 向左、`+z` 向上。
> - `camera_*_optical_frame` 属于相机光学坐标系，通常 `+z` 向前、`+x` 向右、`+y` 向下。
> - 本文只写当前项目中已有记录支持的关系；未明确标定的物理原点不做猜测。

---

# 1. Ranger Mini 3.0（小车）

## 1.1 当前主要 TF 结构

当前工程可抽象为：

```text
map
└── odom
    └── base_link
        ├── LiDAR / body 相关 frame
        └── camera 相关 frame
```

历史调试记录中还出现过：

```text
odom
└── camera_init
```

以及 FAST-LIO 点云：

```text
/cloud_registered_body
frame_id = body
```

因此 Ranger 侧实际上存在两类 frame：

1. 导航链使用的机器人 frame
   - `map`
   - `odom`
   - `base_link`

2. FAST-LIO 内部/输出使用的 frame
   - `camera_init`
   - `body`

当前项目中通过 `fastlio_odom_adapter` 将 FAST-LIO 的里程计结果适配成：

```text
odom → base_link
```

供 Nav2 使用。

## 1.2 各坐标系原点

### `map`

全局地图坐标系。

原点不是机器人上某个实体位置，而是 SLAM 建图时定义的全局参考原点。

特点：

- 不随机器人移动；
- 原点通常与 SLAM 初始化时的位置有关；
- 后续 SLAM 可以通过 `map → odom` 修正累计定位漂移。

### `odom`

连续局部里程计坐标系。

原点也不是固定在机器人上的物理点，可以理解为机器人开始运行时建立的连续运动参考系。

特点：

- 不应因为 SLAM 回环而突然跳变；
- 允许长期累计漂移；
- FAST-LIO / odometry 主要在这一层提供连续运动估计；
- Nav2 通过 `map → odom → base_link` 获得机器人全局位置。

### `base_link`

Ranger 机器人机体参考坐标系。

原点固定在车体上，并随机器人一起运动。当前记录没有给出 Ranger Mini 3.0 的 `base_link` 在车体机械结构上的精确毫米级位置，因此不把它强行描述成“几何中心”或“后轴中心”。

在当前导航工程中可理解为：

> Ranger 的运动与 footprint 计算所使用的机器人主体参考点。

轴向：

```text
           +x 前
            ↑
            |
+y 左  ←  base_link
            |
            +z 向上
```

### `body`

`body` 是 FAST-LIO 输出 `/cloud_registered_body` 时使用的 frame。

当前记录能确认：

```text
/cloud_registered_body
frame_id = body
```

但没有保存 Ranger 上：

```text
base_link → body
```

的精确静态外参，因此不能断言 `body` 原点与 `base_link` 完全重合。

如需精确确认，应检查：

```bash
ros2 run tf2_ros tf2_echo base_link body
```

或对应 URDF / FAST-LIO 配置。

### `camera_init`

这是 FAST-LIO 常见的初始化世界 frame。

它不是相机实体光心，也不是“相机安装位置”，应理解为 FAST-LIO 启动后建立的初始惯性/里程计世界参考坐标系。

历史配置中曾使用：

```text
odom → camera_init
```

静态 TF 来衔接 FAST-LIO 与导航坐标树。

因此：

```text
camera_init ≠ camera_link
```

二者不要混淆。

## 1.3 Ranger 的坐标链理解

导航时，一个障碍物点最终通常经过类似：

```text
传感器局部坐标
      ↓
body / sensor frame
      ↓
base_link
      ↓
odom
      ↓
map
```

对于 Nav2，最核心的是：

```text
map → odom → base_link
```

---

# 2. Unitree Go2（机器狗）

## 2.1 当前主要 TF 树

Go2 当前工程可以整理为：

```text
map
└── odom
    └── base_link
        ├── body_imu
        ├── hesai_lidar
        └── camera_link
            └── camera_*_optical_frame
```

对应职责：

```text
map → odom
    SLAM Toolbox 提供全局修正

odom → base_link
    FAST-LIO 提供连续里程计

base_link → body_imu
base_link → hesai_lidar
base_link → camera_link
    静态外参
```

## 2.2 `map`

全局地图 frame。

原点属于 SLAM 世界坐标，而不是机器狗上的物理点。

VLM 最终得到的目标位置也需要投影到这个坐标系：

```text
RGB target pixel
→ raw depth
→ depth optical 3D
→ TF
→ map point
```

## 2.3 `odom`

Go2 的连续里程计世界坐标系。

当前链路中 FAST-LIO 主要负责：

```text
odom → base_link
```

它：

- 原点不固定在机器人身体上；
- 启动时初始化；
- 随运动保持连续；
- 可以长期漂移；
- SLAM 再通过 `map → odom` 做全局修正。

## 2.4 `base_link`

这是 Go2 当前整个导航系统最重要的机体参考坐标系。

所有传感器安装外参都以它为父 frame：

```text
base_link
├── body_imu
├── hesai_lidar
└── camera_link
```

在导航中：

- footprint 围绕 `base_link` 定义；
- Nav2 的机器人位置是 `base_link` 在 `map/odom` 中的位置；
- 障碍物点最终也要转换到与 `base_link` / costmap 一致的坐标关系中。

轴方向：

```text
+x：机器狗前方
+y：机器狗左侧
+z：机器狗上方
```

当前记录没有给出 Unitree 官方机械图中的 `base_link` 毫米级基准点，因此最准确的描述是：

> `base_link` 是当前工程采用的 Go2 主体运动参考原点，位于机身参考位置附近；精确机械位置应以当前 URDF / Unitree frame 定义为准。

不要擅自把它等同于 IMU 中心、LiDAR 中心、相机中心或四足支撑面的中心。

---

# 3. Go2 传感器 frame 的实际位置

以下平移均表示：

```text
base_link → sensor_frame
```

即“传感器 frame 原点在 `base_link` 坐标系中的位置”。

## 3.1 `body_imu`

当前静态外参：

```text
base_link → body_imu

x = -0.02557 m
y =  0
z = +0.04232 m
R = I
```

因此：

```text
body_imu 原点相对 base_link：

后方 2.557 cm
左右方向基本重合
上方 4.232 cm
```

## 3.2 `hesai_lidar`

当前 XT16 外参：

```text
base_link → hesai_lidar

x = +0.14543 m
y =  0
z = +0.13312 m
R = I
```

因此：

```text
XT16 原点位于 base_link：

前方约 14.543 cm
左右基本居中
上方约 13.312 cm
```

当前 FAST-LIO 还使用：

```text
p_imu = R * p_lidar + T

T = [0.171, 0, 0.0908]
R = I
```

这是 LiDAR → IMU 的 FAST-LIO 外参语义，不应和 `base_link → hesai_lidar` 混为一谈。

## 3.3 `camera_link`

当前使用的静态外参：

```text
base_link → camera_link

x = +0.32715 m
y = -0.00003 m
z = +0.04297 m
roll  = 0
pitch = 0
yaw   = 0
```

即：

```text
camera_link 原点大约位于：

base_link 前方 32.715 cm
横向基本居中
上方 4.297 cm
```

其中 `y = -0.00003 m` 仅约 `0.03 mm`，工程上可视为横向重合。

## 3.4 `camera_color_optical_frame` / `camera_depth_optical_frame`

这两个 frame 位于 D435 内部对应成像光学参考位置附近。

典型结构：

```text
base_link
└── camera_link
    ├── camera_color_frame
    │   └── camera_color_optical_frame
    └── camera_depth_frame
        └── camera_depth_optical_frame
```

光学 frame 通常采用：

```text
+z：向前
+x：向右
+y：向下
```

与 `base_link` 不同：

| Frame 类型 | +x | +y | +z |
|---|---|---|---|
| `base_link` | 前 | 左 | 上 |
| camera optical | 右 | 下 | 前 |

当前 raw-depth VLM 链使用：

```text
color pixel
→ color optical geometry
→ librealsense color→depth mapping
→ depth pixel
→ depth optical 3D
→ map
```

因此真正用于深度 3D 点的参考原点是：

```text
camera_depth_optical_frame
```

而不是 `camera_link`。

---

# 4. Go2 TF 树与物理位置总览

```text
                         map
                          │
                  SLAM Toolbox
                          │
                         odom
                          │
                    FAST-LIO
                          │
                     base_link
                   (机体参考点)
                 ┌────────┼───────────────┐
                 │        │               │
            body_imu  hesai_lidar    camera_link
                 │        │               │
           后 2.56 cm  前14.54 cm     前32.72 cm
           上 4.23 cm  上13.31 cm      上 4.30 cm
                                          │
                                RealSense 内部静态 TF
                                          │
                          ┌───────────────┴──────────────┐
                          │                              │
              camera_color_optical_frame    camera_depth_optical_frame
                   RGB 光学中心                  Depth 光学中心
```

---

# 5. Ranger 与 Go2 的核心区别

两台机器人的导航 TF 主干都是：

```text
map
└── odom
    └── base_link
```

区别主要在传感器层。

## Ranger

```text
map
└── odom
    └── base_link

FAST-LIO 侧还出现：
camera_init
body
```

其中 `body` 与 `camera_init` 带有更强的 FAST-LIO 内部坐标系属性。

## Go2

当前更明确地统一为：

```text
map
└── odom
    └── base_link
        ├── body_imu
        ├── hesai_lidar
        └── camera_link
```

因此 Go2 当前更适合直接围绕 `base_link` 统一处理：

- footprint；
- LiDAR 障碍；
- IMU；
- RGB-D；
- Nav2；
- VLM map projection。

---

# 6. 与 footprint / costmap 的关系

当前 Go2 costmap 改造中最关键的是：

```text
footprint 的坐标原点 = base_link
```

例如：

```yaml
footprint: >
  [[0.40, 0.23],
   [0.40,-0.23],
   [-0.40,-0.23],
   [-0.40,0.23]]
```

这里每个 `[x, y]` 都相对于 `base_link`：

```text
x > 0  → base_link 前方
x < 0  → base_link 后方
y > 0  → base_link 左边
y < 0  → base_link 右边
```

Nav2 再利用：

```text
map → odom → base_link
```

把整个 polygon footprint 放到地图中，与 OccupancyGrid / costmap 中的障碍做碰撞检查。

---

# 7. 建议现场确认的 TF

为了把本文从“工程记录”升级成“精确机械坐标说明”，可以分别在两台机器人运行时保存：

```bash
ros2 run tf2_tools view_frames
```

重点查看：

```bash
ros2 run tf2_ros tf2_echo map odom
ros2 run tf2_ros tf2_echo odom base_link
```

Go2：

```bash
ros2 run tf2_ros tf2_echo base_link body_imu
ros2 run tf2_ros tf2_echo base_link hesai_lidar
ros2 run tf2_ros tf2_echo base_link camera_link
ros2 run tf2_ros tf2_echo base_link camera_depth_optical_frame
```

Ranger：

```bash
ros2 run tf2_ros tf2_echo odom base_link
ros2 run tf2_ros tf2_echo base_link body
```

如果某条 TF 不存在，不应为了补全 TF 树而人为假设其为单位变换。
