查看piper各关节和夹爪状态以及进行控制都需要两个终端A和B，B终端用于查看状态，也可用于诊断
1. 查看当前角度等

控制电脑 Bash 终端 A：

cd /home/isee-pst/unitree_ros2/piper
bash piper_go2.sh inspect

另开 Bash 终端 B，保持诊断运行：

cd /home/isee-pst/unitree_ros2/piper
bash piper_go2.sh diagnostics
出现 OBSERVING 后，查看以下字段：

| 字段 | 含义 |
|---|---|
| joints_deg | J1～J6 当前角度，单位 ° |
| joints_enabled | 六个关节的使能情况，true 为已使能 |
| gripper_width_mm | 夹爪反馈开口，单位 mm |
| gripper_enabled | 夹爪是否使能 |
| gripper_torque_nm | 夹爪反馈力矩，单位 N·m |
| ctrl_mode | 当前控制模式 |
| arm_status、err_code | 机械臂状态与错误码 |
| motion_status | 运动状态 |
| missing_feedback | 缺失或不新鲜的反馈；正常应为 [] |

若显示 WAIT_IO 或 WAIT_FEEDBACK，根据同条日志中的原因排查；字段为 null 表示当前没有有效反馈，不能当成零值。

