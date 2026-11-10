# VLM_Nav：固定地图 + AMCL + EKF 导航迁移设计与实施计划

> 目标：将 Go2 当前“FAST-LIO + SLAM Toolbox 实时建图”的导航链迁移为“固定地图 + AMCL 全局定位 + EKF 局部里程计 + Nav2”，并继续支持现有 VLM 目标定位与导航。
>
> 原则：
> 1. TF ownership 唯一：同一条 TF 只能由一个模块发布。
> 2. 分阶段迁移：先替换 SLAM，再替换 odometry。
> 3. AMCL 定位 scan 与 costmap 障碍源解耦。
> 4. VLM 几何链保持不变，只更换底层 TF provider。
> 5. Fail-closed：任一定位链未通过验收时，不允许自动导航或 ARM。

---

现在待确定机器狗是否使用EKF还是保留FASTLIO用odometry，如果使用EKF则与小车后续方案统一并按照后面的设计步骤迁移修改。否则对计划进行修改。

## 两种方案的核心 trade-off

| 维度                     | Go2 保留 FAST-LIO 做 odometry  | Go2 改 onboard odom + IMU → EKF             |
| ------------------------ | ------------------------------ | ------------------------------------------- |
| 与 Ranger 底层实现一致性 | 较低                           | 高                                          |
| 对上层接口一致性         | **完全可以一致**               | 完全一致                                    |
| 当前真机验证程度         | **高，已经长期调试和动态验证** | 目前未知，需要重新验证                      |
| 位置漂移                 | 通常较小，LiDAR 提供环境约束   | 主要依赖 onboard odom，可能累计漂移         |
| yaw 稳定性               | 已有 LiDAR+IMU 约束            | 很依赖 onboard odom / IMU 质量              |
| 对 XT16 的依赖           | **有**                         | 可以摆脱 LiDAR odometry                     |
| CPU / 算力               | 较高                           | 较低                                        |
| 系统复杂度               | FAST-LIO 本身较复杂            | EKF 逻辑简单                                |
| 调参成本                 | 当前已经完成大部分             | 需要重新确定 EKF covariance / fusion config |
| AMCL 短时运动模型质量    | 大概率较好                     | 必须实验确认                                |
| 失败模式                 | LiDAR退化、点云/时间同步问题   | 足式里程计漂移、打滑、步态误差              |

# 1. 最终总体设计

## 1.1 数据流

```text
                         saved map.yaml / map.pgm
                                  │
                              map_server
                                  │
                                 /map
                                  │
               /scan_amcl ───────┤
                                  ↓
                                 AMCL
                                  │
                             map → odom
                                  │
             ┌────────────────────┴────────────────────┐
             │                                         │
      onboard odometry                             body IMU
             │                                         │
             └──────────────────┬──────────────────────┘
                                ↓
                         robot_localization
                              EKF
                                │
                         odom → base_link
                                │
                         ┌──────┼───────┐
                         │      │       │
                       XT16    D435   body_imu
                         │      │
                         │      └────────────→ VLM raw-depth
                         │
                         └→ /scan_amcl
```

VLM 与 Nav2：

```text
RGB
 ↓
VLM target pixel
 ↓
raw depth + CameraInfo + camera extrinsic
 ↓
3D point
 ↓
map TF
 ↓
目标 map pose
 ↓
Nav2 NavigateToPose
```

Nav2 costmap 第一阶段：

```text
saved /map
   ↓
StaticLayer
   ↓
InflationLayer
   ↓
polygon footprint collision checking
```

第一阶段不让当前 XT16 实时 point cloud 直接给 local costmap marking，以避免靠近障碍物时的丝状假回波污染 costmap。

---

# 2. 最终 TF 设计

```text
map
└── odom
    └── base_link
        ├── body_imu
        ├── hesai_lidar
        └── camera_link
            ├── camera_color_frame
            │   └── camera_color_optical_frame
            └── camera_depth_frame
                └── camera_depth_optical_frame
```

## 2.1 TF ownership

| TF | 唯一发布者 | 说明 |
|---|---|---|
| `map -> odom` | AMCL | 全局定位修正 |
| `odom -> base_link` | EKF | 连续局部里程计 |
| `base_link -> body_imu` | 静态 TF / URDF | 已标定 |
| `base_link -> hesai_lidar` | 静态 TF / URDF | 已标定 |
| `base_link -> camera_link` | 静态 TF / URDF | 已标定 |
| camera 内部 frames | RealSense / 静态 TF | 相机内部光学关系 |

禁止：

```text
SLAM Toolbox 同时发布 map→odom
FAST-LIO / adapter 与 EKF 同时发布 odom→base_link
```

---

# 3. 推荐仓库文件结构

```text
VLM_Nav/
├── config/
│   ├── amcl_go2.yaml
│   ├── ekf_go2.yaml
│   ├── nav2_go2_static.yaml
│   ├── amcl_scan_filter_go2.yaml
│   └── go2_calibration.yaml
│
├── launch/
│   ├── go2_localization.launch.py
│   ├── go2_navigation.launch.py
│   └── go2_vlm.launch.py
│
├── maps/
│   ├── <site>.yaml
│   └── <site>.pgm / <site>.png
│
├── scripts/
│   ├── manualnav2.sh
│   ├── stopnav2.sh
│   └── ...
│
└── test/
    ├── test_amcl_config.*
    ├── test_ekf_config.*
    ├── test_tf_ownership.*
    ├── test_static_map_readiness.*
    └── test_amcl_scan_readiness.*
```

文件名可以按现有仓库风格调整，但模块边界建议保持。

---

# 4. 实施策略

推荐分两阶段：

```text
阶段 A
固定地图 + AMCL
保留 FAST-LIO 提供 odom→base_link
        ↓
确认 AMCL 稳定

阶段 B
固定地图 + AMCL
EKF 替代 FAST-LIO 的 odom→base_link
        ↓
最终架构
```

不要同时更换 SLAM、odometry、costmap。


# 5. Step 0：冻结当前可工作的基线

## 执行前必须确定

无需新增设计决策，只确认：

- 当前 VLM raw-depth 已通过验收；
- 当前 Nav2 / bridge 已通过低速真机控制；
- 当前静态地图已保存；
- 当前实验环境与地图大体一致。

## 修改

不改代码。保存：

```text
git commit / tag
当前配置
当前地图
当前 TF 图
当前 topic list
当前参数 dump
```

建议：

```bash
ros2 run tf2_tools view_frames
ros2 topic list
ros2 node list
```

## 验收

必须能够回退到当前基线。

---

# 6. Step 1：确认固定地图是否适合作为 Nav2 障碍地图

## 执行前必须确定的设计

### 1. 使用哪一份地图

明确：

```text
maps/<site>.yaml
maps/<site>.pgm
```

要求：

- 与当前实验场地一致；
- 墙、桌椅等主要静态障碍完整；
- 没有明显由 XT16 丝状回波形成的虚假占用；
- resolution、origin 正确。

### 2. 第一阶段是否允许忽略动态障碍

推荐：

```text
StaticLayer only
```

这意味着地图建立后新增的人、椅子、箱子不会进入 costmap。

若不能接受，必须先设计新的动态障碍过滤链，不继续后续迁移。

## 修改

只读验证 `/map`。

## 验收

RViz 同时显示：

```text
/map
现有 obstacle cloud
```

确认：

```text
丝状假回波存在于实时点云
但没有固化进 /map
```

若 `/map` 已污染：

```text
STOP
```

先重建/清理地图。

---

# 7. Step 2：设计并验证专用 `/scan_amcl`

AMCL 不能直接假设现有 `/scan` 可用。

## 执行前必须确定的设计

### 1. AMCL scan 从哪里生成

推荐：

```text
/lidar_points
   ↓
TF 到 base_link
   ↓
专用 self / height / range filter
   ↓
pointcloud_to_laserscan
   ↓
/scan_amcl
```

不建议直接复用：

```text
/vlm_nav/obstacle_cloud
```

因为它是为 costmap 障碍预处理设计的，不应与定位输入耦合。

### 2. 过滤参数

写配置前先实测：

- 地面在 `base_link` 下的 z；
- 机身/腿部自反射点 x/y/z 范围；
- 真正墙面/家具点的典型高度；
- 最小有效 range；
- 最大有效 range。

再确定：

```text
min_height
max_height
range_min
range_max
self_crop box
```

禁止凭感觉先写死。

### 3. 是否需要额外 outlier filtering

默认先不增加。

只有 `/scan_amcl` 仍有明显孤立 beam / 丝状结构时，再决定是否增加：

```text
median / radius / temporal filtering
```

## 修改

新增独立 `/scan_amcl` 生成链，AMCL 只订阅它。

## 验收

静止和靠近墙体时：

- `/scan_amcl` 与静态地图墙面基本重合；
- 不出现明显机器狗与墙之间的丝状假障碍；
- 无大量自反射；
- timestamp 单调；
- 频率稳定；
- TF 可转换到 `base_link`。

若 scan-map 明显错配：

```text
STOP
```

不要启动 AMCL。

---

# 8. Step 3：固定地图 + AMCL，暂时保留 FAST-LIO odometry

第一阶段：

```text
map_server
   ↓
 /map
   ↓
 AMCL → map→odom

FAST-LIO
   ↓
odom→base_link
```

## 执行前必须确定的设计

### 1. AMCL 初始位姿策略

选择其一：

A. 每次人工用 RViz `2D Pose Estimate`  
B. 保存固定启动位姿

当前推荐 A。

### 2. AMCL motion model

确认：

- 是否允许 `vy`；
- bridge 是否仍强制 `vy=0`。

若 `vy=0`，第一版按平面近似 differential model 配置。

### 3. AMCL sensor model

第一版推荐：

```text
likelihood_field_prob
```

beam skipping 只作为鲁棒性补充，不能用来掩盖错误 `/scan_amcl`。

## 修改

新增：

```text
config/amcl_go2.yaml
launch/go2_localization.launch.py
```

启动：

```text
map_server
AMCL
```

停用：

```text
SLAM Toolbox
```

继续保留 FAST-LIO 的：

```text
odom→base_link
```

## TF ownership

```text
map→odom       AMCL
odom→base_link FAST-LIO
```

## readiness 修改

删除实时 SLAM 依赖。

固定 `/map` 不再要求 2 秒内重复更新，只要求：

- 至少成功收到；
- metadata 合法；
- map_server lifecycle ACTIVE。

新增：

```text
amcl_active
amcl_pose_received
map_to_odom_tf_available
scan_amcl_fresh
```

## 验收

只读：

- map_server ACTIVE；
- AMCL ACTIVE；
- `/map` 正常；
- `/scan_amcl` 正常；
- `map→odom` 唯一发布；
- `odom→base_link` 唯一由 FAST-LIO 发布。

人工遥控短移动：

- AMCL 粒子保持收敛；
- `/amcl_pose` 合理；
- `map→odom` 不异常跳变；
- scan 与 map 持续对齐。

未通过前禁止进入 EKF 迁移。


# 9. Step 4：确定 EKF 输入设计

必须在写 `ekf_go2.yaml` 前完成。

## 执行前必须回答的设计问题

### 1. Go2 的里程计具体用哪个 topic

列出候选：

```bash
ros2 topic list | grep -Ei 'odom|sport|state'
```

然后：

```bash
ros2 topic info <topic> -v
ros2 topic echo <topic> --once
```

必须明确：

- message type；
- pose 是否有效；
- twist 是否有效；
- frame_id；
- child_frame_id；
- covariance 是否可信；
- 更新频率；
- 是否由 FAST-LIO 派生。

最终 EKF odometry 输入应尽量独立于 FAST-LIO。

### 2. EKF 使用 pose、twist，还是二者

不能默认全开。

实测：

- onboard odometry `vx` 是否稳定；
- `vy` 是否应固定为 0；
- yaw / wz 哪个更可靠；
- pose 是否跳变；
- covariance 是否有意义。

建议优先考虑：

```text
平面速度 + yaw rate
```

若 onboard pose 质量足够，再考虑 pose。

### 3. IMU 融合哪些量

当前 `/body_imu` 已验证，但 2D EKF 不盲目融合全部 6DoF。

明确：

- 是否只使用 `wz`；
- 是否使用 yaw orientation；
- orientation covariance 是否有效；
- 是否需要 differential / relative。

第一版优先：

```text
IMU wz
+
可靠 planar odometry
```

而不是直接融合绝对 yaw。

### 4. FAST-LIO 是否保留作为 diagnostic

推荐：

```text
可以继续运行用于对比
但 publish_tf=false
且不能重复向 EKF 注入同一 IMU 派生信息
```

---

# 10. Step 5：实现 EKF `odom→base_link`

## 前提

Step 4 的四项设计已有实测结论。

## 修改

新增：

```text
config/ekf_go2.yaml
```

基本框架：

```yaml
frequency: 30.0
two_d_mode: true

map_frame: map
odom_frame: odom
base_link_frame: base_link
world_frame: odom

publish_tf: true
```

`odom0_config`、`imu0_config` 必须根据 Step 4 填写。

## 切换 TF ownership

从：

```text
odom→base_link = FAST-LIO
```

改为：

```text
odom→base_link = EKF
```

确保 FAST-LIO / adapter 不再发布该 TF。

## 验收

静止：

- TF 连续；
- 无 timestamp rollback；
- 静止漂移可接受；
- yaw 不持续发散。

人工运动：

```text
短直行
原地左转
原地右转
停止
```

检查：

- 位移方向正确；
- yaw 符号正确；
- 速度方向正确；
- 无明显跳变；
- 停止后速度快速回零。

FAST-LIO 可作为 reference，但不能做同一 TF owner。

---

# 11. Step 6：AMCL + EKF 联合验收

最终：

```text
map→odom       AMCL
odom→base_link EKF
```

## 执行前必须确定的设计

### 1. EKF 误差是否在 AMCL 可校正范围内

比较：

```text
EKF-only odom trajectory
vs
AMCL global pose
```

若 EKF 短距离就严重漂移，先修 EKF。

### 2. 是否需要针对 Go2 步态调 AMCL motion noise

Go2 会出现：

- 小幅横摆；
- 横向摆动；
- 非轮式纯旋转。

如果粒子在每次迈步时过度扩散，再调：

```text
alpha1
alpha2
alpha3
alpha4
alpha5
```

不得提前硬写。

## 验收

- `map→odom` 连续；
- `odom→base_link` 连续；
- `/amcl_pose` 持续有效；
- 回到已知位置时全局误差可接受；
- 无双 TF owner；
- AMCL 不因近墙假点明显跳变。

通过后才置：

```text
LOCALIZATION_READY=true
```

---

# 12. Step 7：Nav2 costmap 改为固定地图主导

## 执行前必须确定的设计

### 1. 第一阶段是否完全禁用动态 obstacle layer

推荐 YES，但要求：

- 场地封闭；
- 测试期间无人员/移动物体进入；
- `/map` 足够完整。

### 2. footprint 尺寸

必须确认：

- Go2 机身长度；
- 宽度；
- 正常步态腿部最大外扩；
- safety padding。

不要只用机身壳体矩形。

### 3. inflation radius

不要直接设 0。

根据：

```text
map resolution
定位误差
footprint padding
```

确定小安全余量。第一版可从 5–10 cm 数量级开始，再通过近墙测试定最终值。

## 修改

Global costmap：

```text
StaticLayer
InflationLayer
```

Local costmap：

```text
StaticLayer
InflationLayer
```

删除/禁用：

```text
VoxelLayer ← /vlm_nav/obstacle_cloud
```

保留：

```text
polygon footprint
DWB ObstacleFootprint critic
```

## 验收

不 ARM：

- footprint 与地图障碍关系合理；
- global path 不穿墙；
- local trajectory 不发生 footprint collision；
- 原丝状假点位置不再生成虚假高代价带。

---

# 13. Step 8：修改 readiness / supervisor

## 执行前必须确定的设计

建议固定新的 readiness 分层：

```text
LOCALIZATION_READY
NAV_READY
VLM_INPUT_READY
VLM_API_READY
AUTONOMY_READY
CONTROL_ARMED
```

定义：

```text
LOCALIZATION_READY
=
map_server active
AND AMCL active
AND amcl pose valid
AND map→odom available
AND EKF odom→base_link fresh
AND /scan_amcl fresh

NAV_READY
=
LOCALIZATION_READY
AND planner/controller/costmap lifecycle active

VLM_INPUT_READY
=
现有 raw-depth 输入链 ready

VLM_API_READY
=
真实 VLM API heartbeat ready

AUTONOMY_READY
=
NAV_READY
AND VLM_INPUT_READY
AND VLM_API_READY
AND depth_units_verified
```

`CONTROL_ARMED` 独立。

## 修改

删除旧：

```text
SLAM Toolbox lifecycle gate
/map freshness <= N 秒
FAST-LIO-specific readiness
```

替换为：

```text
map_available
map_server_active
amcl_active
amcl_pose_fresh
map_to_odom_tf
ekf_odom_fresh
odom_to_base_link_tf
scan_amcl_fresh
```

静态 `/map` 不可作为周期 heartbeat。

---

# 14. Step 9：确认 VLM 几何链无需重写

## 执行前必须确定

只确认：

```text
map → camera_depth_optical_frame
```

在 depth snapshot 时间戳可查询。

## 修改

原则上不改 raw-depth 投影：

```text
color pixel
→ official librealsense color→depth mapping
→ raw depth
→ depth optical 3D
→ map TF
```

变化只在 TF provider：

```text
旧：SLAM + FAST-LIO
新：AMCL + EKF
```

## 验收

重复已验证的单点投影：

- target pixel；
- depth pixel；
- metric depth；
- map point。

静止和人工短移动后均检查。

---

# 15. Step 10：Nav2 只读与短距离闭环

## 执行前必须满足

```text
LOCALIZATION_READY=true
NAV_READY=true
VLM_INPUT_READY=true
bridge=DISARMED
control_armed=false
```

## 只读测试

RViz：

```text
2D Pose Estimate
Nav2 Goal
```

只检查：

- AMCL；
- global path；
- local trajectory；
- footprint；
- costmap。

不 ARM。

## 真机短距离

选择：

```text
0.5–0.8 m
明显空旷区域
```

流程：

```text
ARM
→ 确认 ARMED
→ 单一 NavigateToPose
→ 观察 EKF / AMCL / costmap
→ Stop / DISARM
```

禁止自动 retry。

---

# 16. Step 11：VLM 自动导航闭环

## 前提

```text
depth_units_verified=true
VLM_API_READY=true
VLM_INPUT_READY=true
LOCALIZATION_READY=true
NAV_READY=true
AUTONOMY_READY=true
```

再人工：

```text
ARM
```

确认：

```text
CONTROL_ARMED=true
```

最后：

```text
enabled=true
```

## 第一轮测试范围

只做：

- 单目标；
- 静态场地；
- 短路径；
- 无动态人员；
- 不测试狭窄通道。

记录：

```text
VLM snapshot
target map point
AMCL pose
EKF odom
global path
local trajectory
costmap
Sport request
```

---

# 17. 后续：恢复动态障碍能力

不属于第一轮迁移。

固定地图 + AMCL + EKF + VLM 稳定后，再设计：

```text
StaticLayer
+
filtered dynamic obstacle layer
+
InflationLayer
```

执行前重新确定：

- XT16 丝状回波来源；
- 能否稳定过滤；
- 动态障碍层使用 PointCloud2 还是 LaserScan；
- clearing source；
- marking source；
- obstacle height；
- self-filter；
- 是否独立于 `/scan_amcl`。

原则：

> AMCL scan 与 dynamic obstacle input 使用独立 topic 和独立过滤策略，不再次把定位与避障耦合。

---

# 18. 最终验收矩阵

| 模块 | 必须通过的证据 |
|---|---|
| Fixed map | 地图干净、与现场一致 |
| `/scan_amcl` | 近墙无明显丝状假 scan、与 map 对齐 |
| AMCL | `map→odom` 唯一且稳定 |
| EKF | `odom→base_link` 唯一且稳定 |
| TF | 无 duplicate owner |
| Static costmap | 不再被实时丝状点云污染 |
| Footprint | 与静态障碍碰撞检查正确 |
| Nav2 | 短距离闭环通过 |
| VLM raw-depth | 已验证链保持有效 |
| VLM API | heartbeat 有效 |
| Autonomy | 仅所有 gate 为真时允许 enable |

---

# 19. 推荐执行顺序摘要

```text
Step 0  冻结当前基线
   ↓
Step 1  验证固定地图是否干净
   ↓
Step 2  设计并验证 /scan_amcl
   ↓
Step 3  map_server + AMCL + 保留 FAST-LIO odom
   ↓
       AMCL 稳定后才能继续
   ↓
Step 4  实测并确定 EKF 输入设计
   ↓
Step 5  EKF 替代 FAST-LIO 的 odom→base_link
   ↓
Step 6  AMCL + EKF 联合定位验收
   ↓
Step 7  costmap 切换为 StaticLayer + footprint
   ↓
Step 8  修改 readiness / supervisor
   ↓
Step 9  回归验证 VLM map 投影
   ↓
Step 10 Nav2 只读 + 短距离闭环
   ↓
Step 11 VLM 自动导航闭环
   ↓
后续    再恢复经过严格过滤的 dynamic obstacle layer
```

---

# 20. 当前最先要确定的两个设计问题

开始改代码前，先回答：

1. **固定地图 `/map` 是否干净，不包含 XT16 丝状假障碍？**目前验证发现可以在人工操纵机器狗建图时清除丝状假障碍造成的栅格占用，证据观测自Rviz.
2. **Go2 最终给 EKF 使用的独立 onboard odometry topic 是什么，其 pose/twist/covariance 是否可信？**
3. 

其中第 2 项不阻塞 Step 1–3，因为第一阶段仍可保留 FAST-LIO 提供 `odom→base_link`。

因此第一批修改只做到：

```text
clean fixed map
+
/scan_amcl
+
map_server
+
AMCL
+
FAST-LIO odometry
```

验证通过后，再进入 EKF 替换阶段。
