# Ranger-VLM_Nav 迁移工具

在旧电脑执行：

```bash
bash 迁移工具/01_旧电脑生成迁移包.sh
```

生成物位于 `迁移输出/`，包括 `.tar.zst` 和对应 `.sha256`。复制到新电脑后：

```bash
sha256sum -c Ranger-VLM_Nav_core_时间.tar.zst.sha256
tar --zstd -xf Ranger-VLM_Nav_core_时间.tar.zst
cd Ranger-VLM_Nav_core_时间
bash 02_新电脑恢复源码.sh
bash 02_新电脑恢复源码.sh --apply
```

第一次恢复命令是只读预演，第二次才实际复制。rosbag 与密钥均不在核心包中。
