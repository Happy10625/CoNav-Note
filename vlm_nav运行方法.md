按以下终端顺序运行。

  ### 终端 1：D435

```bash
  cd /home/isee-pst/unitree_ros2
  source /opt/ros/humble/setup.bash
  source go2_ws/install/setup.bash
  source VLM_Nav/scripts/go2_network_env.sh

  VLM_Nav/scripts/01_camera.sh
```



  ### 终端 2：生成 preflight 报告

```bash
 cd /home/isee-pst/unitree_ros2/VLM_Nav
  source /opt/ros/humble/setup.bash
  source ../go2_ws/install/setup.bash
  source /home/isee-pst/venv/co-nav-real/bin/activate
  source scripts/go2_network_env.sh

  REPORT=/tmp/go2_formal_preflight_$(date +%Y%m%d_%H%M%S).json

  PYTHONPATH=. python -m vlm_nav.go2_sensor_preflight \
    --config config/go2_preflight.yaml \
    --duration 60 \
    --output "$REPORT"

  echo "$REPORT"
```



  ### 终端 3：启动 Go2 FAST-LIO、SLAM、Nav2

```bash
  cd /home/isee-pst/unitree_ros2
  source /opt/ros/humble/setup.bash
  source go2_ws/install/setup.bash
  source VLM_Nav/scripts/go2_network_env.sh

  CALIBRATION=/home/isee-pst/unitree_ros2/VLM_Nav/config/go2_calibration.yaml
  REPORT=/tmp/go2_formal_preflight_YYYYMMDD_HHMMSS.json

  ros2 launch vlm_nav go2_system.launch.py \
    target_stage:=nav2 \
    calibration_file:="$CALIBRATION" \
    sensor_preflight_report:="$REPORT"
```

  Bridge 会继续保持 dry_run=true、DISARMED。

  ### 终端 4：启动 VLM 节点

```bash
 cd /home/isee-pst/unitree_ros2
  source /opt/ros/humble/setup.bash
  source go2_ws/install/setup.bash
  source /home/isee-pst/venv/co-nav-real/bin/activate
  source VLM_Nav/scripts/go2_network_env.sh

  export DASHSCOPE_API_KEY='你的API_KEY'
  export DASHSCOPE_WORKSPACE_ID='你的工作空间ID'
  export DASHSCOPE_MODEL='qwen3-vl-flash'

  ros2 launch vlm_nav go2_vlm.launch.py \
    calibration_file:=/home/isee-pst/unitree_ros2/VLM_Nav/config/go2_calibration.yaml \
    target_description:="red chair" \
    enabled:=false
```

  先检查：

  ros2 topic echo /vlm_nav/system_ready
  ros2 topic echo /vlm_nav/nav_ready
  ros2 topic echo /vlm_nav/go2_bridge_state
  ros2 topic echo /vlm_nav/state
