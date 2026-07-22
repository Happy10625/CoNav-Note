# Co-Nav2 快速启动脚本

## 一键按顺序启动

```bash
cd /home/isee-cdh/松灵小车/conav_scripts
./start_all.sh
```

脚本依次打开相机、Ranger、Livox、FAST_LIO、统一 TF/识别、二维地图、Nav2 和两个监控终端。每一步会等待关键话题出现；已经正常运行的节点会跳过。

启动命令如果报错，终端会停留并显示退出码，不会自动闪退。处理错误后按 Enter 才会关闭窗口。

一键启动只启动节点，绝不会自动让小车运动。

## 启动后检查

```bash
./check_all.sh
```

所有项目均显示绿色“通过”后，才能执行识别测试。

## 启用 chair 原地识别

```bash
./arm_chair_test.sh
```

脚本会重新执行检查，并要求手工输入大写 `ARM`。

## 立即软件停车

```bash
./stop_robot.sh
```

紧急情况下优先使用实体急停。

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
