结论：可从外部复用现有独立搜索执行链，无需重写探索和靠近算法；但现有接口尚不足以直接承诺“框架退出即取消完成”。 本轮只读核对，未修改仓库、启动业务或调用模型。

以下“源码已核实”包括安装文件静态核对；历史日志不作为当前真机验收证据。

## 1. 建议冻结的基线

源码已核实

- 仓库：/home/isee-pst/unitree_ros2/VLM_Nav
- 远端：git@github.com:pppppst/VLM_Nav0.git
- 分支：go2-cooperative-task-layer
- HEAD：bce9de1ee4e9d2dd3c4ac6288703335767bb9ae9
- 工作树 dirty，结束核对时状态与开始一致：

 M AGENTS.md
M  CoVLM_env.bash
M  Cooperative_env.bash
M  README.md
M  docs/multi_agent/go2_runbook.md
MM docs/multi_agent/session_handoff.md
MM docs/双机协同启动与验收.md
 M scripts/start_go2_cooperative_task.py
MM scripts/start_go2_vlm.py
M  test/test_cooperative_environment.py
 M test/test_start_go2_cooperative_task.py
MM test/test_start_go2_vlm.py

与单机执行直接相关的未提交修改：默认 overlay 从 go2-local-scan-20261029 改为 go2-recoverable-pause-20261029，NAV_READY 启动等待从 120 秒改为 240 秒。探索、接近及 adapter 文件没有未提交修改。因此应冻结 HEAD＋现有 dirty 内容＋安装副本，不能仅冻结 HEAD。

操作者已确认的实际启动入口

你补充的命令明确选择：

- scripts/start_go2_vlm.sh --target '灭火器'
- COOP_SETUP_FILE=/home/isee-pst/unitree_ros2/VLM_Nav/build/go2-recoverable-pause-20261029/overlay/install/local_setup.bash
- GO2_CONFIG=/home/isee-pst/unitree_ros2/VLM_Nav/cooperative_ws/src/multi_agent_nav/config

以下简称仓库为 R，上述 overlay/install 为 P。

源码已核实：环境及加载身份

CoVLM_env.bash:15 (VLM_Nav/CoVLM_env.bash:15) 的 source 顺序为：

1. /opt/ros/humble/setup.bash
2. /home/isee-pst/Documents/liang/hesai_xt16_ws/install/setup.bash
3. /home/isee-pst/unitree_ros2/go2_ws/install/setup.bash
4. R/build/go2-coop/install/local_setup.bash
5. P/local_setup.bash
6. R/scripts/go2_network_env.sh

前面的 setup 有重复加载 underlay 的链，但最终仍由 P 覆盖。脚本先清除 PYTHONHOME/PYTHONPATH；DDS 配置为 Domain 0、CycloneDDS、enp4s0。

- 启动编排：/usr/bin/python3，版本 3.10.12。
- 安装一致性检查及 multi_agent_go2_check：/home/isee-pst/venv/co-nav-real/bin/python，版本 3.10.12。
- 安装模块路径：P/<包名>/local/lib/python3.10/dist-packages/<包名>/。
- 两包共 55 个 Python 文件逐字节一致；根包 27 个 config 文件、22 个 launch 文件一致；抽查的协同配置及单机启动脚本一致。Python 安装文件为普通副本，不是源码软链接。
- CoVLM_env.bash、Cooperative_env.bash由源码路径加载，不在安装 share 根目录复制。

关键文件源码与安装副本 SHA-256 一致，下面列摘要前 16 位：

| 文件 | SHA-256 前缀 |
|---|---|
| go2_check.py | 818d7f6e10af8912 |
| go2_exploration.py | b48845e3636814b2 |
| local_approach_execution.py | e0a616105b0b22e4 |
| single_robot_approach.py | 7b04f01c0b6bd44c |
| adapters/go2.py | 918c6cf8d71d0b80 |
| vlm_nav/vlm_navigator.py | cd7140e6d83084474 |

配置来源需区分：

- 任务配置：R/cooperative_ws/src/multi_agent_nav/config/，读取 alignment/scene/robot_go2/robot_ranger.yaml；读取 Ranger 配置文件不等于连接 Ranger。
- 地图：R/maps/lab_rescan_20261018_155656_0pa6gm/lab.yaml。
- Keepout：同地图目录下 keepout_boundary_20261025_7be2a662/keepout_mask.yaml。
- 到达参数：源码 R/config/robot.yaml → R/config/robot_go2.yaml，与安装对应副本一致。
- 观察器参数：安装 share 中 config/robot_go2.yaml及 adapter 覆盖。
- Nav2：安装 nav2_bringup 默认 → 安装 nav2_go2.yaml → 安装 nav2_go2_static_map.yaml → 上述任务配置目录的 nav2_go2_cooperative_costmap.yaml，再应用 Keepout。
- 冷启动显式使用源码的 preflight、标定、FAST-LIO 配置；复用既有底层时不会重新加载它们。

已有运行记录支持

最近找到的完整单机记录为 single-vlm.s4mr8uhz/explore.log (VLM_Nav/build/go2-field/single-vlm.s4mr8uhz/explore.log)，对应 2026-10-27 21:19，“灭火器”、生成候选策略、上述地图；结果为接近规划失败，stop_confirmed=true。较早的 experiment.20261027_211123.7b42b791/result.json记录过 TARGET_APPROACHED。

当前未验证

工具环境的 /proc仅见隔离环境内少量进程，不能判断宿主当前任务、模块加载或运动锁状态。本轮未 source 环境、导入业务模块或查询 ROS；没有证明当前运行进程使用上述安装。地图只核对 YAML 身份，未重算 PGM 或整套地图摘要。

## 2. 调用链

源码已核实，以下是已确认启动命令实际对应的分支：

| 层次 | 文件、函数及行号 | 职责 |
|---|---|---|
| Shell 入口 | start_go2_vlm.sh:8 (VLM_Nav/scripts/start_go2_vlm.sh:8) | 加载环境、检查安装、启动 Python 编排 |
| 准备与使能 | start_go2_vlm.py:213 (VLM_Nav/scripts/start_go2_vlm.py:213)、:296 | 准备/复用硬件、人工定位确认、检查 owner、ARM |
| 单次搜索 | 同文件 Launcher.explore():320 | 调用 multi_agent_go2_check --action explore --allow-motion --target 原描述 --approach-target --timeout 300；固定传入 generated_candidates_vlm |
| 独立执行 | go2_check.py:353 (VLM_Nav/cooperative_ws/src/multi_agent_nav/multi_agent_nav/go2_check.py:353)、:138 | run_ros() → standalone_explore_steps()，生成任务身份、设置独立运动 guard |
| 探索 | go2_exploration.py:84 (VLM_Nav/cooperative_ws/src/multi_agent_nav/multi_agent_nav/go2_exploration.py:84) | 初始观察 :504 → 候选生成/选择 :563 → 规划导航 → 到点旋转空间检查 → 环扫 :647 |
| 视觉与深度 | adapters/go2.py:22 (VLM_Nav/cooperative_ws/src/multi_agent_nav/multi_agent_nav/adapters/go2.py:22)、:1009 | VLMNavigator(observation_only=True)提供 RGB-D/TF；ABC 识别、投影、深度重观察 |
| 接近 | local_approach_execution.py:22 (VLM_Nav/cooperative_ws/src/multi_agent_nav/multi_agent_nav/local_approach_execution.py:22) | 驱动共享 SingleRobotApproach，返回既有结果 |
| 停稳验收 | single_robot_approach.py:249 (VLM_Nav/cooperative_ws/src/multi_agent_nav/multi_agent_nav/single_robot_approach.py:249)、go2_check.py:170 | 内层距离/动作终态/停稳验收，再执行外层健康及距离验收 |

不需要 Ranger、coordinator 或跨机桥接；但仍需要本机既有传感器、定位、Nav2、Sport 等输入。

目标字符串以 argv 原样传入，未发现翻译、裁剪或模型改写。内部以 A 为主目标，覆盖传给扫描器的 A 描述；原配置仍须有有效 A/B/C，当前 B 为“灭火器”、C 为“白色的桶”。因此“一轮一个主目标”成立，但内部仍是原 ABC 识别流程。

当前入口的目标有效性依据是 DETECTED＋有效深度定位，不是旧 VLMNavigator.confirm_target()多帧确认状态机；观察器模式不会启动旧自主导航计时器。后续应保持这条真实调用链。

原内部机制包括：

- 深度恢复额外重观察最多 2 次；
- 接近距离不合格重试 1 次；耗尽后符合距离拒绝条件则继续探索；
- 候选导航/观察失败的 30 秒重选冷却；
- 总探索期限 300 秒、扫描配置 240 秒、接近动作监护 120 秒、API 超时 20 秒。

这些由现有执行器控制，外层无需增加重试或重启整轮。

## 3. 外部封装可行性

源码已核实：可直接复用

- 现有独立 CLI 的整轮搜索、识别定位、接近及验收。
- 原目标 argv、固定策略和期限。
- 现有事件、最终报告、视觉证据。
- 现有运动锁、owner 检查和正常 SIGINT 清理。

必须补充的外部接口

- 一次请求与 PID/进程组、证据目录、run_id/task_id的关联。
- 同一轮只能启动一次的约束，防止模型重复调用造成第二轮搜索。
- 进度、结果及取消状态的稳定返回格式。
- RoboRSI 的 cancel_active_and_wait()与实际搜索取消流程对接。
- solved()只读取原程序结果，不读取模型的成功自述。

完整 start_go2_vlm.sh需要桌面、TTY和人工确认，不适合直接作为无交互工具。优先封装其内部独立执行入口，硬件准备、定位与 ARM/DISARM继续由明确的宿主流程管理。独立 CLI 本身不负责 ARM 或 DISARM。

严格的异常停止证明存在第 4 节所述缺口，不能仅靠包装一个 subprocess便宣称完整取消契约成立。

## 4. 状态和取消契约

源码已核实：已有数据

- events.jsonl：run_id、sequence、wall_time、target、地图身份、state/event；执行事件还含 task_id/command_id/goal_id/native_action_uuid。
- result.json及终端 JSON：result、rejected、stop_confirmed、stop_error、motion_sent、last_native_action_uuid、evidence_write_failed、vlm_evidence_pending、vlm_evidence_root。
- 证据位于实验目录的 vlm/、selection/；启动器另保存 inspect.log/explore.log。
- 没有现成的按任务 ID 查询/取消服务；最终报告也未统一包含所有任务身份，需要关联事件。

成功依据

启动器要求：子进程退出 0、result=="TARGET_APPROACHED"、stop_confirmed==true、两个证据故障/未完成标志均为 false；随后 DISARM 服务成功并读回 DISARMED。

接近内部实际契约是：首次到 0.89 m 进入停止流程，停稳后要求 ≤0.81 m；外层再要求健康、定位有效、动作终态、停稳和 ≤1.0 m。不能额外把成功改成必须 Nav2 SUCCEEDED：现有距离触发取消后的 CANCELED终态也可满足成功条件。

停止确认

go2_check.py:108 (VLM_Nav/cooperative_ws/src/multi_agent_nav/multi_agent_nav/go2_check.py:108) 调用取消及零速度发布，再等待最多 5 秒，要求：

- 本进程记录的动作全部终态；
- 新鲜 /odometry：年龄≤0.5秒；
- 平面速度≤0.03 m/s、角速度≤0.05 rad/s，连续至少0.5秒。

这是程序的里程计停稳判据，不是独立实体测量认证。

| 退出方式 | 当前处理 |
|---|---|
| 顶层 Ctrl+C / SIGTERM | 顶层转换为中断，向搜索进程组发一次 SIGINT，最多等待30秒 |
| 搜索 CLI 收到 SIGINT | 捕获 KeyboardInterrupt，关闭执行生成器，进入最终取消、停稳检查及报告 |
| 搜索异常 / 内部期限到达 | 记录失败，走最终停车检查 |
| 搜索 CLI直接收到 SIGTERM | 未注册清理处理器；不能保证进入上述 finally |
| SIGKILL、父进程崩溃 | 无可靠收尾保证；搜索使用独立 session，可能继续运行 |

停止不能确认时设置 stop_confirmed=false、记录 STOP_UNCONFIRMED并失败退出；运动锁保留 STOP_UNCONFIRMED或 IN_PROGRESS，禁止自动再次启动。顶层不自动 DISARM或删除锁。

关键缺口

1. motion_terminal来自本地 motions集合。adapter 获取 action 结果异常时也会 finish('ABORTED')移除记录并置 motion_fault；stop_owned()只检查停稳和集合终态。故异常情况下，该字段不足以证明已收到原生终态。依据：adapters/go2.py:758 (VLM_Nav/cooperative_ws/src/multi_agent_nav/multi_agent_nav/adapters/go2.py:758)、:777。
2. 顶层等待取消超时后不会强杀搜索子进程；框架退出也不等于搜索或机器人停止。
3. result.json不是原子写入；部分单机诊断写入失败仅告警，事件完整性不能只靠一个布尔字段保证。后台视觉请求也可能晚于停车完成。
4. 两个 flock及 ROS节点名称检查能防常见重复启动，但不是所有运动客户端共享的统一原子 owner 锁。
5. 默认实验目录只保留十份受管理记录，后续启动可能清理旧记录。外部封装可利用已有 --output-dir选择管理根之外的新目录，保留证据而不改搜索逻辑。

## 5. Codex / RoboRSI 环境

本机已核实

| Codex 路径 | 版本 |
|---|---|
| ~/.local/bin/codex → standalone release | 0.166.0，当前 PATH 优先 |
| /usr/bin/codex，/bin/codex为同一路径别名 | 0.93.0 |
| SenseNova-RoboRSI/.venv/lib/python3.10/site-packages/codex_cli_bin/bin/codex | 0.163.0 |

只执行了 --version。查询出现只读文件系统下无法创建 PATH 别名的警告，未执行修复。

- 用户级非敏感配置：model=gpt-6-astra、model_reasoning_effort=high。
- 尚无确定的 Go2 框架运行配置；RoboRSI运行时可显式覆盖上述值，不能把用户默认配置视为未来有效配置。

RoboRSI：

- 路径：/home/isee-pst/unitree_ros2/SenseNova-RoboRSI
- 远端：https://github.com/OpenSenseNova/SenseNova-RoboRSI.git
- HEAD：0208cd72ec7c885a7219040cd2be459d127e374e
- detached HEAD，工作树干净。
- .venv已 editable 安装 roborsi 0.0.0，模块指向该源码目录。
- openai-codex及其 CLI binary 包为 0.163.0。
- 系统已有 Python 3.10.12、3.12.11；项目要求 >=3.10,<3.13。可另建隔离环境，ROS执行侧继续固定现有3.10环境。

框架已提供 Toolkit取消和 solved()钩子，但默认取消只设置取消事件并等待工具返回，不会自动理解 Go2停稳契约。CLI进程清理使用 SIGTERM/SIGKILL，也不能代替机器人取消。

示例 codex_cli.yaml的模型和版本仍是占位符，动作超时示例为180秒，短于现有300秒搜索；实施时需配置框架等待预算，不能因此缩短原搜索期限。

当前未验证：模型访问、认证有效性、真实请求及框架接入均未验证。

## 6. 仍需用户回答的问题

目前没有必须补答的问题：实际单机启动命令、overlay、配置目录和目标已由你补齐。

当前宿主加载、底层参数和运行任务状态仍未知，属于后续受授权现场核验事项，不能由本轮文件检查补证。

## 7. 建议的最小改动范围

仅建议，不实施：

1. Go2侧增加一个 RoboRSI Toolkit/外部执行包装及固定配置；一轮只接受一个原始目标描述，只启动一次现有独立搜索。
2. 增加身份关联、事件读取、结果映射和取消等待；框架成功仅取原执行器结果。
3. 保留现有硬件准备与 ARM/DISARM责任边界；固定解释器、overlay、配置及 Codex二进制绝对路径。
4. 若要求覆盖异常退出的严格停止保证，再单独处理 SIGTERM清理、原生终态未知与已确认的区分、持久停止回执三个接口缺口；不改探索、识别、深度恢复、接近或重试策略。

未执行构建、测试、ROS查询、模型请求或真机验收；主要剩余风险是异常退出时停止证明不足。核对结束，等待后续实施文档。
