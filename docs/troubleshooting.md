# 故障排查索引

## 小米后台提示 Docker 文件缺失，但容器仍运行

优先运行：

```sh
/etc/init.d/mi_docker check_integrity
/etc/init.d/mi_docker is_running
```

再检查所有容器挂载。

不要立即卸载 Docker，也不要先修改状态位。

## 清理后页面仍异常

1. 确认没有新的长期容器挂载 `/`、`/dev`、`/sys`、`/proc` 或从 `/tmp` bind mount；
2. 运行官方 `check_integrity`；
3. 运行 `is_running`；
4. 两项均为 0 后再刷新管理页面。

## SSH reboot 后不可用

检查：

```sh
uci -q show firewall.auto_ssh
test -s /data/auto_ssh/auto_ssh.sh
test -s /data/auto_ssh/authorized_keys
```

当前 SSH 已通过真实整机 reboot 验证。若失效，应先检查 UCI firewall include 是否仍存在，而不是重新生成密钥。

## SSH 报 `no matching host key type found`

Windows 新版 OpenSSH 对旧 Dropbear 需要：

```text
-o HostKeyAlgorithms=+ssh-rsa
```

必要时用户密钥也增加：

```text
-o PubkeyAcceptedAlgorithms=+ssh-rsa
```

## R3 容器运行但全家外网不通

按顺序只读检查：

```sh
ip link show b7g-tun-r3
ip route show table 2074
ip -6 route show table 2074
ip rule show
ip -6 rule show
```

再查看 Family restore 日志。

如果 table 2074 或 `br-lan` ingress policy 缺失，优先运行 Family restore。

不要先重建 R3 容器。

## firewall reload 后短暂断网

Family restore 在 reload 后需要重新等待 R3/R6/R10/guard 就绪。

短暂恢复窗口是预期现象，但最终应自动成功。

如果持续失败，再执行 Family rollback，并确认旧 R6/R10 路径。

## reboot 后 IPv6 前缀变了

这是 PPPoE/ISP 正常行为。

Family 应自动发现新的 `br-lan` global `/64`。检查 IPv6 rule 与 table 2074，不要把旧前缀手工写回去。

## ChatGPT / Google / GitHub 能打开但很慢

不要第一时间改 MTU、关客户端 IPv6 或改 Family。

建议按以下顺序：

1. route-get 确认客户端公网流量进入 table 2074/TUN；
2. R3 日志确认目标站点命中 `HOME-VLESS`；
3. Windows curl 比较 connect/TLS/TTFB/total；
4. 用国内 DIRECT 站点做基线；
5. 测 `HOME-VLESS` 节点 IPv4/IPv6 RTT 和丢包；
6. `netstat` 确认 Mihomo 实际使用哪个节点地址族；
7. 必要时做 `ip-version: ipv4` 可回滚 A/B。

如果 TCP connect 很快，但 TLS/TTFB 随机数秒，且国内 DIRECT 正常，优先怀疑节点/国际线路而不是 LAN/TUN。

## 如何判断 IPv4-only A/B 是否生效

客户端 IPv6 不需要关闭。

只看 `HOME-VLESS` 节点的新连接：

```sh
netstat -nt 2>/dev/null | grep ESTABLISHED
```

如果候选节点有 A/AAAA，切换后新 ESTABLISHED 应只剩节点 IPv4。

不要用旧的 `TIME_WAIT` 判断当前是否仍在走 IPv6。

## ChatGPT App 提示“网络提供非预期的 SSL 证书”

历史问题是污染 DNS 与透明代理原始目标不一致。

旧 R10 通过 `override-destination` 修复。

不要立即改系统证书或关闭 ChatGPT 证书校验。

## 桌面 ChatGPT 反复 Reconnecting

先区分：

- Wi-Fi/LAN 断开；
- R3/Family 丢失；
- `HOME-VLESS` 节点 EOF/reset/timeout。

如果国内 DIRECT 正常、R3 route 正常但外网长连接集中失败，优先检查节点线路。

## 米家异常

先确认设备是否实际位于 `br-miot`。

当前现场多数 IoT 与米家中心网关位于主 2.4G/`br-lan`，而不是专用 MIoT 网络。

不要因为存在 `br-miot` 接口就假设米家一定走 `br-miot`。

## 只回滚 R3/Family，保留 R6/R10

使用：

```text
/data/be7000-r3-family/rollback.sh
```

回滚前保持 SSH，会话中确认 R6/R10 正常。

不要先删除 R6/R10 容器。

## 禁止事项

- 不运行 `docker system prune`；
- 不批量删除未知停止容器；
- 不使用 `docker rm -v` 清理测试容器；
- 不从 `/tmp` 挂载长期容器脚本；
- 不删除 Docker 数据目录；
- 不把代理凭据写入 Git；
- 不删除固件自有 IPv6 policy rule；
- 不在缺少回滚路径时改防火墙、SSH 或主路由；
- 不用修改路由表来掩盖代理节点线路质量问题。
