# Ranger 复用 Go2 单机框架 Implementation Plan

> 执行者：Ranger 控制电脑上的 Codex 顺序实施；有 executing-plans 技能时可按任务使用。本文交付的是实施计划，本次聊天未修改机器人代码、运行 ROS 或做真机测试。后续代码实现按用户授权开展，现场运动和跨端通信按届时已有授权范围执行。

**Goal：** 将 Go2 当前单机“选观察点→导航→多方向识别→目标投影→接近→停止与记录”框架接到 Ranger 的固定地图、RGB-D、MID-360 和底盘接口，复用同一算法与公共包，并保留后续双机任务接口。

**Architecture：** 先复用单机实际执行链，抽取少量 Go2 配置/健康检查耦合，增加 Ranger profile 和薄 adapter。公共消息、AgentMachine、AgentRunner、coordinator、FrameAdapter 与资源模块继续共用；本轮单机实验不启动 coordinator、bridge 或 fake 对端。

**Tech Stack：** ROS 2 Humble、Nav2、现有 Python/VLM 客户端；系统、SDK、RMW 和原驱动沿用 Ranger 实际可用环境，不为迁移升级。

**Spec / 来源：** 用户已审查的独立地图双机架构、Ranger 本机审计报告，以及本计划第1节列出的实际代码。旧2026-10-09方案中“公共代码尚未取得、重新实现感知/任务层”的部分由本计划取代。

## 1. 本次读取到的真实基线

2026-10-15读取 GitHub `https://github.com/pppppst/VLM_Nav0`：

| 分支 | HEAD | 与本计划的关系 |
|---|---|---|
| `VLM_nav_go` | `32eab6244ec4b483807f8ed68e8667f5495874bb` | 旧 Go2 分支，不含新任务层 |
| `go2-cooperative-task-layer` | `eb32b4527c37cd0b278c1790f7c0bdde7bf5ad75` | 本次读取的新框架基线 |

源码固定链接：[本次任务分支](https://github.com/pppppst/VLM_Nav0/tree/eb32b4527c37cd0b278c1790f7c0bdde7bf5ad75)。实施时若现场 Go2 已有更新，读取其实际 commit/diff 后同步，不能丢掉尚未推送的修复。

Ranger 历史审计基线：`/home/isee601/ws/VLM_Nav`、`main@251f9fb`；当前是否仍一致需在本机核实。先前6项用户修改应保留，不把审计快照当当前状态。

### 实际执行关系

| 已存在文件（相对仓库） | 当前职责 / 已确认限制 |
|---|---|
| `cooperative_ws/src/multi_agent_nav/multi_agent_nav/go2_check.py` | 独立 CLI；inspect/plan/navigate/scan/explore，管理运动排他、停止和实验记录；固定 Go2 运行环境、配置和目标 A |
| 同目录 `go2_exploration.py` | 单机串行探索、三种策略、扫描和接近；不是 coordinator 调度的双机任务 |
| `adapters/go2.py` | `Go2Adapter` 实际主要封装通用 Nav2/Spin、costmap、路径、停稳和扫描；同文件还放 ABCClient/AsyncVision；observer 工厂固定读取 Go2 YAML |
| `generated_candidates.py` | 家具外侧候选、旋转空间、双图、严格候选ID解析；固定读取 robot_go2、source_robot=go2 |
| `semantic_search.py` | 家具选择＋预设观察点；固定 Go2 地图及标注身份 |
| `agent.py`、`runner.py`、`agent_node.py`、`coordinator*.py` | 已有公共任务层；AgentNode 真实分支目前只支持 Go2 |
| `config.py` | 已有地图摘要和 gates；`go2_local_gates` 和部分 `live_gates` 仍依赖 Go2 |
| `config/robot_ranger.yaml`（公共包内） | 只有 robot_id/domain、空地图及 `adapter: not_installed`，尚不能真机运行 |
| 根包 `vlm_nav/vlm_navigator.py` | 新版本支持 `observation_only=True`，复用图像/TF投影，不运行旧自主循环；仍依赖若干名字带 go2 的纯Python工具 |
| 根包 `vlm_nav/arrival.py` | 单机接近距离契约；当前单机实验可因距离达标而取消导航，再确认停止 |

当前 Go2 配置为四视角 `[0,π/2,π,-π/2]`；Ranger 原 `scan_yaws(initial,8)` 是从初始朝向开始依次到45°、90°……360°。不能把前者直接复制给 Ranger。

源码存在和历史记录不等于当前真机通过。本次未在 ROS 环境执行这些测试。

## 2. Global Constraints：保持的行为与范围

- 固定本轮目标是 Ranger 单机接入；Go2 功能保留，任务归属最终仍为 Go2→A、Ranger→B。
- 不整分支覆盖 Ranger，不重写底盘/CAN、Livox、FAST-LIO、AMCL、相机驱动或已验证外参。两端独立地图和自身 footprint/速度参数保留。
- 共同包只维护一份源码；禁止复制一套 `ranger_exploration.py` 或数百行 Ranger 专用 Nav2 状态机后分别演化。
- 保留 Go2 原 CLI、函数调用默认值和策略默认值；Ranger 增加独立入口，依赖相同实现。允许保留历史 `go2_check.py` / `go2_exploration.py` 文件名，避免为命名整洁扩大改动。
- Ranger 默认目标ID为 B，`--target`只覆盖该ID的描述，不能把“找B”偷偷编码为目标A。
- Ranger 保留原八次45°扫描与取图时序；配置角度是相对初始朝向的目标朝向序列，不是逐次累加的转角。
- 本地 `TARGET_APPROACHED` 与公共 READY 分开。本地复用当前距离契约及有界重试；READY/deposited仍由现公共任务机决定，不把本地取消/距离成功直接映射为 READY。
- 接近成功半径、取消半径、Nav2 goal/planner tolerance 分别记录。迁移不顺手增删0.81米检查、不改膨胀或容差；若现场当前版本有更新，以用户确认后的配置为准。
- 路径保留按接收单调时钟判断断流，初值5秒；不新增1秒path header年龄门槛。定位、RGB-D、速度和costmap各自已有时效判断保留。
- 单机不要求 Ranger→Go2 真实SE(2)、对端在线或门/C互斥场景；不能为过门槛伪造 lab_ref 标定或 fake READY。
- 三种选点策略复用；未提供 Ranger 语义标注时先跑 fixed_viewpoints，语义资料齐备后启用另外两种，不重新实现生成/渲染算法。
- 不默认添加完整点云诊断、额外RGB-D检查订阅、录bag或无限API重试；复用已有输入与实验记录。

## 3. Review Focus

1. 目标ID写死A：Ranger所有识别、历史、提前检出及接近必须指向B，生成策略仍检查ABC。
2. 四方向被复制：Ranger应有八次45°转动和八个停止后新图视角；Go2原默认行为不变。
3. 旧 Ranger VLMNavigator 不支持 observation_only：只同步公共包不能解决此依赖；必须同步最小根包能力并做旧入口回归。
4. Go2门槛泄漏：Ranger不可依赖Sport端点、GO2_NET_IFACE、Go2 DDS XML或强制单位lab_ref变换。
5. 本地坐标误写lab_ref、旧响应/旧goal被应用：坐标模式、地图身份、操作代数和停止生命周期必须在复用后保持正确。

## 4. 任务0：核查一次本机状态并同步所需源码

**Files：** 实际 Ranger 仓库与 `docs/multi_agent/ranger_port_status.md`（新增简要记录）。

- [ ] 确认仓库绝对路径、分支、HEAD、适用AGENTS及 `git status --short`，读取已有 Ranger 审计和正在使用的 `scripts` 入口，只补本次变化，不重复全盘审计。
- [ ] 记录原成功入口、地图、相机/深度、TF、Nav2、停止速度反馈、实际解释器及overlay。Ranger配置不得使用Go2路径、相机外参或障碍高度。
- [ ] 在不覆盖用户修改的工作分支完成后续代码；只有需要且不破坏绝对路径的情况下采用worktree。禁止reset/clean、盲目整分支merge和自动提交。
- [ ] 同步该基线的 `cooperative_ws/src/multi_agent_nav` 和 `multi_agent_task_msgs`；它们是公共包，不复制成另一套包名。
- [ ] 核对根包依赖闭包：新 `VLMNavigator(observation_only=True)`、`arrival.py`、`geometry.py`、`models.py`、`vlm_client.py` 及实际导入的纯Python工具。同步其必要实现，合并 Ranger 已有改动；保留 Ranger launch/config/驱动。名字带go2的纯工具可按依赖保留，不因此启动Go2节点。
- [ ] 根包构建仅增加必要文件/依赖；不把Go2整份CMake、Unitree SDK依赖和控制插件要求强加给Ranger。公共Python支持和两ROS包必须来自本次构建的同一overlay。

**完成判据：** 能准确列出同步的commit和本地差异；Ranger仍只有一份vlm_nav及两公共包，旧单机入口保留。缺真机标定不阻塞代码同步和离线测试。

## 5. 任务1：抽出共用 Nav2 能力，增加 Ranger profile

**Files（相对 `cooperative_ws/src/multi_agent_nav/multi_agent_nav/`）：**

| 文件 | 操作 |
|---|---|
| `adapters/nav2.py` | 新增：将当前Go2Adapter的通用动作、路径/costmap、停稳、扫描实现移入Nav2Adapter，算法不重写 |
| `adapters/vision.py` | 新增：承接ABCClient、AsyncVision、observations_from_results，不新增第二套API/解析器 |
| `adapters/go2.py` | 保留make_observer与Go2Adapter薄包装，兼容原导入与默认行为 |
| `adapters/ranger.py` | 新增RangerAdapter和Ranger observer工厂，定义本机健康/运动许可来源 |
| `adapters/factory.py` | 新增小型运行时工厂，只选择已知robot_id；offline不触发ROS初始化 |
| `config/robot_ranger.yaml`（包配置） | 完成本机地图、接口、footprint、scan_angles、API、记录目录和选点策略 |

**接口约束：**

- 保留RobotAdapter的7个方法与 `results` 队列、Future/GoalResult身份语义。
- `select_approach(local_object, excluded_candidates, *, standoff_distance=None)` 保留当前单机调用需要的可选参数。
- 新增 `Nav2Adapter.readiness_checks(now) -> dict[str,bool]` 钩子；get_health复用几何、动作和停止判断，平台差异通过该钩子提供。
- 新增 `create_runtime(robot_id, config, *, read_only=False, global_goal_checks=False, node_name=None) -> (observer, adapter)`；只创建本机能力，不启动硬件/ARM/bridge。

- [ ] 先补有意义的回归：Go2原接口行为保持；Ranger不需要Sport信号；readonly没有运动发布；取消后旧结果无效；停稳来源用实际底盘反馈。
- [ ] 将代码移到公共模块并增加薄包装，保留旧导入兼容。若现有测试patch模块属性，保持兼容边界或调整注入位置，不通过删测试掩盖行为变化。
- [ ] Ranger工厂读取本机根 `config/robot.yaml` 的RGB-D/TF参数，以 `observation_only=True` 运行，`raw_depth_mode=false` 使用本机已对齐深度；不要求Go2 raw-depth单位报告或特定librealsense路径。
- [ ] 健康判断保留Nav2动作服务、定位、costmap、RGB-D、停止反馈与明确的本机运动许可。用Ranger本机来源替代Go2 nav_ready/control_armed；没有真实来源时报告缺项，不能恒置true。
- [ ] `/odom.twist`用于停稳反馈（先核实当前驱动仍提供真实速度）；map位姿仍取TF。底盘输出沿用Ranger实际 `/cmd_vel` 接收链，协同只有一个上层goal拥有者。底层运动/速度超时采用Ranger能力，不复制Sport协议。
- [ ] Ranger扫描角度采用 `list(scan_yaws(0,8))`，即45°、90°……360°目标朝向；保留“Spin完成→停稳→新帧→识别”顺序。测试实际八个目标方向，而不只断言列表长度。

**验证：** 后续在已确认解释器上执行新增 `tests/test_robot_adapters.py` 和受影响 `test_go2_adapter.py`、`test_go2_scan_evidence.py`、`test_go2_executing_path.py`。预期Go2回归通过、Ranger使用本机接口、无真实运动。迁移不声称已解决所有原有路径重规划竞态。

## 6. 任务2：共用单机执行器，去掉Go2/目标A硬编码

**Files：** `go2_check.py`、`go2_exploration.py`、`config.py`、`generated_candidates.py`、`semantic_search.py`；新增 `ranger_check.py`、必要 `local_context.py`；包CMake入口表。

建议的兼容接口（新增参数均有Go2默认值）：

```text
go2_check.main(argv=None, *, robot_id='go2')
go2_check.run_ros(config, args, events=None, *, robot_id='go2')
go2_exploration.explore(原位置参数保持, *, robot_id='go2', target_id='A')
GeneratedCandidates(config, robot_id='go2')
load_catalog(config, robot_id='go2')
robot_local_gates(config, robot_id, motion=False, vision=False, check_map_files=True)
```

- [ ] `go2_local_gates`保留兼容包装；单机Ranger使用robot_local_gates，不走要求双机标定、Go2硬件与对端地图文件的live_gates。
- [ ] `ranger_check.main(argv=None)`调用同一执行器并指定robot_id=ranger，注册 `multi_agent_ranger_check`；原 `multi_agent_go2_check` 保持可用。
- [ ] 新增 `--target-id A|B|C`；Go2默认A、Ranger默认B。默认描述读取scene.targets[target_id]，`--target`只替换该目标描述。去掉检测过滤、partial-error保留、历史和接近中的所有硬编码A。
- [ ] 生成候选策略仍同图识别ABC；例如Ranger选择B时，A已检出不能误结束搜索，C早期检出不触发本地目标切换。
- [ ] 按robot_id读取机器人配置、地图身份、viewpoints、语义资料、footprint、日志目录及display topics；GeneratedCandidates/语义catalog检查当前机器人来源，不通过改文件标签冒充坐标正确。
- [ ] `require_ros_environment`分平台校验。Go2原严格环境保持；Ranger接受本机真实RMW/域/接口配置，不要求enp4s0或CycloneDDS/Go2 XML。offline仍不得初始化ROS。
- [ ] 将运动锁、节点名、RViz marker、run_id/事件中的robot_id和frame从常量变为运行上下文；两台同名文件无碍，但同机重复运动实例仍拒绝。
- [ ] 本机环境/解释器、地图或配置有误时输出具体缺项。API调用仍在原AsyncVision中，原日志/图片/严格候选ID解析及取消代数继续复用。

**测试：** 新增 `tests/test_robot_local_exploration.py`，至少验证：Ranger找B且真实B检出进入接近；A/C检出不提前完成；ABC部分出错时保留B的有效检出但不把整点记为已观察；完整八方向；Go2原无robot参数调用结果不变；离线不导入/创建真实ROS客户端。

## 7. 任务3：本机地图、选点与原接近行为

**Files：** 包内Ranger配置；Ranger地图旁的新观察点/语义文件；公共探索上下文及必要转换调用。

- [ ] fixed_viewpoints使用现场给定的Ranger本机map观察点，不复制Go2的两个观察点。先提供一个或少量真实点即可；缺点时保持配置缺项，不造坐标。
- [ ] 单机采用显式 `local_only` 上下文：本机map作为内部参考、恒等变换仅表示同一张Ranger地图，frame/日志写 `ranger_local_map` 和本机map_id；无lab_ref标定时不标为lab_ref，不发布公共任务消息。真实alignment.yaml保持未validated。
- [ ] 允许本机识别与接近在这个局部上下文完成；Observation元数据及结果记录必须与当前FrameAdapter身份一致，不能保留默认lab_ref。之后切换协同模式才要求真实Ranger→lab_ref变换。
- [ ] 语义策略直接复用GeneratedCandidates/semantic_search；Ranger语义多边形与本机map对应，更新source_map哈希/路径。可从Go2语义图经已验证变换生成Ranger版本，未标定时使用Ranger人工标注；不能只改source_robot字段。
- [ ] 两张给VLM的图继续使用同一像素变换与标记层，展示当前位置/朝向、P编号和已观察点；只有本机静态/实时旋转空间、costmap、路径检查通过的候选可选。模型仍只返回候选ID。
- [ ] 目标物体位置和停车点分离；当前 `select_approach` 的局部costmap/路径检查与接近闭环共用，参数读取Ranger本机arrival_config_files，不复制Go2的容差、速度或footprint。
- [ ] 保留当前 `TARGET_APPROACHED / TARGET_DETECTED_UNLOCATED / WAITING_VIEWPOINTS / EXHAUSTED / APPROACH_DISTANCE_FAILED` 的真实含义与停止记录。Nav2成功但距离契约未达标时按原逻辑报告，不伪造本地成功；本地成功也不置协同READY。
- [ ] 当前单机不启通道互斥，resources显式为空；仍保留定位、路径、动态障碍与停止判断。真实门/C区域及跨图标定留给联合阶段，不阻塞本机实验。

**验证：** 两张带非零origin/旋转的合成地图验证渲染与候选身份；本机标注错图被拒绝；目标B与坐标模式进入结果记录；arrival现有测试保持。未提供真实语义图时，标记该策略尚未现场准备，不影响fixed_viewpoints交付。

## 8. 任务4：最小启动接入、构建与验证

**新增：** `scripts/start_ranger_local.sh`、`launch/ranger_local.launch.py`、本机 `config/nav2_ranger_local.yaml`、`docs/multi_agent/ranger_local_runbook.md`。

**必要修改：** Ranger `launch/system.launch.py`、`launch/vlm_navigation.launch.py`、实际Nav2 profile透传处；默认保持旧行为。

- [ ] 为旧vlm_navigator Node增加 `start_legacy_navigator`（默认true）开关，新单机入口设false，避免旧自主循环/图像订阅与新observer同时运行。不能仅enabled=false后把它当可用感知服务。
- [ ] 复用Ranger原硬件、固定地图、TF适配与Nav2。新入口不启动Go2相机SSH、Sport bridge、Go2 supervisor、coordinator或task bridge；不自动ARM或发任务。
- [ ] 新Ranger Nav2 profile由本机已有配置派生，需要动态障碍时增加本机点云/scan层；保留旧AMCL profile，禁止为了迁移照抄Go2控制参数。明确当前raw costmap和执行路径实际topic，未核实则列现场项。
- [ ] 默认附着已运行硬件；启动前识别重复旧任务/底盘/TF发布者并报告，不自动杀进程或重启硬件。完整冷启动仍按Ranger现有脚本顺序。
- [ ] 独立构建目录建议统一 `REPO/build/ranger-local/{build,install,log}`，只维护这一套新输出。测试/source/result均对应该目录，最后加载新overlay，不能再被旧install覆盖。
- [ ] 不因单机构建要求安装domain_bridge：本轮构建用 `BUILD_TESTING=OFF` 避开现公共CMake的bridge parser测试依赖；离线pytest单独执行所需测试。桥接parser未运行明确记录，后续通信阶段再补，不报告完整colcon测试通过。

本机Codex核实实际REPO/解释器与依赖overlay后执行；以下变量必须来自已完成核查，不让用户猜路径：

```bash
# 构建终端：已加载Ranger现有ROS/硬件依赖；命令会构建软件，不启动机器人。
colcon list --base-paths "$REPO" "$REPO/cooperative_ws/src"
colcon --log-base "$REPO/build/ranger-local/log" build \
  --base-paths "$REPO" "$REPO/cooperative_ws/src" \
  --build-base "$REPO/build/ranger-local/build" \
  --install-base "$REPO/build/ranger-local/install" \
  --packages-up-to multi_agent_nav --symlink-install \
  --cmake-args -DBUILD_TESTING=OFF \
  -DCOOPERATIVE_RUNTIME_PYTHON="$RANGER_PYTHON"
source "$REPO/build/ranger-local/install/setup.bash"
ros2 pkg executables multi_agent_nav
```

**成功判据：** 三个包各出现一次，构建成功，能看到原Go2及新Ranger入口；纯Python运行时与rclpy生成消息ABI兼容，安装导入确来自本次输出。不是相机/运动验收。

后续软件验证只跑受影响组：新增adapter/本地探索测试，加既有 `test_go2_adapter.py`、`test_go2_exploration.py`、`test_go2_scan_evidence.py`、`test_go2_executing_path.py`、`test_generated_candidates.py`、`test_semantic_search.py`、`test_exploration_display_records.py`，以及根包 `test/test_arrival_contract.py` 和Ranger实际受影响旧launch/geometry测试。不因文档修改或无新问题重复全量测试。

runbook必须写清每条命令的终端、目录、环境、目的、预期结果和是否保持运行。新CLI交付后至少提供：

```bash
# 自动退出：配置检查，不初始化ROS、不请求API、不运动。
ros2 run multi_agent_nav multi_agent_ranger_check \
  --config-dir "$RANGER_LOCAL_CONFIG" --offline --require-ready

# 后续现场只读：依赖本机已运行的地图、定位、相机/Nav2，不发运动命令。
ros2 run multi_agent_nav multi_agent_ranger_check \
  --config-dir "$RANGER_LOCAL_CONFIG" --action inspect --require-ready

# 后续获授权的单机实验：显式运动，只选择本机已填写的观察点。
ros2 run multi_agent_nav multi_agent_ranger_check \
  --config-dir "$RANGER_LOCAL_CONFIG" --action explore --allow-motion \
  --target-id B --approach-target --strategy fixed_viewpoints \
  --timeout 300 --output-dir "$RANGER_EXPERIMENT_DIR"
```

第一条退出0且缺项为空、motion_sent=false才进入下一阶段。第二条须能读到正确本机地图/健康/真实速度，不能用静止零值替代反馈有效性。第三条输出真实八方向识别、B目标与停止结果；软件验证通过后可在这次受控实验中一并观察导航/取消/接近，不强制先展开多轮冗余专项真机测试。运动授权缺失时只交付软件与命令，不自动运行第三条。

## 9. 双机阶段的接入点（本轮不提前实现整套联动）

Ranger单机完成后，只补既有公共层的Ranger真实分支：AgentNode使用同一create_runtime，保留AgentMachine/Runner/消息/coordinator；将local_only换成经验证lab_ref，完整 `live_gates` 按local_robot检查本机配置与双方共享身份，去掉“无论local_robot是谁都按Go2健康判断”的耦合。

部署继续双方本地Domain0、定向bridge接Domain40；Ranger不启动coordinator。新消息保留现schema/topic/QoS，不重写协议。随后按现场安排验证状态/目标共享、READY屏障、门/C资源与整机退出。此阶段才要求真实地图对齐、双方在线和相同C，不能用单机TARGET_APPROACHED或fake对端代替协同完成。

## 10. 交付与回退

- [ ] 报告基线commit、本机已有改动、同步文件及公共化的精确差异。
- [ ] Go2原入口与公共测试回归保留，Ranger独立入口可构建；不声称远端Go2源码等于现场已全部通过。
- [ ] 报告八方向/目标B/本机坐标模式的测试证据，区分软件测试与尚未执行的真机实验。
- [ ] 填写真实地图、相机、运动/停止接口及运行环境；语义资料或标定缺失只阻塞对应阶段。
- [ ] 回退通过停止新任务并确认取消/停稳后退出新入口、在新终端加载旧overlay和原脚本完成，不reset整仓库、不删除日志/bag或旧install。

## 可直接给 Ranger Codex 的任务说明

```text
请按本计划实施Ranger单机接入。当前电脑是Ranger控制电脑，先核实ws/VLM_Nav路径、
分支/HEAD/已有改动/AGENTS与实际scripts入口，保留已验证硬件、地图、定位和用户修改。
框架来源是pppppst/VLM_Nav0的go2-cooperative-task-layer@eb32b4527c37cd0b278c1790f7c0bdde7bf5ad75，
不是仍停在32eab62的VLM_nav_go。若用户提供更新Go2 commit/diff，先读取并保留最新修复。

不要重新写第二套任务机或整分支覆盖Ranger。复用现go2_check→go2_exploration→Adapter，
将机器人配置/平台健康/目标ID参数化，抽取共用Nav2与vision模块，增加Ranger薄适配和入口。
同步根包必要observation_only投影支持，不能只复制cooperative_ws后假设旧VLMNavigator兼容。
Ranger默认找B，保留原八次45度扫描；本地接近沿用当前arrival契约，不替换成协同READY。
两张地图独立；本轮local_only只使用Ranger map，不填假lab_ref标定，不依赖Go2在线。
复用三种选点策略及双图/ID解析；无Ranger语义图时先完成fixed_viewpoints，资料就绪后启用同一算法。
不复制Go2 raw-depth、Sport、网卡、footprint、DWB最小速度或绝对路径。

完成必要离线回归和隔离构建，生成真实Ranger运行命令与回退说明。只为缺失的现场资料报告
具体阻塞项；不要反复确认常规实现选择，不做无关重构/升级/额外常驻诊断。
本轮不启动bridge、不操作Go2、不自动运行真机运动；真机步骤按之后已有明确授权执行。
```
