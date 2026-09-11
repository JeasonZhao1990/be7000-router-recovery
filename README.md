# Xiaomi BE7000 Docker、SSH 与家庭透明代理恢复手册

这是小米 BE7000（RC06）路由器的恢复记录，整理自一次真实修复过程。

截至 2026-09-11 的现场结果：

- 不重启路由器、不拔移动硬盘；
- 恢复小米后台的 Docker 正常状态；
- 将 126 个无数据卷的测试容器归档后删除；
- 启用仅密钥登录的 SSH；
- 保留 5 个正式代理/防护容器与 `simple-docker`；
- 中国大陆直连、其他 IPv4 TCP/HTTPS 代理、局域网直连；
- 为避免 IPv6 绕过代理，阻断 LAN/IoT 到 WAN 的全球 IPv6，保留本地 IPv6；
- 不重启路由器、不拔移动硬盘。

## 文档导航

- [Docker 页面误报修复](docs/docker-ui-recovery.md)
- [SSH 开启与持久化](docs/ssh-persistence.md)
- [当前运行基线](docs/runtime-baseline.md)
- [完整恢复顺序与回滚](docs/recovery-runbook.md)
- [测试容器清理记录](docs/container-cleanup-20260911.md)
- [透明代理故障与容量记录](docs/proxy-incidents.md)
- [故障排查索引](docs/troubleshooting.md)
- [敏感信息规则](SECURITY.md)
- [脚本说明](scripts/README.md)

## 重要原则

1. 先做只读检查，再修改。
2. 删除容器前必须核对名称、状态、重启策略和数据卷；禁止对未知容器使用批量删除。
3. 删除临时容器时不使用 `-v`，避免删除数据卷。
4. 不建议把 `valid_mountpath()` 永久改成无条件成功；本次采用清理违规临时容器的最小修复。
5. 所有容器启动脚本必须位于 USB 存储路径，不能从 `/tmp`、`/root` 或系统目录 bind mount。
6. 本仓库不包含代理节点、订阅、私钥、设备 MAC、磁盘 UUID 或公网地址。

## 已验证边界

Docker 官方 `check_integrity`、`is_running`、6 个容器状态、挂载路径、规则标记、SSH 端口和密钥登录均已现场验证。SSH 的开机恢复文件已经落盘并检查存在，但为了避免影响智能家居，没有通过整机重启验证开机恢复。

> 这是特定 BE7000、固件和现场路径的恢复记录。执行任何写操作前先运行只读审计，并根据实际 USB 路径、镜像 ID 和容器状态调整；不要整段盲目复制。
