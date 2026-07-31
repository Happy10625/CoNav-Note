```bash
# 关闭vscode
pkill code

# 检查缓存
ls ~/.config/Code/

# 清除缓存
rm -rf ~/.config/Code/Service\ Worker/


# 若仍失败，清理webview cache
rm -rf ~/.config/Code/Cache/
rm -rf ~/.config/Code/CachedData/
# 清除后重启code
# 这次只完成第一步清理已经可以行动了

# 重新启动
code
```