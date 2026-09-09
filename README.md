# Xiaomi BE7000 Docker and SSH recovery notes

这是小米 BE7000（RC06）路由器的恢复记录，整理自一次真实修复过程。

最终结果：

- 不重启路由器、不拔移动硬盘；
- 恢复小米后台的 Docker 正常状态；
- 保留既有 Docker 容器和数据卷；
- 启用仅密钥登录的 SSH；
- 保留现有透明代理服务，不重新部署。

## 文档导航

- [Docker 页面误报修复](docs/docker-ui-recovery.md)
- [SSH 开启与持久化](docs/ssh-persistence.md)
- [当前运行基线](docs/runtime-baseline.md)
- [故障排查索引](docs/troubleshooting.md)
- [敏感信息规则](SECURITY.md)

## 重要原则

1. 先做只读检查，再修改。
2. 删除容器前必须核对名称、状态和挂载；禁止对未知容器使用批量删除。
3. 删除临时容器时不使用 `-v`，避免删除数据卷。
4. 不建议把 `valid_mountpath()` 永久改成无条件成功；本次采用清理违规临时容器的最小修复。
5. 本仓库不包含代理节点、订阅、私钥、设备 MAC、磁盘 UUID 或公网地址。

## 已验证边界

Docker 官方完整性检查、Docker 运行状态、SSH 端口和密钥登录均已现场验证。SSH 的开机恢复文件已经落盘并检查存在，但为了避免影响智能家居，本次没有通过重启路由器验证开机恢复。
