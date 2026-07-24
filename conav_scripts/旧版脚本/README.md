# Co-Nav2 快速启动脚本

## 一键按顺序启动

```bash
cd /home/isee-cdh/松灵小车/conav_scripts
./start_all.sh
```

脚本依次打开相机、Ranger、Livox、FAST_LIO、统一 TF/识别、二维地图、Nav2、
两个监控终端和 RViz 验证终端。RViz 会在地图与 Nav2 就绪后启动；已经正常运行
的节点会跳过。

Ranger 启动前会自动检查 `can0`：状态为 `DOWN` 时执行 `sudo ip link set can0 up type can bitrate 500000`（终端会要求输入 sudo 密码），状态为 `UP` 时直接继续。

启动命令如果报错，终端会停留并显示退出码，不会自动闪退。处理错误后按 Enter 才会关闭窗口。

一键启动只启动节点，绝不会自动让小车运动。

## 启动后检查

```bash
./check_all.sh
```

所有项目均显示绿色“通过”后，才能执行识别测试。

## 启用 chair 识别与接近

```bash
./arm_chair_test.sh
```

脚本会重新执行检查，并要求手工输入大写 `ARM`。

## 立即软件停车

```bash
./stop_robot.sh
```

紧急情况下优先使用实体急停。

## RViz 辅助验证

`start_all.sh` 会自动执行 `10_rviz.sh`。RViz 固定坐标系为 `map`，默认显示：

- `/map` 二维地图与 `/scan`
- `/cloud_registered` 注册点云
- 完整 TF 树和 `/fastlio/odom`
- `/semantic_explorer/markers` 中的目标与导航候选
- `/camera/color/image_raw` RGB 图像

如果单独启动：

```bash
./10_rviz.sh
```

## 单独启动某个终端

```bash
./01_camera.sh
./02_ranger.sh
./03_livox.sh
./04_fastlio.sh
./05_semantic_tf.sh
./06_mapping_2d.sh
./07_nav2.sh
./08_watch_state.sh
./09_watch_odom.sh
```

正常冷启动时必须按照编号顺序运行。



## 当前正确的重启方式

`stop_robot.sh` 不是“关闭全部节点”，只是让小车停止。

如果要完整重新启动，应：

1. 先执行 `stop_robot.sh`。
2. 在原来的终端 2 按 `Ctrl+C`，确保 Ranger 节点退出。
3. 关闭其他原 launch 终端。
4. 确认：

```
ros2 node list | grep ranger
ros2 topic info /odom
```

应当没有 Ranger 节点和 `/odom` 发布者。

1. 再运行：

```
./start_all.sh
```
