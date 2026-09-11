# 故障排查索引

## 小米后台提示 Docker 文件缺失，但容器仍运行

优先运行官方 `check_integrity`，再检查所有停止容器的挂载。不要立即卸载 Docker，也不要先修改状态位。

## 清理后页面仍异常

1. 确认没有新的临时容器挂载 `/`、`/dev`、`/sys` 或 `/proc`；
2. 运行 `/etc/init.d/mi_docker check_integrity`；
3. 运行 `/etc/init.d/mi_docker is_running`；
4. 两者为 0 后强制刷新浏览器页面。

## `ssh_en=1` 但 22 端口关闭

检查 `/etc/init.d/dropbear` 是否仍包含 release 渠道直接返回的逻辑，并确认 RSA 主机密钥不是空文件。

## 容器内出现 `/dev/nvram: Operation not permitted`

普通容器无法访问 NVRAM。不要把该错误解释为 NVRAM 损坏。立即启用阶段需要受控的一次性维护环境映射 `/dev/nvram`；执行完成后必须删除维护容器，避免再次触发小米挂载检查。

## SSH 报 `no matching host key type found`

连接时增加：

```text
-o HostKeyAlgorithms=+ssh-rsa
```

## SSH 报 `Permission denied (publickey)`

旧版 Dropbear 可能不接受 Ed25519 用户密钥。使用 RSA-3072 专用用户密钥，并增加：

```text
-o PubkeyAcceptedAlgorithms=+ssh-rsa
```

同时检查 `authorized_keys` 是否为 600 权限。

## 维护容器导致 Docker 页面再次变灰

确认维护任务结束后，检查它是否从 `/tmp` 或系统路径挂载脚本。正式容器应迁移到 USB 路径；确认为无数据卷的临时容器可先归档再删除，删除时不使用 `-v`。随后重新执行官方完整性检查。

## ChatGPT App 提示“网络提供非预期的 SSL 证书”

本次不是中间人证书，而是污染 DNS 让 HTTPS 连接指向错误原始 IP，透明重定向后 Mihomo 默认仍使用该错误目的地址。R10 HTTPS 层启用 `override-destination` 后，由嗅探到的真实域名重新解析目标，120 秒手机金丝雀和 35 分钟全家庭容量测试均通过。

先检查 R10 是否存在且运行，再查日志；不要立即改系统证书或关闭 ChatGPT 的证书校验。

## 桌面 ChatGPT 反复显示 Reconnecting

2026-09-11 曾观察到单一 VLESS 节点对 Cloudflare 连接集中返回 `EOF`、`connection reset by peer` 和超时。该现象与 Wi-Fi 断开不同，节点恢复后长连接可自行恢复。

当前未部署第二节点自动切换。如果频繁复现，应先保存 R10 日志，再准备第二个独立节点组成 fallback；不要通过叠加更多防火墙规则处理出口服务器故障。

## 运行约 26 分钟后全家断网

历史 R8 核心曾因容器 `nofile=1024` 出现 `socket: too many open files`。修正版使用 `nofile=8192:8192`，35 分钟容量金丝雀峰值约 5170，并带自动回滚。重新创建 R10 时不得遗漏该限制。

## 只回滚 R10，保留 R6

先停止 R10 rules，让它清理自己的 TCP/443 规则，再停止 R10 core。不要先停止 R6。仓库中的 `scripts/stop-r10-overlay.sh` 带显式确认门。

## 禁止事项

- 不运行 `docker system prune`；
- 不批量删除停止容器；
- 不从 `/tmp` 挂载常驻容器脚本；
- 不删除 Docker 数据目录；
- 不把代理凭据写入 Git；
- 不在缺少回滚路径时改防火墙或 SSH；
- 不为验证持久化而贸然重启承载智能家居的路由器。
