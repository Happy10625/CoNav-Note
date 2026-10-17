# Go2 生成候选 VLM 启动指引

更新：2026-10-15。当前是 Go2 单机找目标并接近；不启动 Ranger、coordinator 或 Domain40 桥。
控制电脑使用 Bash，目录 `/home/isee-pst/unitree_ros2/VLM_Nav`，本地域 Domain0 / enp4s0。
已正常运行的组件直接复用；任一步失败停在该步。启动运动须有明确授权及现场急停人员。
详细配置/排障见 [runbook](/home/isee-pst/unitree_ros2/VLM_Nav/docs/multi_agent/go2_runbook.md)。

终端：A＝相机 SSH，1＝底层，2＝RViz，3＝Sport 转换，4＝检查/探索。
下列 source 自动进入仓库、加载当前安装；不要随后 source 旧 overlay。

## 1．终端 A：检查并启动相机

作用：确认已有相机，避免重复驱动。输入：Go2 网络已连接。

```bash
source /home/isee-pst/unitree_ros2/VLM_Nav/CoVLM_env.bash
ros2 topic info /camera/camera/color/image_raw --verbose
ros2 topic info /camera/camera/depth/image_rect_raw --verbose
```

预期：两路各有唯一真实发布者；后续还须通过 RGB 持续刷新及 RGB-D 输入检查，话题存在不等于数据新鲜。
已有正常相机跳过下面命令；没有相机且旧进程/USB已释放时才启动：

```bash
bash "$REPO/scripts/go2_camera_ssh.sh"
```

输入：需要时提供 SSH 登录凭据。脚本连接 `unitree@192.168.123.18`，在 Go2 上位机执行
640×480×15 RGB/深度、同步开启、对齐深度关闭的相机命令。
预期：`RealSense Node Is Up`；终端 A 保持运行。连接失败或重复发布者先排障，不再启动一份。

## 2．终端 1：仅冷启动时做传感器预检

已有正常底层跳到第4步。冷启动前让 Go2 按原手动流程站稳，预检和定位初始化期间保持静止。
作用：检查真实机身输入，确认临时预检不会与已有驱动冲突。

```bash
source /home/isee-pst/unitree_ros2/VLM_Nav/CoVLM_env.bash
ros2 topic info /lowstate --verbose
ros2 topic info /lidar_points --verbose
ros2 topic info /body_imu --verbose
```

预期：`/lowstate`有真实发布者；冷启动时后两路无发布者或话题尚不存在。已有驱动不要叠加预检。
输入：相机已运行、Go2站稳、急停可用；生成本次新报告：

```bash
mkdir -p "$REPO/build/go2-field"
export GO2_PREFLIGHT_REPORT="$REPO/build/go2-field/preflight.$(date +%Y%m%d_%H%M%S).json"
test ! -e "$GO2_PREFLIGHT_REPORT" && bash "$REPO/scripts/run_go2_preflight.sh"
```

预期：约30秒后 `healthy: True`、`PASS: temporary sensor processes stopped`。
失败不启动底层；同名报告已存在则重新取时间，不覆盖。

## 3．终端 1：预检成功后启动底层，保持运行

作用：启动雷达/IMU、FAST-LIO、地图/AMCL、Nav2及安全监督。
输入：同一终端中的新鲜预检报告（600秒内）；`start_bridge:=false`留给终端3单独启动速度接口。

```bash
ros2 launch vlm_nav go2_system.launch.py \
  sensor_preflight_report:="$GO2_PREFLIGHT_REPORT" \
  sensor_preflight_config:="$REPO/config/go2_preflight_xt16.yaml" \
  calibration_file:="$REPO/config/go2_calibration_xt16.yaml" \
  spark_config_file:="$REPO/config/spark_fast_lio_go2_xt16.yaml" \
  target_stage:=nav2 localization_mode:=amcl \
  map:="$REPO/maps/lab_rear120_20261001_IwQjMX/lab.yaml" \
  amcl_scan_topic:=/scan start_bridge:=false \
  costmap_overrides_file:="$GO2_EXPLORE_CONFIG/nav2_go2_cooperative_costmap.yaml"
```

预期：加载实验地图；等待初始位姿时进入第4步，定位成立后继续启动Nav2。
启动报错或退出先排障，不继续ARM。

2026-10-15更新：Go2协同全局/局部膨胀半径改为0.45米，衰减系数仍为5.0。
配置由上面的 `costmap_overrides_file` 在终端1启动时读取；仅重开终端4不会更新运行中的Nav2。
当前底层仍运行时，先结束实验并按第10步确认停稳、DISARM，再结束终端1；
按第2～3步刷新过期预检并重启底层。相机可保持运行，桥接不要重复启动；定位/Nav2未就绪时不得ARM。
在终端2完成定位、Nav2启动后，用终端4按顺序核对（自动退出）：

```bash
source /home/isee-pst/unitree_ros2/VLM_Nav/CoVLM_env.bash
timeout 10 ros2 param get /global_costmap/global_costmap inflation_layer.inflation_radius
timeout 10 ros2 param get /local_costmap/local_costmap inflation_layer.inflation_radius
```

两条均须输出 `Double value is: 0.45`，否则停止后续ARM/实验并核对终端1加载的配置。
停靠和接近允许普通膨胀代价1～252，仍拒绝253～255、未知/越界及失效输入；
RViz灰色还可能表示未知，不能按颜色一律放行。减小膨胀不等于放宽0.81米到达判据。

## 4．终端 2：RViz及初始位姿，保持运行

```bash
source /home/isee-pst/unitree_ros2/VLM_Nav/CoVLM_env.bash
rviz2 -d "$REPO/config/go2_exploration.rviz"
```

作用：显示地图、灰黑costmap/障碍云、车体、生成候选、VLM选点和1 Hz RGB预览。
输入：仅冷启动且AMCL未初始化时，工具栏“+”添加 `2D Pose Estimate`，在 `/initialpose`
设置机器人真实 base_link 位置和朝向；已有有效定位不重置。
预期：地图/costmap显示OK。Go2 live RGB (1 Hz preview)订阅 `/vlm_nav/camera_preview`，仅终端4的inspect/探索运行期间刷新；入口退出后停止刷新，不代表相机驱动停止。不要改回相机原始RGB话题，额外订阅已在只读对照中触发RGB-D失效。新策略运行后橙点为本轮可选点，灰点为非可选点，
绿色箭头为VLM选择；旧模式探索点不显示。打开RViz本身不计算候选或运动。

## 5．终端 3：唯一 Sport 速度转换，保持运行

作用：Nav2速度转Go2 Sport请求；这是本地速度接口，不是跨机DDS桥。
先检查已有节点：

```bash
source /home/isee-pst/unitree_ros2/VLM_Nav/CoVLM_env.bash
ros2 node list --no-daemon
```

已有 `/twist_to_go2_sport_bridge`且为当前版本才复用。2026-10-15首次切换：先结束实验并确认机器人停稳，在旧终端3按Ctrl+C退出旧桥接，再重新source本文件所列环境；不要同时启动两个桥接。

新终端3先核对安装：

```bash
ros2 pkg prefix vlm_nav
```

预期：`$GO2_BRIDGE_OUTPUT/install/vlm_nav`（go2-manual-takeover-20261015）；不匹配先处理环境。确认没有旧桥接后执行：

```bash
ros2 run vlm_nav twist_to_go2_sport_bridge --ros-args \
  --params-file "$REPO/config/go2_bridge.yaml" -p dry_run:=false
```

预期：新实例为DISARMED。此步不ARM、不发送探索目标。

两次实验之间可用遥控器调整位置：外部Sport请求会让桥接退出ARMED并让出控制，不锁存FAULT、不发送StopMove覆盖遥控；CONTROL_ARMED变false。调整完释放遥控并静默至少2秒，确认停稳后按第8步重新ARM。若实验尚未结束，接管会取消当前任务，之后须新开一次实验；不自动续跑。其他原因的FAULT仍按原流程处理。

## 6．终端 4：检查配置及现场输入

作用：确认新策略配置与实际输入。每条通过才执行下一条；均自动退出。
2026-10-15切换接近距离预算版本（保留检出即结束扫描）：先结束终端4旧实验并确认停稳，再执行下面的source；相机、终端1/2/3可保持运行。已有进程不会随文件修改自动更新。

```bash
source /home/isee-pst/unitree_ros2/VLM_Nav/CoVLM_env.bash
ros2 pkg prefix multi_agent_nav
```

预期：`$REPO/build/go2-arrival-budget-20261015/install/multi_agent_nav`；不匹配先处理环境。

作用：只读核对Nav2到达参数；输入：终端1的Nav2已运行，机器人停稳。仍在终端4执行，命令自动退出：

```bash
timeout 10 ros2 param get /controller_server general_goal_checker.xy_goal_tolerance
timeout 10 ros2 param get /planner_server GridBased.tolerance
```

预期依次为 `0.25`、`0.5`；超时或值不一致先核对环境/终端1加载配置，不继续ARM。
本轮未修改这两个Nav2参数，无需为本次更新重启终端1。
程序在接近前再次异步读取实际容差和map/base_link配置；读取失败停止。
停车点须满足“规划路径终点到目标＋实际控制容差＋0.03米余量≤0.81米”，
当前对应终点距离≤0.53米，同时通过原碰撞/路径检查。没有合格点会停止，不强行靠近。
不再以0.89米提前停止接近；进入0.81米后仍须停稳复核，停稳后距离才是最终成功判据。
实验 `events.jsonl` 的 `APPROACH_CANDIDATE_CHECK`、`APPROACH_STOPPED`、`ARRIVAL_VERIFIED`
记录请求点、规划终点、停稳点及各自到目标距离；不改善距离或已落入Nav2容差的重试不发送。


```bash
ros2 run multi_agent_nav multi_agent_go2_check --offline --require-ready \
  --config-dir "$GO2_EXPLORE_CONFIG" --strategy generated_candidates_vlm
```

预期：退出0、`single_robot_experiment_gates=[]`；不初始化ROS。
当前扫描从初始朝向起，每次顺时针45°，最多8次；每次停稳后等待当前VLM回复，期间不旋转。当前A=灭火器、B=水杯、C=篮子；完整双机 `live_gates` 未通过，不改标记解锁。

```bash
timeout 10 ros2 topic echo /vlm_nav/nav_ready std_msgs/msg/Bool \
  --once --filter 'm.data' --qos-reliability reliable \
  --qos-durability transient_local --no-daemon
```

预期：`data: true`；超时先处理Nav2阶段，不ARM。

```bash
ros2 run multi_agent_nav multi_agent_go2_check --action inspect --require-ready \
  --config-dir "$GO2_EXPLORE_CONFIG" --strategy generated_candidates_vlm --timeout 10
```

预期：退出0，`active_map_matches`、`localization_valid`、`health.stopped`、`costmap_valid`、
`rgbd_ready`均为true。DISARMED时 `health.nav_ready`可为false；全局候选空间/路径由探索入口再查。

## 7．终端 4：检查API配置

输入：沿用已有有效密钥、endpoint、model环境变量；不要把密钥写进本文或命令历史。
作用：只检查变量存在，不调用API、不打印值。

```bash
/home/isee-pst/venv/co-nav-real/bin/python - <<'PYAPI'
import os
assert os.getenv('DASHSCOPE_API_KEY') or os.getenv('OPENAI_API_KEY'), '缺API密钥'
assert os.getenv('DASHSCOPE_BASE_URL') or os.getenv('OPENAI_BASE_URL') or os.getenv('DASHSCOPE_WORKSPACE_ID'), '缺endpoint'
assert os.getenv('DASHSCOPE_MODEL') or os.getenv('OPENAI_MODEL'), '缺model'
print('API_ENV_CONFIGURED=OK')
PYAPI
```

预期：`API_ENV_CONFIGURED=OK`；缺失则先配置，重新检查后再继续。

## 8．终端 4：按状态ARM

输入：已获运动授权，Go2站稳、急停人员在场，其他上层目标owner已退出，外部Sport请求静默至少2秒。
先读取状态（自动退出）：

```bash
timeout 10 ros2 topic echo /vlm_nav/go2_bridge_state std_msgs/msg/String \
  --once --qos-reliability reliable --qos-durability transient_local --no-daemon
```

ARMED跳到第9步；DISARMED只执行ARM；FAULT先消除故障、确认静止，再执行reset：

```bash
timeout 10 ros2 service call /twist_to_go2_sport_bridge/reset_fault std_srvs/srv/Trigger '{}'
```

仅reset返回 `success: true`、DISARMED后，或本来就是DISARMED时执行：

```bash
timeout 10 ros2 service call /twist_to_go2_sport_bridge/arm std_srvs/srv/Trigger '{}'
```

预期：`success: true`、ARMED。无状态、reset或ARM失败均停止，不盲目连续调用。

## 9．终端 4：执行一次探索并接近

终端A、1、2、3保持运行。输入：第6～8步已通过；`--target`为当前A目标描述，B/C沿用scene配置。

```bash
ros2 run multi_agent_nav multi_agent_go2_check \
  --config-dir "$GO2_EXPLORE_CONFIG" --action explore --allow-motion \
  --strategy generated_candidates_vlm --target '灭火器' \
  --approach-target --timeout 300
```

作用：生成/筛选候选→双图VLM选ID→导航/停稳→逐方向旋转识别ABC。A未检出才继续下一方向；A检出立即结束扫描，有效位置经原安全/路径检查后进入接近闭环，不补扫余下方向。
预期：RViz出现候选及绿色选点；完整成功为 `TARGET_APPROACHED`、`stop_confirmed=true`，
且 `evidence_write_failed=false`、`vlm_evidence_pending=false`。
`EXHAUSTED`仅表示当前视角已检查完，`WAITING_VIEWPOINTS`表示候选暂不可达/观察失败，均不判目标不存在。
到点不等于观察完成；提前检出也不把整点记为已观察。A检出但无有效位置时以 `TARGET_DETECTED_UNLOCATED` 停止；API/图像/旋转失败或健康异常停止本轮，不继续选点或旋转。看到 `observation_failed` 后仍自动换点/旋转，先停止并核对第6步版本。运行至退出，或Ctrl+C进入取消/停止流程。

不传 `--output-dir`，资料自动写入 `$REPO/build/go2-vlm-experiments/experiment.<时间>.<ID>/`。
`selection/`存每轮双图、请求/返回/解析；`vlm/`存每方向实际JPEG、请求/返回及标注图；
`events.jsonl`、`result.json`存执行结果。最多保留10个托管实验，删除最旧非活跃包；旧日志/bag不删。
外部自定义 `--output-dir`不参与此清理；需要10次限制就沿用上面的默认命令。

## 10．终端 4：确认停止后DISARM

输入：动作/取消终态及实际停车已确认；否则先现场急停、排障，不重启或删运动锁。

```bash
timeout 10 ros2 service call /twist_to_go2_sport_bridge/disarm std_srvs/srv/Trigger '{}'
```

预期：`success: true`、DISARMED。需继续实验可保持底层；结束整套流程时再依次Ctrl+C关闭
本次启动的终端3、2、1，最后关闭本次启动的相机终端A，已有相机按原方式管理。

文档命令已按当前入口/安装核对并检查语法；本次未执行SSH、ROS启动、API、ARM或运动。

