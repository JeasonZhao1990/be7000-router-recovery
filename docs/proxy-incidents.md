# 透明代理故障、迁移与容量记录

## 当前目标

- `br-lan` IPv4/IPv6 统一透明代理；
- 中国大陆域名/IP 直连；
- 其他流量通过 `HOME-VLESS`；
- DNS A/AAAA 与数据流策略一致；
- 局域网和智能家居本地通信直连；
- 启动/重载失败时 fail-closed；
- R6/R10 保留作为 `br-miot` 兼容与回退。

## 关键故障与结论

### 早期 TPROXY/TUN 不稳定不代表 TUN 永久不可用

2026-09-11 前的多轮 TPROXY/TUN 金丝雀受真实转发路径、硬件加速和固件行为影响，没有直接成为最终方案，因此当时生产先采用 IPv4 REDIRECT + IPv6 WAN guard。

后续通过 R1 隔离实验、R2 host canary 和 R3 手工 policy routing，把“客户端策略路由”和“Mihomo 自身 TUN 出站”拆开后，R3 unified TUN 最终成功进入生产。

结论：问题不在“TUN 能不能用”，而在必须避开自动路由与固件规则冲突。

### Mihomo TUN IPv6 rule 的 preference 不能写死

即使 `auto-route=false`，Mihomo 仍可能创建 TUN `oif` 相关 IPv6 rule，且 preference 可能随运行环境变化。

生产脚本只按语义识别，不持久化硬编码 preference。

### ChatGPT 非预期 SSL 证书

历史问题是污染 DNS 与透明代理原始目标不一致。

R10 对 TCP/443 启用 `override-destination`，按嗅探域名重新解析后恢复 ChatGPT App。

R3 unified TUN 迁移后 R10 仍保留作为旧路径/回退，不应因为主路径变化就直接删除。

### R8 文件句柄耗尽

历史 R8 运行约 26 分钟后出现 `socket: too many open files`，容器上限为 1024。

修正版将 `nofile` 提升到 `8192:8192`；后续容量金丝雀通过。

### firewall reload 恢复窗口

Family 持久化通过 UCI firewall include + restore 重试。

受控 reload 时，fail-closed 规则出现计数增长，说明恢复窗口确有流量尝试直接离开，但被阻断而不是泄漏。

### PPPoE IPv6 `/64` 会变化

整机 reboot 后 ISP 下发的家庭全球 IPv6 `/64` 发生变化。

Family 没有写死旧前缀，而是重新发现当前 `br-lan` prefix 并更新 IPv6 ingress rule/table，因此无需人工干预。

### `br-miot` 没有真实活动客户端

MIoT IPv4 TUN 脚本已做过 apply/rollback，但专用网络没有 station/FDB/真实业务。

实际米家中心网关与多数 Wi-Fi IoT 位于 `br-lan`，因此主 Family 已覆盖真实业务。

结论：不要为“空网络”增加长期持久化复杂度。

### ChatGPT / Google / GitHub 打开慢

R3 生产稳定后出现“外网能访问但网页慢”。

排查证据：

- 客户端公网 route 正确进入 Family table/TUN；
- Mihomo 日志确认外网站点走 `HOME-VLESS`；
- 国内 DIRECT 热身后很快；
- 外网站点 TCP connect 通常很快，但 TLS/TTFB 会随机升至数秒；
- GitHub 曾出现 TLS handshake failure。

进一步检查节点接入：

- IPv4 RTT 约 `258 ms`，小样本曾出现丢包；
- IPv6 RTT 约 `334 ms`；
- Mihomo 默认 dual 时实际同时建立节点 IPv4/IPv6 连接。

对 `HOME-VLESS` 增加：

```json
"ip-version": "ipv4"
```

A/B 后：

- ChatGPT 平均 total 明显下降；
- GitHub 有改善，未再次出现握手失败；
- Google 仍有明显波动；
- 浏览器主观体感为“稍微变快”。

结论：

- Family/TUN/客户端 IPv6 不是主要慢点；
- 节点 IPv6 接入较差，强制 IPv4 有一定收益；
- 根本瓶颈仍是单节点 RTT 与国际线路质量；
- 后续应增加更好的独立节点，而不是继续叠加路由规则。

## 当前单点

目前仍只有一个 `HOME-VLESS` 出口节点，没有自动节点故障切换。

如果频繁出现 EOF/reset/timeout：

1. 保存 R3 日志；
2. 测节点基础 RTT/丢包；
3. 测 TLS/TTFB；
4. 准备第二节点独立金丝雀；
5. 再考虑 selector/fallback。

不要把出口线路故障误判为路由器防火墙问题。
