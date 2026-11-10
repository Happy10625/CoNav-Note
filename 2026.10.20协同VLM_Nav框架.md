当前采用的是：Go2 集中管理任务阶段，两台机器人各自完成本地探索与导航，通过许可协调门和篮子的使用。 Ranger 端需要接入自己的执行适配器，复用公共任务层。

┌────────────────────────────────────┐
│ Go2：coordinator + RulePlanner     │
│                                    ├◄─命令、状态、许可─────────────┐
│                                    ├◄─定向桥接：命令、状态、许可───╪─┐
└────────────────────────────────────┘                               │ │
                                                                     │ │
                                                                     │ │
┌────────────────────────────────────┐                               │ │
│ Go2：AgentMachine + AgentRunner    │                               │ │
│                                    ├◄──────────────────────────────┘ │
│                                    ├─────────────────────────────────╪─┐
└────────────────────────────────────┘                                 │ │
                                                                       │ │
                                                                       │ │
┌────────────────────────────────────┐                                 │ │
│ Ranger：AgentMachine + AgentRunner │                                 │ │
│                                    ├◄────────────────────────────────┘ │
│                                    ├───────────────────────────────────╪─┐
└────────────────────────────────────┘                                   │ │
                                                                         │ │
                                                                         │ │
┌────────────────────────────────────┐                                   │ │
│ 公共 explore_steps 核心            │                                   │ │
│                                    ├◄──────────────────────────────────┘ │
│                                    ├─────────────────────────────────────╪─┐
└────────────────────────────────────┘                                     │ │
                                                                           │ │
                                                                           │ │
┌────────────────────────────────────┐                                     │ │
│ 同一公共 explore_steps 核心        │                                     │ │
│                                    ├◄────────────────────────────────────┘ │
│                                    ├───────────────────────────────────────╪─┐
└────────────────────────────────────┘                                       │ │
                                                                             │ │
                                                                             │ │
┌────────────────────────────────────┐                                       │ │
│ Go2 adapter → 本机感知 / Nav2      │                                       │ │
│                                    ├◄──────────────────────────────────────┘ │
└────────────────────────────────────┘                                         │
                                                                               │
                                                                               │
┌────────────────────────────────────┐                                         │
│ Ranger adapter → 本机感知 / Nav2   │                                         │
│                                    ├◄────────────────────────────────────────┘
└────────────────────────────────────┘

各模块的职责如下：

| 模块 | 部署位置 | 职责 |
|---|---|---|
| RulePlanner | Go2 | 分配 Go2 找 A、Ranger 找 B，安排 C 放入和退出顺序 |
| coordinator | Go2 | 管理阶段、READY 屏障、命令重发、心跳、超时和资源许可 |
| AgentMachine | 两端各一份 | 检查任务身份、处理状态转换、导航结果及许可申请/退出 |
| AgentRunner | 两端各一份 | 逐 tick 推进执行核心，连接状态机与 adapter；等待 VLM 时继续处理通信 |
| explore_steps | 两端复用 | 本地生成候选、VLM 选 ID、导航、扫描、定位、接近和距离验收 |
| 机器人 adapter | 各自实现 | 对接自身相机、TF、costmap、Nav2、停止确认和异步结果 |

RulePlanner 和 coordinator 都不选择本地探索点。虽然公共核心文件仍叫 go2_exploration.py，现在已按 robot_id 使用对应机器人的配置。

整个任务按以下顺序推进：

| 阶段 | 行为与完成条件 |
|---|---|
| SEARCH_AB | Go2 本地找 A，Ranger 本地找 B；各自接近验收成功后 READY，先完成的一方停稳等待 |
| SEARCH_C | 双方 READY 后，各自检查本机 C 缓存；没有有效线索的一方继续本地寻找 |
| DEPOSIT | 双方都有本机 C 引用后，先 Go2 接近、模拟放入并整机退出，再放行 Ranger |
| DONE | 双方均完成放入和退出，资源许可已释放 |

场内虽然只有一个 C，软件仍只使用各自识别的位置，不共享 C 坐标，也不做共同 C 绑定或跨地图转换。

机器人内部的执行流程为：

本机地图＋家具标注
→ 生成并筛选观察候选
→ 检查全局 costmap、完整 footprint、旋转空间和规划路径
→ 将候选图及 P 编号交给本地 VLM
→ 导航到选中点并停稳
→ 最多 8 次顺时针 45°，每次停稳后使用新鲜 RGB-D 同图识别 ABC
→ 发现自身目标后提前结束扫描
→ 本机定位目标、规划接近、导航并验收

远端候选不会仅因超出局部 costmap 而被否决；运动期间仍使用本机局部避障和资源监护。协同接近必须同时满足：当前任务身份有效、当前目标接近导航 SUCCEEDED、真实停稳、动作终止，以及 base_link 到已定位目标的平面距离 ≤1.00 m。原单机入口保持 0.81 m。

Ranger 的主要搭建工作是实现自己的 adapter，并接入公共 Runner：

AgentRunner(
    machine,
    ranger_adapter,
    descriptions,
    on_observation,
    config=config,
    success_radius=1.0,
)

接口应遵守 RobotAdapter (cooperative_ws/src/multi_agent_nav/multi_agent_nav/adapters/base.py) 的契约：

| 接口组 | Ranger 需要提供的内容 |
|---|---|
| 健康状态 | get_health()：本机位置、定位/Nav2 健康、真实停稳、动作是否终止、执行路径和完整 footprint |
| 路径与接近 | compute_path() → Future[PathResult]；select_approach() → Future[ApproachResult] |
| 距离参数 | read_approach_parameters()：读取实际 XY 和 planner 容差，不修改它们 |
| 地图检查 | costmap_transform、costmap_candidate_free、observation_candidate_free、approach_candidate_free |
| 运动 | start_navigation() 返回独立 goal ID；结果进入 results 队列，并携带 task/command/goal/kind 身份 |
| 扫描与 VLM | start_scan() 返回观测列表 Future；提供 client.choose_candidate() 和后台 vision.submit() |
| 取消与停车 | cancel_navigation()、stop_motion()；遵守 Runner 注入的 motion_guard |

这里有一个容易接错的边界：adapter 内部的有效目标观测需要保留本机坐标。现有观测字段仍叫 common_position，但私有模式下内部承载本机位置；由 AgentMachine 在发送网络消息前统一清零，不能在 adapter 产生观测时就清掉位置。

通信继续使用既有五条任务话题：

| 话题 | 跨机方向 |
|---|---|
| /multi_agent/go2/state | Go2 → Ranger |
| /multi_agent/go2/observation | Go2 → Ranger |
| /multi_agent/ranger/state | Ranger → Go2 |
| /multi_agent/ranger/observation | Ranger → Go2 |
| /multi_agent/go2/command | Go2 → Ranger，按 recipient_id 分发 |

两端本地均为 Domain0，经各自定向 bridge 接共享 Domain40；任务话题采用 Reliable/Volatile。TF、图像、costmap、速度和 Nav2 action 留在各自本机。

本轮使用 share_c_coordinates=false、SYNC_LOCAL_C。网络命令只表达“找 B”“找 C”“接近本机 C”“退出”等意图；位置字段无效且置零。仍检查任务、命令序号、机器人身份、地图版本和 simulation 标志，不能只看消息字段指纹判断两端兼容。

资源许可有两条必须保留的规则：

- 门通行：取得许可，整机退出并释放后，恢复原主任务。
- 篮子：许可贯穿 C 接近、放入和退出；EXIT 保留原放入命令的 parent_command_id 和 token。搜索及 A/B 接近阶段不提前申请篮子许可。

Ranger 搭建时建议按依赖顺序完成：

1. 合并公共任务代码和消息语义，保留 Ranger 自己的底层、单机栈和参数。
2. 实现 Ranger adapter，并接入 AgentNode 的 Ranger live 分支；替换 Go2 专属 observer 和运动占用检查。
3. 配置本机地图与几何：robot_ranger、地图身份/摘要、source_robot=ranger 的家具标注、footprint、costmap，以及本地资源多边形、门退出点和 C 退出点。同一资源 ID 必须对应同一实物。
4. 先验证本地接口与 fake 流程，再核对定向桥接，最后进行真实双机验收。当前模式无需数值地图对齐。

完整同步清单和字段约定见 Ranger 最小接入说明 (docs/multi_agent/ranger_handoff.md:91)。公共包仍依赖 vlm_nav 的公共 Python 工具，应按需合并兼容代码，避免整体覆盖 Ranger 分支。

目前已验证 Go2/公共层及 fake Ranger，Ranger 真实 adapter 尚未接入。此次仅核对代码和文档，未运行 Ranger、ROS 通信或真机验证。
