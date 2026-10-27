# Go2 的 VLM_Nav 协同指引（1020）

更新：2026-10-20。适用电脑：Go2 控制电脑，账户 `isee-pst`，交互式 Bash。
仓库：`/home/isee-pst/unitree_ros2/VLM_Nav`。编写时分支 `go2-cooperative-task-layer`，HEAD `6a786c1`；空地候选及独立C修改尚未提交。

本文按当前源码启动脚本编写。原指定 `/home/isee-pst/Notes/VLM_Nav初步启动指引.md` 已不在原位置，
实际参考同目录的 [0910 初步启动指引](VLM_Nav初步启动指引_0910.md) 和 [1018 单侧指引](协同单侧VLM启动指引_1018.md)。
其中旧地图、旧单机使能方式不作为本次协同入口。

## 0．先看当前可执行范围

**已实现：**Go2 与公共任务层复用本地 VLM 执行核心，fake Ranger 验证流程；正式协同入口独立于单机入口。
**尚未完成：**Ranger 实际 adapter 接入、两端真实联合任务验收及相关验证项。
**空地探索已实现：**家具标签可省略；从已知自由区域生成网格候选，有有效家具标注时合并家具周围点。
源码 `scene.enabled=false`；资源多边形和退出点已不作为门槛。Go2 `vision_validated`、`path_source_verified`、
`peer_obstacle_verified` 仍为 false。完整 live gates 当前不为空，不能直接运行真实 A/B→C 任务。

当前可先做第2～3节的安装/配置核对，或在通信授权范围内按第4节做 PAUSED 通信检查。
第5～12节是条件满足后的正式现场顺序，不是宣称现在已具备启动条件。
只改标记为true、填零坐标或接fake Ranger，均不能替代真实前置验证。

本文只是操作说明。编写本文没有启动ROS、SSH、相机、桥接、采集、模型请求、ARM或机器人运动。
任一步失败停在该步；只复用已核实健康的现有组件，不叠加第二套。

## 1．协同结构与入口选择

Go2 控制电脑运行 coordinator、RulePlanner 和 Go2 agent；Ranger 控制电脑只运行自己的 agent。
各机器人保留自己的地图、定位、相机、Nav2及adapter。

```text
Go2本机Domain0 / enp4s0
  coordinator + Go2 task agent + Go2感知/Nav2
                  ↕ Go2定向bridge
         共享Domain40 / 两端Wi-Fi
                  ↕ Ranger定向bridge
Ranger本机Domain0 / Ranger自己的本地域网卡
  Ranger task agent + Ranger感知/Nav2
```

任务：Go2找A（当前灭火器），Ranger找B（当前水杯）→各自接近成功READY→双方READY进入C阶段→
各自使用本机C缓存或继续找C→找到的一方独立接近/模拟放入→双方完成且停稳→DONE。
C坐标仅在本机保存，线上仅报CACHED引用；无共同C绑定，无跨地图坐标转换。
不再设置门/篮子保护区、不申请资源许可、不规定C先后顺序，也不执行固定EXIT。
完成后停在各自C接近位置；没有任务层互斥，运动继续依赖各端Nav2避障。

| 入口 | 用途 | 本文是否用于正式协同 |
|---|---|---|
| `scripts/start_go2_vlm.sh` | Go2单机准备、探索并接近 | 否；不能与协同agent同时运行 |
| `scripts/VLMNav-go.sh` / `manualnav2.sh` | 旧单机/手动流程，包含预检、录包或运动 | 否；不叠加启动 |
| `scripts/start_go2_agent.sh` | 旧里程计state转发 | 否；不代表新任务agent接入 |
| `scripts/start_multi_agent_bridge.sh` | 旧`multi_agent_msgs` state桥 | 否；不是本轮五话题任务桥 |
| `scripts/check_go2_comm.sh` | 默认环境下的PAUSED通信入口 | 默认会重新加载1018安装；本指引直接调用其底层Python脚本保留1020环境 |
| `go2_cooperative.launch.py` | coordinator＋Go2新任务agent | 是；不启动底层、Ranger、桥或ARM |

正式协同不用 `scripts/arm.sh`，也不对旧 `/vlm_nav` 设置 `enabled=true`。
协同任务由 `multi_agent_start_task start` 启动，Sport ARM另行执行。

## 2．终端分工与统一环境

| 终端 | 工作 | 是否保持运行 |
|---|---|---|
| A | 必要时SSH启动Go2上位机相机 | 是 |
| 1 | 冷启动预检，然后Go2传感器/FAST-LIO/地图/AMCL/Nav2 | launch后保持 |
| 2 | RViz与初始位姿 | 是 |
| 3 | Go2本地Sport速度转换 | 是 |
| 4 | 新任务Domain0↔40定向bridge | 是 |
| 5 | Go2 coordinator＋task agent；PAUSED检查时只开阻塞agent | 是 |
| 6 | 配置/输入检查、ARM、任务start/pause及结果检查 | 有限命令自动退出 |

Go2控制电脑每个相关新终端先执行以下环境块；工作目录会进入仓库。
此块只加载环境，不启动节点，但会核对Go2本地域网络条件并创建日志目录。

```bash
source /home/isee-pst/unitree_ros2/VLM_Nav/CoVLM_env.bash
```

只有source成功才继续下面一块；失败先处理它报告的网卡、地址或缺失环境文件。

```bash
source /home/isee-pst/unitree_ros2/VLM_Nav/CoVLM_env.bash
export GO2_TASK_OUTPUT="$REPO/build/go2-independent-c-20261020"
source "$GO2_TASK_OUTPUT/install/local_setup.bash"
export GO2_CONFIG="$REPO/cooperative_ws/src/multi_agent_nav/config"
export LIVE_CONFIG_DIR="$GO2_CONFIG"
export COOPERATIVE_RUNTIME_PYTHON=/home/isee-pst/venv/co-nav-real/bin/python
unset COMM_ENV_FILE
cd "$REPO"
ros2 pkg prefix multi_agent_nav
ros2 pkg prefix vlm_nav
```

预期两个prefix分别为：

```text
/home/isee-pst/unitree_ros2/VLM_Nav/build/go2-independent-c-20261020/install/multi_agent_nav
/home/isee-pst/unitree_ros2/VLM_Nav/build/go2-manual-takeover-20261015/install/vlm_nav
```

`CoVLM_env.bash`原默认协同包仍为`go2-approach-coverage-20261018`；上面的第二次source才选择1020独立C包（包含空地候选）。
旧`go2-local-execution-20261020`和`go2-free-space-20261020`安装均不含本次取消许可/顺序改动。
后面不要再source旧overlay或运行会重载旧环境的单机启动器；新终端要重复环境块。
若1020安装不存在或与源码不匹配，先按仓库[runbook构建与核对节](/home/isee-pst/unitree_ros2/VLM_Nav/docs/multi_agent/go2_runbook.md#2026-10-20-取消保护区与独立c执行最新)处理。
完整构建命令只在runbook维护，本文不另存一套。

## 3．终端6：安装与完整协同配置检查（不初始化ROS）

输入：第2节环境已成功加载。执行目录为仓库，下面子Shell临时切到/tmp，避免源码遮蔽安装。
命令自动退出，不调用API、不启动节点。

```bash
(
cd /tmp || exit 1
"$COOPERATIVE_RUNTIME_PYTHON" - <<'PY'
import hashlib
import importlib
import os
from pathlib import Path
from ament_index_python.packages import get_package_prefix
from multi_agent_nav.config import load_config, live_gates
repo=Path(os.environ['REPO'])
prefix=Path(os.environ['GO2_TASK_OUTPUT'])/'install/multi_agent_nav'
assert Path(get_package_prefix('multi_agent_nav'))==prefix
for name in ('agent','agent_node','runner','coordinator','coordinator_node','planner','models','config',
             'frame_adapter','go2_exploration','generated_candidates','go2_check','adapters.go2'):
    module=importlib.import_module('multi_agent_nav.'+name)
    actual=Path(module.__file__).resolve()
    source=repo/'cooperative_ws/src/multi_agent_nav/multi_agent_nav'/(name.replace('.','/')+'.py')
    assert actual.is_relative_to(prefix), str(actual)
    assert hashlib.sha256(actual.read_bytes()).digest()==hashlib.sha256(source.read_bytes()).digest(),name
print('TASK_INSTALL=OK')
config=load_config(os.environ['LIVE_CONFIG_DIR'])
assert config['scene'].get('share_c_coordinates') is False
errors=live_gates(config,local_robot='go2')
for error in errors: print('BLOCKED:',error)
print('COOPERATIVE_GATES=' + ('OPEN' if not errors else 'CLOSED'))
raise SystemExit(1 if errors else 0)
PY
)
```

版本核对预期`TASK_INSTALL=OK`。当前真实配置预期`COOPERATIVE_GATES=CLOSED`、退出1，列出缺项；
这表示正确阻止正式任务，不是允许ARM的成功结果。此时可按第4节继续独立PAUSED通信检查，
不要进入第5～12节正式现场流程。待真实补齐并审查配置后，重跑须OPEN且退出0。

本模式不要求Ranger→Go2数值地图对齐；仍要求各端地图身份/摘要和自身真实验证有效；不要求资源几何或固定退出点。
家具文件未配置、不存在或合法家具列表为空，均不再阻止空地点生成；已有坏文件、摘要或身份不符仍报错。
不自动创建/伪造家具标签。网格间距为max(1m,2×完整旋转半径)，向上取整至地图分辨率；
每轮按当前位置由近到远筛选，最多12个安全候选交给VLM。当前地图静态约518点，不等于实时可达数或要求全部走完。
`multi_agent_go2_check --offline --require-ready`只检查单机门槛，不能替代这里的完整协同检查。

## 4．可选：仅做PAUSED新任务通信检查

这是单独分支；执行它时不ARM、不start、不启真实运动adapter。两端完整live gates必须真实非空。
按需具备通信授权后执行；Ranger需同步新任务消息和公共代码，并在其电脑运行对应环境/脚本。
PAUSED模式不需要启动相机/雷达来证明运动能力，也不提供任何运动验收结论。

终端6（第2节环境，仓库目录）先执行，自动退出：

```bash
"$COOPERATIVE_RUNTIME_PYTHON" scripts/check_multi_agent_comm.py --side go2 preflight --config-dir "$LIVE_CONFIG_DIR"
```

预期`PREFLIGHT_OK`，记录并与Ranger比对三个消息schema摘要、两端实际安装路径、网卡和路由。
此命令只读配置/本机网络，不初始化ROS；失败先处理输出，不进入bridge/agent。

终端4加载第2节环境，然后执行，保持运行：

```bash
"$COOPERATIVE_RUNTIME_PYTHON" scripts/check_multi_agent_comm.py --side go2 bridge --config-dir "$LIVE_CONFIG_DIR"
```

终端5加载第2节环境，然后执行，保持运行：

```bash
"$COOPERATIVE_RUNTIME_PYTHON" scripts/check_multi_agent_comm.py --side go2 agent --config-dir "$LIVE_CONFIG_DIR"
```

预期agent为PAUSED且附真实配置阻塞原因，不创建live运动adapter。Ranger也按其通信指引启动桥和阻塞agent。
双方都运行后，终端6执行，自动退出：

```bash
"$COOPERATIVE_RUNTIME_PYTHON" scripts/check_multi_agent_comm.py --side go2 check --config-dir "$LIVE_CONFIG_DIR"
```

预期`DATA_OK`；Ranger也须在其接收端得到DATA_OK。它只证明阻塞态状态传输，不证明READY、定位、C或任务成功。
如需停流检查，仅在该PAUSED分支使用`check --expect-peer-stop`，等接收端提示后人工退出对端agent；
两端不要同时停agent，先前初始无消息也不能记为停流通过。

通信检查结束，在原终端正常退出这次阻塞agent。进入正式流程前确认没有它残留。
桥若继续复用，必须核对同一五话题配置、DDS和唯一实例。完整gates变空后该检查脚本会拒绝运行，
不能修改真实配置制造阻塞；届时桥按第9节直接启动，agent按第10节正式入口启动。

## 5．正式现场前置条件与相机（终端A）

**以下步骤仅供第3节OPEN、Ranger已完成本机adapter接入及所需现场授权后执行。**
Go2、XT16、上位机、D435供电正常；急停操作者在场。网络地址运行前核实，历史Go2上位机为192.168.123.18。
相机/定位使用的时钟须先同步，运行中不突然校时；失败恢复方法参照0910指引，不临时添加诊断订阅。

终端A加载第2节环境，先检查（自动退出）：

```bash
ros2 topic info /camera/camera/color/image_raw --verbose
ros2 topic info /camera/camera/depth/image_rect_raw --verbose
```

各有唯一且健康的真实发布者则复用；后续第8节仍要验证新鲜RGB-D。只有确实没有相机且旧进程/USB已释放时，
才能执行以下脚本；它会SSH到Go2上位机启动相机，保持终端A运行：

```bash
bash scripts/go2_camera_ssh.sh
```

预期`RealSense Node Is Up`；参数为RGB/深度640×480×15、enable_sync=true、align_depth=false。
重复发布者或残留进程先回原终端处理，不叠加驱动。

## 6．终端1：冷启动传感器预检和底层

输入：已获相应现场/预检授权，Go2按既有现场姿态流程保持稳定静止，传感器与网络正常。
加载第2节环境，先检查（自动退出）：

source /home/isee-pst/unitree_ros2/VLM_Nav/CoVLM_env.bash
export GO2_TASK_OUTPUT="$REPO/build/go2-independent-c-20261020"
source "$GO2_TASK_OUTPUT/install/local_setup.bash"
export GO2_CONFIG="$REPO/cooperative_ws/src/multi_agent_nav/config"
export LIVE_CONFIG_DIR="$GO2_CONFIG"
export COOPERATIVE_RUNTIME_PYTHON=/home/isee-pst/venv/co-nav-real/bin/python
unset COMM_ENV_FILE
cd "$REPO"
ros2 pkg prefix multi_agent_nav
ros2 pkg prefix vlm_nav

```bash
ros2 topic info /lowstate --verbose
ros2 topic info /lidar_points --verbose
ros2 topic info /body_imu --verbose
ros2 topic info /odometry --verbose
```

已有完整健康底层则复用，直接到第7节；不能仅凭话题名字判定健康。
冷启动须`/lowstate`有唯一真实发布者，lidar/body_imu没有现存驱动。
只启动了一部分时先回原终端排障，不重复预检或启动第二套。

冷启动时同一终端生成新报告，命令约30秒后退出，会临时启动传感器并采样：

```bash
mkdir -p "$REPO/build/go2-field"
export GO2_PREFLIGHT_REPORT="$REPO/build/go2-field/preflight.$(date +%Y%m%d_%H%M%S).json"
test ! -e "$GO2_PREFLIGHT_REPORT" && bash scripts/run_go2_preflight.sh
```

预期`healthy: True`和`PASS: temporary sensor processes stopped`；失败不启动下一步。
通过后同一终端、600秒有效期内启动；此命令保持运行：

```bash
ros2 launch vlm_nav go2_system.launch.py \
  sensor_preflight_report:="$GO2_PREFLIGHT_REPORT" \
  sensor_preflight_config:="$REPO/config/go2_preflight_xt16.yaml" \
  calibration_file:="$REPO/config/go2_calibration_xt16.yaml" \
  spark_config_file:="$REPO/config/spark_fast_lio_go2_xt16.yaml" \
  target_stage:=nav2 localization_mode:=amcl \
  map:="$REPO/maps/lab_rescan_20261018_155656_0pa6gm/lab.yaml" \
  amcl_scan_topic:=/scan start_bridge:=false \
  costmap_overrides_file:="$LIVE_CONFIG_DIR/nav2_go2_cooperative_costmap.yaml"
```

该入口启动传感器、FAST-LIO、地图/AMCL、Nav2及安全监督；`start_bridge=false`把Sport转换留给终端3。
当前标定文件已含相机外参，底层会处理其TF，不再手动叠加static_transform_publisher。
1018旧文档中的`lab_rear120...`已停用，本次使用上面的`lab_rescan_20261018_155656_0pa6gm`。
若按新现场配置更换地图，须同步map_path/digest/身份；若使用家具标注也须同步其地图绑定，之后重新验证，不只改launch中的路径。

## 7．终端2/3：RViz、定位和唯一Sport接口

终端2加载第2节环境，执行并保持运行：

source /home/isee-pst/unitree_ros2/VLM_Nav/CoVLM_env.bash
export GO2_TASK_OUTPUT="$REPO/build/go2-independent-c-20261020"
source "$GO2_TASK_OUTPUT/install/local_setup.bash"
export GO2_CONFIG="$REPO/cooperative_ws/src/multi_agent_nav/config"
export LIVE_CONFIG_DIR="$GO2_CONFIG"
export COOPERATIVE_RUNTIME_PYTHON=/home/isee-pst/venv/co-nav-real/bin/python
unset COMM_ENV_FILE
cd "$REPO"
ros2 pkg prefix multi_agent_nav
ros2 pkg prefix vlm_nav

```bash
rviz2 -d "$REPO/config/go2_exploration.rviz"
```

地图和costmap正常；仅AMCL未初始化时，用2D Pose Estimate设置真实base_link位置/朝向，已有有效定位不重置。
预览保持`/vlm_nav/camera_preview`，不要改订阅原始RGB或增加额外完整点云诊断。
候选图/请求证据以第12节文件为准，不把单机入口特有的候选显示作为协同agent启动成功判据。

终端3加载第2节环境，先查节点（自动退出）：

```bash
ros2 node list --no-daemon
```

已有唯一且版本正确的`/twist_to_go2_sport_bridge`才复用。确认没有后，执行并保持运行：

```bash
ros2 run vlm_nav twist_to_go2_sport_bridge --ros-args \
  --params-file "$REPO/config/go2_bridge.yaml" -p dry_run:=false
```

预期初始DISARMED；这只是Go2本地速度接口，不是Domain40网络桥。此步不ARM、不发任务。

## 8．终端6：配置、现场输入和API检查

输入：相机、底层、RViz、Sport接口均正常，机器人停稳；此时不要启动单机探索或旧vlm_nav自主导航。
第2节环境下逐项执行，均自动退出；任何失败先排障。

source /home/isee-pst/unitree_ros2/VLM_Nav/CoVLM_env.bash
export GO2_TASK_OUTPUT="$REPO/build/go2-independent-c-20261020"
source "$GO2_TASK_OUTPUT/install/local_setup.bash"
export GO2_CONFIG="$REPO/cooperative_ws/src/multi_agent_nav/config"
export LIVE_CONFIG_DIR="$GO2_CONFIG"
export COOPERATIVE_RUNTIME_PYTHON=/home/isee-pst/venv/co-nav-real/bin/python
unset COMM_ENV_FILE
cd "$REPO"
ros2 pkg prefix multi_agent_nav
ros2 pkg prefix vlm_nav

先重新执行第3节，确认仍为OPEN，然后检查Nav2参数：

```bash
timeout 10 ros2 param get /global_costmap/global_costmap inflation_layer.inflation_radius
timeout 10 ros2 param get /local_costmap/local_costmap inflation_layer.inflation_radius
timeout 10 ros2 param get /controller_server general_goal_checker.xy_goal_tolerance
timeout 10 ros2 param get /planner_server GridBased.tolerance
```

当前应依次为0.45、0.45、0.25、0.5；与已审查现场参数不符先查实际加载配置，不现场猜测调参。

```bash
ros2 run multi_agent_nav multi_agent_go2_check --action inspect --require-ready \
  --config-dir "$LIVE_CONFIG_DIR" --strategy generated_candidates_vlm --timeout 10
```

这条命令初始化只读ROS观察器，不是纯离线检查。预期退出0且`active_map_matches`、
`health.localization_valid`、`health.stopped`、`costmap_valid`、`rgbd_ready`、`depth_units_verified`均为true。
退出0本身不保证所有RGB-D字段都通过，须同时读报告；DISARMED时`health.nav_ready=false`可预期。
结束后观察器应退出，再启动正式agent，避免额外相机订阅。

API变量仅检查存在，不打印值、不调用模型：

```bash
"$COOPERATIVE_RUNTIME_PYTHON" - <<'PY'
import os
assert os.getenv('DASHSCOPE_API_KEY') or os.getenv('OPENAI_API_KEY'), '缺API密钥'
assert os.getenv('DASHSCOPE_BASE_URL') or os.getenv('OPENAI_BASE_URL') or os.getenv('DASHSCOPE_WORKSPACE_ID'), '缺endpoint'
assert os.getenv('DASHSCOPE_MODEL') or os.getenv('OPENAI_MODEL'), '缺model'
print('API_ENV_CONFIGURED=OK')
PY
```

预期`API_ENV_CONFIGURED=OK`。Ranger需在自己的环境独立满足对应配置。

## 9．终端4：正式任务定向bridge

输入：两端任务版本/消息语义一致、实际网卡正常、无旧/重复任务桥；第4节已开的同一正确bridge可复用。
正式gates已经OPEN时，不再用只允许阻塞态的check脚本启动。
终端4加载第2节环境，仅在确实未运行该桥时执行，保持运行：

```bash
unset ROS_DOMAIN_ID
export CYCLONEDDS_URI="file://$REPO/config/cyclonedds_go2_multi_agent_bridge.xml"
ros2 run domain_bridge domain_bridge "$LIVE_CONFIG_DIR/bridge_go2_pending.yaml"
```

该终端专供bridge；不再用它运行普通Domain0节点。XML明确Domain0=enp4s0、Domain40=wlo1；
不要替换成仅本地域的`cyclonedds_go2.xml`。Ranger须在其电脑启动互补的定向bridge。

只桥接五话题：Go2 state/observation/command由Go2 0→40；Ranger state/observation由Go2桥40→0。
不桥接TF、图像、costmap、速度或Nav2 action，旧`/multi_agent/agents/*/state`不是新任务状态。

## 10．终端5：coordinator＋Go2正式task agent

输入：第3/8节通过，无第4节PAUSED agent残留，无单机目标owner；Ranger真实agent已按其本机指引接入。
终端5加载第2节环境，执行并保持运行：

```bash
ros2 launch multi_agent_nav go2_cooperative.launch.py config_dir:="$LIVE_CONFIG_DIR"
```

它只启动Go2 coordinator和Go2 task agent，不启动Ranger、桥、相机、底层或Sport ARM。
启动后尚无task，保持IDLE；若出现`Live start blocked`或`Live adapter not activated`，停止后续操作。
修改配置不会热更新已创建的adapter/缓存门槛，应先安全结束该上层进程，再按流程重新启动。

## 11．终端6：ARM、核对双机健康、显式开始任务

输入：现场运动授权有效；双方已停稳、急停操作者就位、Go2遥控/Sport外部请求静默至少2秒。
终端6加载第2节环境，先读取Sport状态，命令自动退出：

```bash
timeout 10 ros2 topic echo /vlm_nav/go2_bridge_state std_msgs/msg/String \
  --once --field data --no-daemon --qos-reliability reliable --qos-durability transient_local
```

若DISARMED，在输入、定位和监督均正常后仅调用一次ARM：

```bash
timeout 10 ros2 service call /twist_to_go2_sport_bridge/arm std_srvs/srv/Trigger '{}'
```

预期`success: true`并确认ARMED/control_armed=true。已ARMED则不重复调用；FAULT先按原现场排障查清原因，
本文不提供自动reset/retry。无状态或ARM失败不继续。Ranger按自身控制接口处理使能，不能套Go2 Sport服务。

读取双方新任务状态，逐条执行、各自动退出：

```bash
timeout 10 ros2 topic echo /multi_agent/go2/state multi_agent_task_msgs/msg/AgentState \
  --once --no-daemon --qos-reliability reliable --qos-durability volatile
timeout 10 ros2 topic echo /multi_agent/ranger/state multi_agent_task_msgs/msg/AgentState \
  --once --no-daemon --qos-reliability reliable --qos-durability volatile
```

开始前两端须是simulation=false、正确robot_id/地图身份、持续新鲜的状态，localization_valid/nav_ready/stopped均true，
不存在STOPPING或PAUSED；旧资源/token字段保留为空，不作为许可使用。一次echo不能证明持续新鲜，coordinator还会检查接收心跳。
私有模式的common_frame_id/alignment_id为空，pose_valid=false、common_pose零是协议预期，
不要据此发布假的pose_valid或改回共享坐标；本地定位有效看localization_valid。

仅这些条件全部成立后，同一终端执行一次；这一步会下发可运动任务：

```bash
ros2 run multi_agent_nav multi_agent_start_task start --scenario lab
```

预期`accepted=true`并返回非空task_id。拒绝则看reason，停止在当前步骤；不要循环start或用fake对端解锁。
`accepted=true`仅表示任务被接受，不是READY或任务完成。

## 12．终端6：监视、完成判据、正常暂停与退出

任务监视命令会持续运行，按Ctrl+C只结束本次显示；它不暂停任务：

```bash
ros2 topic echo /multi_agent/coordinator/status std_msgs/msg/String --field data --no-daemon
```

预期SEARCH_AB→SEARCH_C→DEPOSIT→DONE；Ranger B未成功时Go2不能独自进入C放入。
双方READY后，一方有有效本机C即可进入DEPOSIT并接近；另一方缺C则继续搜索。
DEPOSIT阶段允许一方搜索、另一方接近，不等双C缓存；双方可同时执行C。
只收到CACHED不代表接近/放入成功。deposited当前表示导航接近验收/模拟放入，没有实体机械臂动作。

| 验收项 | 单机入口 | 本次协同入口 |
|---|---|---|
| 停稳后base_link到目标平面距离 | ≤0.81m | 自身A/B及本机C均≤1.00m |
| 协同完成条件 | 不适用 | 当前接近Nav2 SUCCEEDED＋当前身份＋真实停稳＋动作终止＋距离达标 |
| XY=0.25、余量0.03时的路径终点距离预算 | ≤0.53m | ≤0.72m |

Nav2参数、安全余量、footprint、扫描角度/次数和既有超时不因1m门槛改变。
远端候选检查全局完整footprint和真实规划路径，不因local覆盖不足本身否决；local已知碰撞/未知、
地图失效/陈旧/缺TF仍失败。运动继续局部避障和执行路径/健康监护。最多8次顺时针45°，ABC同图，自身目标发现后提前结束扫描。
空地与家具点均能被选择；无家具时第二张选点图没有家具层，仍保留双图/候选ID接口和观察历史。
旧门/篮子多边形即使存在也不再拦截；不发送GRANT_RESOURCE或EXIT，收到这些旧指令会拒绝。
无Go2先行或固定退出点；消息资源字段保留为空，exited保留false。

完整成功须coordinator为DONE、双方ready/deposited均true、双方实际停稳且当前命令按task/command/sequence匹配结束。
不得仅凭Nav2 SUCCEEDED、单方READY或某个CACHED记完整PASS。

本地协同证据在`robot_go2.experiment_records_root`下，当前根目录为：

```text
/home/isee-pst/unitree_ros2/VLM_Nav/build/go2-vlm-experiments/
  <task_id_go2_command序号>/events.jsonl
  <同目录>/decisions/     本轮选点图与VLM请求证据
  <同目录>/views/         各方向识别证据
```

具体目录名由command_id中的斜杠替换为下划线形成；Ranger保存自身证据。
协同Runner不等同单机experiment管理器，不假定有单机result.json或自动保留最近10次的清理行为。
本文不额外启动rosbag；记录当次task_id、双方版本、结果和实际已有证据路径。

任务DONE后准备收尾，或需要中途取消时，先结束监视显示，再在终端6调用：

```bash
ros2 run multi_agent_nav multi_agent_start_task pause
```

预期`success=true`，随后核对双方真实停止、原生动作终态和状态进入PAUSED；服务返回只表示暂停请求被接收。
取消后迟到VLM/goal结果不能恢复任务；失联会停车暂停，不自动续跑。
暂停会取消当前动作并等待真实停稳，不存在资源冻结/释放步骤；未确认停车不能重开任务。

确认Go2实际停稳后DISARM：

```bash
timeout 10 ros2 service call /twist_to_go2_sport_bridge/disarm std_srvs/srv/Trigger '{}'
```

预期`success=true`、DISARMED/control_armed=false；Ranger按自身接口安全停止。
都确认后，按原终端依次退出任务层5、任务桥4、Sport3、RViz2、底层1，最后本次启动的相机A。
复用的进程按原所有者管理；不要先关桥制造失联，或先杀底层代替停车。
暂停后重新开始须双方停车、原生动作终止及健康门槛满足，按新任务重新start，不续用旧task/cache。

## 13．异常与紧急停止

- 有碰撞、人身或失控风险：先现场实体急停；软件服务不能替代实体急停。
- 通信或定位丢失：等待原取消/停车确认，保留日志；不要持续重发任务或清运动锁。
- coordinator不可用而仍需Go2软件停止：按原流程在独立Go2终端使用下面脚本；它会取消Nav2并DISARM，
  但不会替代对端停车或coordinator任务处理。该脚本可能使用原有环境加载逻辑，不能拿它验证1020任务安装。

```bash
bash /home/isee-pst/unitree_ros2/VLM_Nav/scripts/stopgo.sh
```

无法确认停车/动作终态时继续按急停排障，不以进程退出作为验收，不删除运动锁、不自动reset/ARM。

## 14．Ranger交接与资料依据

Ranger须接同一公共AgentMachine/Runner/explore_steps接口，使用自己的adapter、地图、相机、footprint、
Nav2。命令与状态不传地图坐标，任务身份、真实停止、READY和独立C完成语义必须一致。
不要整体覆盖Ranger分支，不复制Go2硬件参数；两端消息字段相同也不能代替命令语义版本核对。

- [Ranger最小接入说明](/home/isee-pst/unitree_ros2/VLM_Nav/docs/multi_agent/ranger_handoff.md#2026-10-20-独立c与取消保护区最新覆盖)
- [本轮实现及证据交接](/home/isee-pst/unitree_ros2/VLM_Nav/docs/multi_agent/session_handoff.md#2026-10-20-独立c与取消保护区最新)
- [runbook](/home/isee-pst/unitree_ros2/VLM_Nav/docs/multi_agent/go2_runbook.md)
- [单机一键入口](/home/isee-pst/unitree_ros2/VLM_Nav/scripts/start_go2_vlm.sh)
- [PAUSED通信脚本](/home/isee-pst/unitree_ros2/VLM_Nav/scripts/check_multi_agent_comm.py)
- [正式Go2协同launch](/home/isee-pst/unitree_ros2/VLM_Nav/cooperative_ws/src/multi_agent_nav/launch/go2_cooperative.launch.py)

历史记录：1020独立安装相关测试276项通过（235既有＋41新增），不代表Ranger实机/跨机任务已通过。
独立C实现后的构建/测试结果见runbook与会话交接最新一节；本指引更新只核对文档与命令语法，未执行现场命令。
