Unitree 官方 `unitree_ros` 仓库中的 Go2 URDF 目前能看到这些外参：

```xml
<joint name="imu_joint" type="fixed">
    <origin xyz="-0.02557 0 0.04232" rpy="0 0 0" />
    <parent link="base" />
    <child link="imu" />
</joint>

<joint name="radar_joint" type="fixed">
    <origin xyz="0.28945 0 -0.046825" rpy="0 2.8782 0" />
    <parent link="base" />
    <child link="radar" />
</joint>

<joint name="front_camera_joint" type="fixed">
    <origin xyz="0.32715 -0.00003 0.04297" rpy="0 0 0" />
    <parent link="base" />
    <child link="front_camera" />
</joint>
```

也就是，以 `base` 为父坐标系：

| 传感器           | xyz / m                        | rpy / rad        |
| ---------------- | ------------------------------ | ---------------- |
| IMU              | `(-0.02557, 0, 0.04232)`       | `(0, 0, 0)`      |
| 内置雷达 `radar` | `(0.28945, 0, -0.046825)`      | `(0, 2.8782, 0)` |
| 前置相机         | `(0.32715, -0.00003, 0.04297)` | `(0, 0, 0)`      |

这里的 `radar` 一般指 **Go2 原厂机头内置的 4D LiDAR/雷达模块坐标系**

由此计算得LiDAR 数据 → IMU 坐标系对应的 TF 参数为：

```
translation:
x =  0.315020
y =  0.000000
z = -0.089145

rotation RPY:
roll  = 0
pitch = 2.8782
yaw   = 0s
```