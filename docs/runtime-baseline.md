# 修复完成后的运行基线

## 环境

- 设备：Xiaomi BE7000（RC06）
- 固件：1.1.38 稳定版
- 内核：5.4.164 aarch64
- Docker Engine：20.10.17
- Docker 数据目录：USB 存储下的 `mi_docker/lib/docker`
- `/etc`：启动后重建的临时文件系统
- 持久化配置：优先放在 `/data` 或 USB 存储

## 当前运行容器

2026-09-21 收尾时，生产相关容器为：

```text
be7000-family-tun-r3-unified
be7000-family-proxy-core-r6-20260907
be7000-family-proxy-rules-r6-20260907
be7000-family-override-core-r10-20260911
be7000-family-override-rules-r10-20260911
be7000-family-ipv6-wan-guard-r17-20260908
simple-docker
openlist
```

R1/R2 测试容器已删除：

```text
be7000-family-tun-r1-lab
be7000-family-tun-r2-hostcanary
```

删除的只是容器实例；测试目录保留，且没有删除与 R3/R6/R10 共用的 Mihomo image。

## 分层职责

### R3 unified TUN

当前 `br-lan` 的主生产路径：

- host network；
- Mihomo TUN：`b7g-tun-r3`；
- MTU 1400；
- `auto-route=false`；
- `auto-redirect=false`；
- `strict-route=true`；
- IPv4/IPv6 与 DNS IPv6 均开启；
- VLESS UDP 开启；
- restart policy 为 `always`；
- `HOME-VLESS` 节点入口当前使用 `ip-version: ipv4`。

`ip-version: ipv4` 只影响 R3 到代理节点的接入地址族，不关闭客户端 IPv6，也不改变目标网站是否可通过代理访问 IPv6。

### Family policy

持久化目录：

```text
/data/be7000-r3-family/
```

职责：

- `br-lan` IPv4 公网流量进入独立策略路由表；
- 当前 `br-lan` 全球 IPv6 `/64` 到 `2000::/3` 进入同一 TUN 策略；
- 动态发现当前 LAN IPv6 前缀；
- DNS 53 导入 R3；
- 建立 TUN FORWARD 允许规则；
- 让 `br-lan` 在旧 R6/R10 链顶部 bypass；
- IPv4 建立独立 fail-closed WAN guard；
- 与原 IPv6 WAN guard 共同防止直连泄漏。

现场策略表为 `2074`。这是当前实现细节，不应与固件已有表冲突。

### R6 / R10

R6/R10 仍保留：

- `br-miot` 旧生产兼容路径；
- R3/Family 故障时的回落价值；
- R10 的 HTTPS `override-destination` 能力。

`br-lan` 正常情况下已由 Family/R3 提前接管，因此旧 R6/R10 对 `br-lan` 不再是主路径。

### IPv6 guard

`be7000-family-ipv6-wan-guard-r17-20260908` 继续存在：

- 阻断 LAN/MIoT 直接向 PPPoE WAN 泄漏全球 IPv6；
- 保留 ULA/link-local；
- 在 firewall reload 或启动恢复窗口充当 fail-closed 防线。

### SimpleDocker 与 OpenList

- `simple-docker`：容器管理界面；
- `openlist`：独立应用容器，不参与透明代理策略。

## 持久化入口

UCI firewall include：

```text
firewall.auto_ssh.path=/data/auto_ssh/auto_ssh.sh
firewall.auto_ssh.reload=1

firewall.r3_family.path=/data/be7000-r3-family/firewall-hook.sh
firewall.r3_family.reload=1
```

Family restore 使用锁和重试机制，允许 Docker/Mihomo/旧规则链在启动初期尚未准备好。

## 网络目标

- 中国大陆域名/IP：DIRECT；
- 其他 IPv4/IPv6：`HOME-VLESS`；
- 局域网、本地发现、智能家居本地通信：直连；
- `br-lan` DNS A/AAAA 与数据路径使用同一规则；
- `br-miot` 暂时继续旧 R6/R10；
- 不允许客户端公网流量因为 R3 未恢复而直接从 WAN 泄漏。

## 已知限制

当前仍是单一 `HOME-VLESS` 出口节点。实测节点接入 RTT 较高，IPv4 路径优于 IPv6 路径但仍可能出现国际线路抖动，因此 ChatGPT、Google、GitHub 的 TLS/TTFB 偶尔变慢。

当前通过 `ip-version: ipv4` 降低双栈节点接入抖动，但这不是节点质量问题的根本解决方案。

## 健康检查

```sh
/etc/init.d/mi_docker check_integrity
echo "integrity_exit=$?"

/etc/init.d/mi_docker is_running
echo "running_exit=$?"

uci -q show firewall.auto_ssh
uci -q show firewall.r3_family
```

Docker 两项退出码应为 `0`。

R3/Family：

```sh
ip link show b7g-tun-r3
ip route show table 2074
ip -6 route show table 2074
ip rule show
ip -6 rule show
```

完整只读审计可使用：

```sh
scripts/audit-current-state.sh
```
