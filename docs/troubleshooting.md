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

确认维护任务结束后，删除确切的已停止维护容器，不使用 `-v`。随后重新执行官方完整性检查。

## 禁止事项

- 不运行 `docker system prune`；
- 不批量删除停止容器；
- 不删除 Docker 数据目录；
- 不把代理凭据写入 Git；
- 不在缺少回滚路径时改防火墙或 SSH；
- 不为验证持久化而贸然重启承载智能家居的路由器。
