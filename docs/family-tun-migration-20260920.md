# R3 Family TUN 双栈迁移、持久化与性能诊断（2026-09-20～2026-09-21）

本文记录 Xiaomi BE7000 从旧的 R6/R10 IPv4 REDIRECT + IPv6 WAN guard，演进到 R3 Mihomo unified TUN 的完整生产迁移。

本文按公开仓库标准脱敏，不记录 VLESS 节点域名、服务器公网地址、UUID、Reality 参数、SSH 密钥、设备 MAC、家庭公网 IPv6 前缀或完整日志。

## 1. 迁移目标

主 LAN 的目标拓扑：

```text
br-lan -> Family policy routing -> R3 unified TUN
                               -> CN IPv4/IPv6: DIRECT
                               -> foreign IPv4/IPv6: HOME-VLESS
```

同时要求：

- DNS A/AAAA 与数据流使用同一策略；
- TCP、UDP、QUIC 均能由 R3 处理；
- 不破坏米家和局域网通信；
- firewall reload 后可自动恢复；
- 整机 reboot 后可自动恢复；
- PPPoE 重新拨号导致 IPv6 `/64` 变化时可自动适配；
- 启动和恢复窗口 fail-closed，避免直连泄漏；
- R6/R10 在迁移完成前保留为回退路径。

## 2. 迁移前基线

R6 是稳定的 IPv4 基础层，负责 DNS 劫持和 TCP REDIRECT。R10 只覆盖 TCP/443，启用 `override-destination`，用于修复污染 DNS 与透明代理原始目的地址不一致导致的 ChatGPT/Cloudflare HTTPS 问题。

IPv6 guard 阻断 LAN/MIoT 直接进入 PPPoE WAN 的全球 IPv6，保留 ULA 和 link-local。该方案稳定，但 IPv4 与 IPv6 的处理模型不统一，而且 UDP/QUIC 依赖回退。

## 3. R1：隔离 TUN 实验

R1 不接管家庭生产流量，只验证 Mihomo TUN 能力。

关键条件：

- 独立 TUN 设备；
- MTU 1400；
- `strict-route`；
- DNS hijack；
- IPv4/IPv6 均开启。

验证结果：

- A/AAAA DNS 正常；
- 国外 IPv4 与 IPv6 均可通过 `HOME-VLESS`；
- Mihomo 会创建自己的 IPv6 TUN `oif` policy rule。

结论：TUN 核心能力可用，但不能把 Mihomo 自动路由行为直接原样放进小米生产网络。

## 4. R2：host-network 金丝雀

R2 使用 host network，并关闭 `auto-route` 和 `auto-redirect`，用于拆分：

1. 客户端转发策略；
2. Mihomo 自身出站路由。

验证确认：

- 路由器自身 IPv6 可经 TUN 使用；
- DNS 与 VLESS UDP 可用；
- source-based policy route 可工作；
- 单纯 fwmark 不能覆盖全部目标客户端；
- 即使 `auto-route=false`，Mihomo 仍可能创建 TUN `oif` 相关 IPv6 rule。

因此最终实现不能把 Mihomo 自建 IPv6 rule 的 preference 写死。

## 5. R3：最终统一 TUN

R3 成为 `br-lan` 主生产路径。

主要特征：

```text
network: host
TUN device: b7g-tun-r3
MTU: 1400
auto-route: false
auto-redirect: false
strict-route: true
IPv4: enabled
IPv6: enabled
DNS IPv6: enabled
VLESS UDP: enabled
restart: always
```

R3 不依赖 Mihomo 自动接管 LAN。真正的客户端导流由宿主机 Family policy 完成。

## 6. Family V1：br-lan 统一策略

持久化目录：

```text
/data/be7000-r3-family/
├── apply-core.sh
├── apply.sh
├── rollback.sh
├── restore.sh
└── firewall-hook.sh
```

### 6.1 IPv4

现场使用独立 policy routing table `2074`。

核心行为：

- 私网、链路本地、组播和保留地址继续进入 `main`；
- `br-lan` 公网流量进入 table 2074；
- table 2074 中保留 LAN、MIoT、Docker 和 TUN 自身所需直连路由；
- 公网默认指向 R3 TUN peer。

现场 IPv4 rule 使用独立区间：

```text
20740-20748  reserved/local destinations -> main
20749        iif br-lan -> table 2074
```

### 6.2 IPv4 fail-closed

建立独立 IPv4 WAN guard。其目的不是加速，而是在 Family/TUN 暂时未恢复时，阻止 `br-lan` 公网流量直接从 WAN 泄漏。

### 6.3 IPv6

Family 每次 apply 时动态发现当前 `br-lan` 全球 IPv6 `/64`。

只对：

```text
current br-lan global /64 -> 2000::/3
```

建立 ingress policy，并进入 table 2074。

关键原则：

- 不写死 ISP 当前下发的 `/64`；
- 不删除小米固件已有 IPv6 policy rules；
- Mihomo 自己创建的 TUN `oif` rule 只按语义识别，不持久化硬编码其 preference。

### 6.4 DNS

`br-lan` 的 DNS 53 导入 R3 DNS listener，使 A/AAAA 与实际数据流共享同一 `CN DIRECT / foreign HOME-VLESS` 规则。

### 6.5 与 R6/R10 共存

Family 生效后：

- `br-lan` 在旧 R6/R10 链顶部 bypass；
- R3 TUN FORWARD accept 位于旧 reject/drop 前；
- `br-miot` 继续保留旧 R6/R10；
- R6/R10 不删除，作为兼容和回退路径。

## 7. apply / rollback / restore

`apply-core.sh` 负责：

- 发现当前 LAN IPv4/IPv6；
- 校验 R3/R6/R10/guard；
- 建立 table 2074；
- 建立 IPv4/IPv6 policy；
- 建立 IPv4 fail-closed；
- 导入 DNS；
- 设置 TUN FORWARD；
- 让 `br-lan` 绕过旧 R6/R10。

`apply.sh` 是 fail-safe 包装层：发生错误或信号时自动 rollback，成功后再解除 failsafe。

`rollback.sh` 只清理 Family 自己创建的 route/rule/filter/nat，并恢复旧 `br-lan` 路径，不删除任何生产容器，也不碰固件自有 policy rule。

`restore.sh` 使用锁与重试机制，允许 Docker、R3、R6/R10 和 guard 在启动初期尚未准备好。

## 8. UCI 持久化

Family 通过 firewall include 恢复：

```text
firewall.r3_family.path=/data/be7000-r3-family/firewall-hook.sh
firewall.r3_family.reload=1
```

SSH 同样通过持久化 include：

```text
firewall.auto_ssh.path=/data/auto_ssh/auto_ssh.sh
firewall.auto_ssh.reload=1
```

由于该固件的 `/etc` 会在启动后重建，关键恢复逻辑必须放在 `/data` 或 USB。

## 9. firewall reload 验证

受控 firewall reload 后确认：

- Family hook 被调用；
- restore 成功；
- table/rule/DNS/FORWARD 恢复；
- fail-closed 规则在恢复窗口捕获到本来可能直连泄漏的包；
- 没有长期断网。

## 10. 整机 reboot 验证

后续执行了受控整机 reboot。

实际启动过程出现依赖未就绪：

- 早期 restore 尝试时 R3 尚未运行；
- 随后 R6 旧链尚未准备好；
- restore 自动继续重试；
- 最终成功，无需人工 SSH 救网。

同时 PPPoE 重拨后家庭全球 IPv6 `/64` 发生变化，Family 自动重新发现新前缀并更新 IPv6 rule/table。

因此本次 reboot 验证覆盖：

- Docker 自启动；
- SimpleDocker 自启动；
- R3/R6/R10/IPv6 guard 自启动；
- SSH 恢复；
- Family hook/restore；
- 动态 IPv6 前缀变化；
- 真实客户端重新联网。

## 11. SSH 持久化最终状态

SSH 使用：

```text
/data/auto_ssh/auto_ssh.sh
/data/auto_ssh/authorized_keys
```

整机 reboot 后已实际验证：

- Dropbear 自动恢复；
- 22 端口可用；
- 密钥登录可用；
- Windows 新版 OpenSSH 通过 `ssh-rsa` 兼容选项可重新连接。

这修正了仓库旧文档中“落盘但未做整机重启验证”的限制。

## 12. MIoT / br-miot 探索与回滚

曾制作非持久化 MIoT IPv4 TUN 脚本并现场 apply。

验证了：

- `br-miot` 可建立独立 ingress policy；
- DNS 可导入 R3；
- R6/R10 可对 `br-miot` bypass；
- TUN FORWARD 与 IPv4 fail-closed 可工作。

但现场没有真实 `br-miot` 客户：

- 专用 MIoT 2.4G 接口无关联 station；
- `br-miot` FDB 为空；
- 没有真实业务计数。

随后执行 rollback，确认：

- MIoT policy/rules 清理干净；
- `br-miot` 回到旧路径；
- `br-lan` R3 Family 不受影响。

实际米家设备和米家中心网关位于主 2.4G/`br-lan`，因此主 Family 已覆盖真实业务。最终没有添加 MIoT 持久化 hook。

## 13. R1/R2 清理

R3 完成生产验证后，删除两个停止的测试容器：

```text
be7000-family-tun-r1-lab
be7000-family-tun-r2-hostcanary
```

保留：

- R1/R2 历史配置目录；
- 共用 Mihomo image；
- 所有 production container；
- Docker volume。

## 14. ChatGPT / Google / GitHub 慢速诊断

迁移完成后，电脑访问外网站点出现“能打开但明显慢”。

### 14.1 排除 Family 误路由

确认：

- 客户端公网 IPv4 route 正确进入 table 2074/TUN；
- ChatGPT/OpenAI CDN、Google、GitHub 命中 `HOME-VLESS`；
- 国内域名命中 DIRECT。

因此慢速不是因为外网站点误走 DIRECT。

### 14.2 客户端 IPv4/IPv6 A/B

Windows curl 分别测试 IPv4 与 IPv6。

结果：

- TCP connect 通常只需几十毫秒；
- TLS 与 TTFB 会随机升到数秒；
- 临时关闭客户端 IPv6 后，IPv4 仍能出现数秒 TLS；
- 因此不能把问题简单归因于客户端 IPv6。

### 14.3 国内 DIRECT 基线

国内站点热身后约 `0.2 s` 以内，而 ChatGPT/Google/GitHub 经 `HOME-VLESS` 会出现数秒 TLS/TTFB，GitHub 还曾出现 TLS handshake failure。

问题范围因此收缩到代理出口之后，而不是 WLAN → BE7000 → TUN 的最初 TCP 建连。

### 14.4 节点接入双栈

在不记录实际服务器地址的前提下测得：

- 节点 IPv4 接入 RTT 约 `258 ms`，小样本曾出现丢包；
- 节点 IPv6 接入 RTT 约 `334 ms`；
- `netstat` 证明 Mihomo 默认 dual 模式下实际同时建立节点 IPv4/IPv6 连接。

### 14.5 IPv4-only A/B

为 `HOME-VLESS` 增加：

```json
"ip-version": "ipv4"
```

切换前执行：

1. 备份生产 config；
2. 生成候选 config；
3. 使用 `jsonfilter` 验证；
4. 使用 `mihomo -t` 自检；
5. 重启 R3；
6. 运行 Family restore；
7. 验证 TUN、table 2074 与路由；
8. 确认新 ESTABLISHED 节点连接只剩 IPv4。

A/B 后：

- ChatGPT 5 次请求平均 total 约从 `3.4 s` 下降到 `1.7 s`；
- GitHub 有改善，且未再次出现握手失败；
- Google 仍有明显波动；
- 浏览器主观体感为“稍微变快”。

结论：

- 当前保留 `ip-version: ipv4`；
- Family/TUN/客户端 IPv6 不是主要性能瓶颈；
- 根本限制仍是单节点 RTT 与国际线路质量；
- 后续应优先增加质量更好的独立节点，再做新的 canary。

## 15. 当前生产拓扑

```text
br-lan
  -> Family policy
  -> R3 unified TUN
     -> CN IPv4/IPv6: DIRECT
     -> foreign IPv4/IPv6: HOME-VLESS

br-miot
  -> old R6/R10 compatibility path

IPv6 WAN guard
  -> fail-closed direct-WAN protection
```

## 16. 当前生产容器

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

## 17. 回滚原则

如果 R3/Family 出现生产故障：

1. 保持 SSH 会话；
2. 不删除 R6/R10；
3. 优先运行 Family `rollback.sh`；
4. 恢复旧 `br-lan` REDIRECT 前先确认 R6/R10 正常；
5. 不在同一轮叠加新的 TPROXY/TUN 规则；
6. 不运行 `docker system prune`；
7. 不删除小米固件已有 IPv6 policy rule；
8. 如果只是节点慢，不通过继续修改路由表来“修线路”。

## 18. 后续方向

当前架构已通过 firewall reload、整机 reboot、动态 IPv6 `/64` 变化和真实多设备业务验证。

后续优先级：

1. 保持 R3/Family 稳定；
2. 新增第二个独立 VLESS 节点时先做 isolated canary；
3. 比较 RTT、丢包、TLS/TTFB 与长连接稳定性；
4. 再考虑 selector/fallback；
5. 只有当 `wl13/br-miot` 出现真实 station 时，才重新进行 MIoT 迁移验证。
