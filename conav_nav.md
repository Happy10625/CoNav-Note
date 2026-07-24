这个仓库实际上包含两套导航链路：

1. 当前正在开发的 `co_nav2_nav`：使用 YOLO-World + MobileSAM 识别目标，FAST_LIO/SLAM Toolbox 建图，前沿算法或目标位置决定目标位姿，再把目标交给 Nav2。
2. 原始 Co-NavGPT2：直接把 RGB-D 转成点云地图，用 GPT-4V 给多个机器人分配探索前沿，用 FMM 算局部方向，最后产生前进/左转/右转离散动作。

从当前代码完整性和 ROS 2 集成情况看，实际机器人更建议按第一套理解。

## 一、当前 `co_nav2_nav` 的总体数据流

```text
RGB 图像 ──→ YOLO-World 检测框 ──→ MobileSAM 分割掩码
                                           │
对齐深度图 + CameraInfo ───────────────────┤
                                           ↓
                               相机坐标目标点 (x,y,z)
                                           │ TF
                                           ↓
                                  map 坐标目标位置
                                           │
                                           ↓
                               生成目标周围接近位姿
                                           │
                                      Nav2 路径验证
                                           ↓
                               NavigateToPose / Spin
                                           ↓
                             Nav2 Controller → /cmd_vel
```

建图是另一条并行数据流：

```text
Livox 点云
   ↓
FAST_LIO：位姿估计、点云配准
   ↓ /cloud_registered_body
pointcloud_to_laserscan
   ↓ /scan
SLAM Toolbox
   ↓ /map (OccupancyGrid)
SemanticExplorer
   ↓
前沿检测 → 探索目标位姿 → Nav2
```

也就是说，当前版本不是“仅从图片直接形成地图”。图片主要负责语义目标识别；导航占据栅格地图主要来自激光雷达。

---

## 二、如何从图像识别目标

主要代码位于：

- [semantic_explorer.py](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/co_nav2_nav/semantic_explorer.py:630)
- [robot.yaml](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/config/robot.yaml:10)

### 1. RGB、深度图同步

在 [semantic_explorer.py:140](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/co_nav2_nav/semantic_explorer.py:140) 附近订阅：

- `/camera/color/image_raw`
- `/camera/aligned_depth_to_color/image_raw`
- `/camera/color/camera_info`

RGB 和深度通过：

```python
self.sync = ApproximateTimeSynchronizer(
    [self.rgb_sub, self.depth_sub], 10, 0.10
)
self.sync.registerCallback(self.on_rgbd)
```

合并为一次 `on_rgbd(rgb_message, depth_message)` 调用。

### 2. YOLO 找目标框，SAM 得到像素级区域

模型初始化在 [semantic_explorer.py:630](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/co_nav2_nav/semantic_explorer.py:630)：

```python
self.yolo = YOLO(self.p.yolo_model_path).to(self.p.model_device)
self.yolo.set_classes([self.p.target_object])
self.sam = SAM(self.p.sam_model_path).to(self.p.model_device)
```

例如 `target_object: chair` 时，YOLO-World 只搜索 chair。

推理代码在 [semantic_explorer.py:662](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/co_nav2_nav/semantic_explorer.py:662)：

```python
results = self.yolo.predict(
    image,
    conf=float(self.p.detection_confidence),
    verbose=False
)
boxes = results[0].boxes.xyxy

sam_result = self.sam.predict(
    image,
    bboxes=boxes,
    verbose=False
)[0]
```

流程是：

1. YOLO 输出检测框、类别和置信度。
2. 选择置信度最高的框。
3. MobileSAM 把框细化成目标掩码。
4. 掩码与深度图相交，只保留属于目标的有效深度像素。

### 3. 从目标像素计算三维坐标

核心反投影在 [semantic_explorer.py:680](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/co_nav2_nav/semantic_explorer.py:680)：

```python
z = float(np.median(z_values))
u = float(np.median(cols[near]))
v = float(np.median(rows[near]))

fx, fy = self.camera_info.k[0], self.camera_info.k[4]
cx, cy = self.camera_info.k[2], self.camera_info.k[5]

camera_point = (
    (u - cx) * z / fx,
    (v - cy) * z / fy,
    z
)
```

使用针孔相机模型：

\[
X=(u-c_x)Z/f_x,\quad
Y=(v-c_y)Z/f_y,\quad
Z=depth
\]

代码使用中值深度，并只保留距离中值小于 0.15 m 的点，用于减小 SAM 掩码边缘混入背景造成的误差。

### 4. 从相机坐标变换到地图坐标

在 [semantic_explorer.py:699](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/co_nav2_nav/semantic_explorer.py:699)：

```python
transform = self.tf_buffer.lookup_transform(
    self.p.global_frame,
    self.p.camera_frame,
    Time.from_msg(depth_message.header.stamp),
    timeout=Duration(seconds=0.2)
)

point = rotate_vector(transform.transform.rotation, camera_point)
point += translation
```

变换关系大致是：

```text
camera_color_optical_frame
          ↓
      camera_link
          ↓
      base_link
          ↓
        odom
          ↓
         map
```

相机相对机器人的安装位置在 [semantic_exploration.launch.py](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/launch/semantic_exploration.launch.py:60) 中定义。

### 5. 多帧确认

[semantic_explorer.py:712](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/co_nav2_nav/semantic_explorer.py:712) 不会看到一帧就立刻追踪，而是要求：

- 连续 `confirm_frames` 帧，默认 3 帧；
- 检测位置之间不超过 `confirmation_radius`，默认 0.35 m；
- 最终取多帧位置中值。

```python
self.confirm_positions.append(point)

if len(self.confirm_positions) < self.p.confirm_frames:
    return

center = np.median(np.asarray(self.confirm_positions), axis=0)
self.target_position = tuple(center)
self.set_state(TARGET_CONFIRMED)
self.cancel_goal(publish_stop=True)
```

确认目标后，会取消当前探索目标，先停住机器人，然后转入接近目标状态。

---

## 三、地图是如何形成的

主要文件：

- [fastlio_mapping_2d.launch.py](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/launch/fastlio_mapping_2d.launch.py:1)
- [slam_toolbox.yaml](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/config/slam_toolbox.yaml:1)
- [semantic_explorer.py](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/co_nav2_nav/semantic_explorer.py:211)

### 1. FAST_LIO 提供定位和配准点云

FAST_LIO 使用 Livox 点云和 IMU 估计机器人位姿，并发布：

- `/Odometry`
- `/cloud_registered`
- `/cloud_registered_body`
- 相应 TF

`/cloud_registered_body` 是当前扫描在机器人/传感器运动坐标系下的点云，适合 Nav2 障碍物层和激光扫描转换。

### 2. 三维点云转换成二维 LaserScan

[fastlio_mapping_2d.launch.py](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/launch/fastlio_mapping_2d.launch.py:10)：

```python
Node(
    package="pointcloud_to_laserscan",
    executable="pointcloud_to_laserscan_node",
    remappings=[
        ("cloud_in", "/cloud_registered_body"),
        ("scan", "/scan"),
    ],
    parameters=[{
        "target_frame": "base_link",
        "min_height": 0.05,
        "max_height": 1.50,
        "range_min": 0.50,
        "range_max": 20.0,
    }],
)
```

它截取离地 0.05～1.50 m 的点，投影为二维 `/scan`。

### 3. SLAM Toolbox 形成 OccupancyGrid

[slam_toolbox.yaml](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/config/slam_toolbox.yaml:10) 配置：

```yaml
odom_frame: odom
map_frame: map
base_frame: base_link
scan_topic: /scan
mode: mapping
resolution: 0.05
```

SLAM Toolbox 综合：

- `/scan`
- `odom → base_link` 位姿
- 扫描匹配和回环检测

形成 `/map`，类型为 `nav_msgs/OccupancyGrid`。

栅格通常表示为：

- `-1`：未知区域；
- `0`：空闲区域；
- 较大的正数：占用/障碍物。

### 4. SemanticExplorer 接收地图

[semantic_explorer.py:211](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/co_nav2_nav/semantic_explorer.py:211)：

```python
def on_map(self, message):
    self.map_message = message
    self.grid = np.asarray(
        message.data,
        dtype=np.int16
    ).reshape(message.info.height, message.info.width)
```

之后所有前沿搜索都在 `self.grid` 上执行。

---

## 四、没有发现目标时，如何确定探索方向

主要文件：

- [navigation_algorithms.py](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/co_nav2_nav/navigation_algorithms.py:1)
- [semantic_explorer.py](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/co_nav2_nav/semantic_explorer.py:265)

当前 ROS 2 版本没有使用 GPT/VLM 决定方向，而是使用确定性的前沿探索算法。

### 1. 首先原地扫描

`scan_first=true` 时，会生成一圈均匀角度：

```python
def scan_yaws(initial_yaw, steps):
    return [
        initial_yaw + 2.0 * math.pi * (index + 1) / steps
        for index in range(steps)
    ]
```

默认 `scan_steps=8`，即每次约转 45°，通过 Nav2 的 `Spin` Action 执行。

### 2. 找到“已知—未知”的边界

[navigation_algorithms.py:61](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/co_nav2_nav/navigation_algorithms.py:61) 首先从机器人所在栅格做 BFS，只保留与机器人连通的空闲区域。

然后把满足以下条件的空闲格标记为 frontier：

```python
reachable free cell
    并且
至少一个四邻域格子的值为 UNKNOWN(-1)
```

相关代码：

```python
if any(
    grid[ny, nx] == UNKNOWN
    for nx, ny in _neighbors4(x, y, width, height)
):
    frontier[y, x] = True
```

接着把相邻 frontier 聚成连通簇，并选择靠近簇中心的实际可行栅格作为候选目标。

### 3. 前沿评分

[navigation_algorithms.py:107](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/co_nav2_nav/navigation_algorithms.py:107)：

```python
score = len(cluster["cells"]) - 0.35 * cluster["distance_cells"]
```

含义是：

- 前沿越长，潜在未知信息越多，得分越高；
- 到机器人的 BFS 距离越远，代价越大。

在 `tick()` 中，候选前沿按这个分数排序，随后依次交给 Nav2 验证；第一个可以规划出路径的前沿成为探索方向。

---

## 五、发现目标后，如何确定接近方向

目标确认后，系统不会直接向目标中心冲过去，而是在目标周围生成一圈“停靠位姿”。

[navigation_algorithms.py:116](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/co_nav2_nav/navigation_algorithms.py:116)：

```python
x = object_x + radius * cos(angle)
y = object_y + radius * sin(angle)
yaw = atan2(object_y - y, object_x - x)
```

每个候选位姿包含：

```text
(x, y, yaw)
```

其中：

- `(x, y)` 是机器人底盘应该到达的位置；
- `yaw` 使机器人到达后朝向目标；
- 候选点按离机器人当前位置的距离排序。

当前配置的接近半径为：

```text
target_clearance + robot_front_extent - margin
= 0.50 + 0.36 - 0.05
= 0.81 m
```

这样底盘中心距目标约 0.81 m，扣除机器人前部 0.36 m，机器人前沿距离目标约 0.45～0.50 m。

候选位置不会由 `standoff_candidates()` 自己判断障碍物，而是逐一发送给 Nav2 的 `ComputePathToPose`：

```python
goal = ComputePathToPose.Goal()
goal.goal.pose.position.x = pose[0]
goal.goal.pose.position.y = pose[1]
```

只有 Nav2 成功规划出路径、并且路径没有越出限定区域时，才正式执行。

---

## 六、如何产生移动指令

当前版本分成两层。

### 上层：产生目标位姿

在 [semantic_explorer.py:485](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/co_nav2_nav/semantic_explorer.py:485)：

```python
goal = NavigateToPose.Goal()
goal.pose.header.frame_id = "map"
goal.pose.pose.position.x = x
goal.pose.pose.position.y = y
goal.pose.pose.orientation = yaw_quaternion(yaw)

self.navigator.send_goal_async(goal)
```

上层输出的不是“左轮多少、右轮多少”，而是地图坐标下的目标位姿。

原地转动使用 [semantic_explorer.py:509](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/co_nav2_nav/semantic_explorer.py:509) 的 `Spin.Goal`：

```python
goal = Spin.Goal()
goal.target_yaw = relative_yaw
self.spinner.send_goal_async(goal)
```

### 下层：Nav2 产生速度

Nav2 根据：

- 全局路径；
- 局部代价地图；
- 机器人当前位姿；
- 障碍物；
- 速度和加速度限制；

持续计算 `geometry_msgs/Twist`，最终发布到 `/cmd_vel`。

速度限制主要在：

- [nav2_open_space.yaml](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/config/nav2_open_space.yaml:56)
- [nav2_overrides.yaml](/home/isee-cdh/ws/Co-NavGPT2/co_nav2_nav/config/nav2_overrides.yaml:61)

例如受控测试配置：

```yaml
max_vel_x: 0.10
max_vel_theta: 0.25
acc_lim_x: 0.20
acc_lim_theta: 0.40
```

`SemanticExplorer` 自己只在取消、失败或关闭时直接向 `/cmd_vel` 发布零速度；正常运动速度由 Nav2 Controller 产生。

---

## 七、状态是如何传递的

核心状态机定义在 `semantic_explorer.py` 顶部：

```text
SEARCHING
   │ 目标连续确认
   ↓
TARGET_CONFIRMED
   │ 找到合法接近路径
   ↓
APPROACHING
   │ 到达且目标最近仍可见
   ↓
SUCCEEDED

任意关键超时、TF 丢失、规划失败
   ↓
FAILED
```

状态通过 `/semantic_explorer/state` 发布，前沿、目标点和导航目标通过 `/semantic_explorer/markers` 发布，方便在 RViz 中检查。

---

## 八、原始 Co-NavGPT2 的数据流

如果你指的是仓库根目录的论文实现，而不是新增的 `co_nav2_nav`，其核心入口是：

- [main.py](/home/isee-cdh/ws/Co-NavGPT2/main.py:118)：Habitat 仿真主循环
- [ros_multi_nav.py](/home/isee-cdh/ws/Co-NavGPT2/ros_multi_nav.py:205)：原始多机器人实机循环
- [vlm_agents.py](/home/isee-cdh/ws/Co-NavGPT2/agents/vlm_agents.py:209)：仿真感知、点云和动作
- [ros2_agents.py](/home/isee-cdh/ws/Co-NavGPT2/agents/ros2_agents.py:150)：实机多机器人 Agent
- [ros2_single_agent.py](/home/isee-cdh/ws/Co-NavGPT2/agents/ros2_single_agent.py:143)：实机单机器人 Agent

它的流程是：

```text
RGB + Depth + 相机位姿
       ↓
YOLO-World + MobileSAM
       ↓
完整场景点云 point_sum + 目标点云 object_pcd
       ↓
点云高度切片
       ↓
obstacle_map / explored_map / top_view_map
       ↓
前沿检测
       ↓
GPT-4V 为每个机器人选择 frontier
       ↓
FMM 距离场 → 短期目标 stg
       ↓
角度差
       ↓
0停止 / 1前进 / 2左转 / 3右转
       ↓
ZMQ speedctl 指令
```

### 原始目标识别

[detection_segmentation.py](/home/isee-cdh/ws/Co-NavGPT2/utils/detection_segmentation.py:31)：

```python
YOLO('yolov8l-world.pt')
SAM('mobile_sam.pt')
```

输出 `xyxy`、`confidence`、`class_id` 和 `mask`。

### 原始 RGB-D 点云地图

[explored_map_utils.py:14](/home/isee-cdh/ws/Co-NavGPT2/utils/explored_map_utils.py:14) 将所有有效深度反投影成三维点云。

[explored_map_utils.py:159](/home/isee-cdh/ws/Co-NavGPT2/utils/explored_map_utils.py:159) 按高度切片：

- 指定高度范围内的点形成 `obstacle_map`；
- 摄像机可观察到的点形成 `explored_map`；
- 每格最高点颜色形成 `top_view_map`。

多个机器人的 `point_sum` 在 [ros_multi_nav.py:281](/home/isee-cdh/ws/Co-NavGPT2/ros_multi_nav.py:281) 合并后生成统一地图。

### GPT 分配探索方向

[chat_utils.py:37](/home/isee-cdh/ws/Co-NavGPT2/utils/chat_utils.py:37) 为每个前沿制作一张候选地图，把前沿标成红色并标出机器人位置。

[chat_utils.py:109](/home/isee-cdh/ws/Co-NavGPT2/utils/chat_utils.py:109) 将候选地图编码为 Base64，连同目标名称发送给视觉语言模型。

模型返回类似：

```json
{
  "robot_0": "frontier_2",
  "robot_1": "frontier_0"
}
```

[main.py:159](/home/isee-cdh/ws/Co-NavGPT2/main.py:159) 或 [ros_multi_nav.py:306](/home/isee-cdh/ws/Co-NavGPT2/ros_multi_nav.py:306) 再将 `frontier_2` 转回对应的栅格坐标。

要注意：VLM 只负责高层“去哪一个前沿”，不负责底层转向和速度控制。

### FMM 决定局部方向

[fmm_planner.py](/home/isee-cdh/ws/Co-NavGPT2/utils/fmm_planner.py:39) 在可通行地图上建立到目标的距离场。

`get_short_term_goal()` 在机器人周围找距离下降最快的位置，输出短期目标 `stg_x, stg_y`。

随后 [ros2_agents.py:324](/home/isee-cdh/ws/Co-NavGPT2/agents/ros2_agents.py:324) 比较：

```python
目标方向角 = atan2(stg_x-current_x, stg_y-current_y)
相对角 = 机器人航向 - 目标方向角
```

并离散化：

```python
if relative_angle > turn_angle:
    action = 3       # 右转
elif relative_angle < -turn_angle:
    action = 2       # 左转
else:
    action = 1       # 前进
```

### 原始实机移动指令

[ros_multi_nav.py:332](/home/isee-cdh/ws/Co-NavGPT2/ros_multi_nav.py:332)：

```python
action == 1 → speedctl speed|0.3|0.0|0.0
action == 2 → speedctl speed|0.0|0.0|0.5
action == 3 → speedctl speed|0.0|0.0|-0.5
```

这些是：

```text
前向速度 | 横向速度 | 角速度
```

通过 ZMQ 发给机器人的底层控制程序。

---

## 九、需要特别注意的代码现状

- 当前 `co_nav2_nav` 路径没有调用 GPT/VLM，方向由前沿评分和 Nav2 路径规划决定。
- 根目录的原始 Co-NavGPT2 才使用 GPT 给机器人分配前沿。
- 原始单机器人 ROS 代码真正的运动指令走 ZMQ；虽然创建了 `/robot_action` 的 `Twist` 发布器，但 [ros_single_nav.py:275](/home/isee-cdh/ws/Co-NavGPT2/ros_single_nav.py:275) 中 `vel_msg` 没有填入速度，所以发布的是零 Twist。
- 原始代码将目标名称直接写成 `"person"`，位置在 [ros2_single_agent.py:155](/home/isee-cdh/ws/Co-NavGPT2/agents/ros2_single_agent.py:155) 和 [ros_multi_nav.py:162](/home/isee-cdh/ws/Co-NavGPT2/ros_multi_nav.py:162)；当前 Nav2 版本则从 `robot.yaml` 的 `target_object` 参数读取。
- 当前 Nav2 版本的数据接口、停止保护、目标多帧确认和路径验证更加清楚，适合继续作为实机主链路。
