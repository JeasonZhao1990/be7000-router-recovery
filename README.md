# Xiaomi BE7000 Docker、SSH 与家庭透明代理恢复手册

这是小米 BE7000（RC06）路由器的一套真实恢复、固化与透明代理迁移记录。仓库最初记录 2026-09-11 的 Docker UI / SSH / R6-R10 恢复；截至 2026-09-21，主 LAN 已进一步完成 R3 Mihomo TUN 双栈迁移、UCI 持久化、firewall reload、整机 reboot、动态 IPv6 前缀适配，以及代理出口性能诊断。

## 当前生产状态

截至 2026-09-21：

- Docker 与 SimpleDocker 正常，官方 `check_integrity` / `is_running` 可用；
- SSH 使用 `/data` 持久化恢复，并已通过整机 reboot 验证；
- `br-lan` 的 IPv4 与全球 IPv6 统一进入 R3 Mihomo TUN；
- 中国大陆域名/IP 直连，其他流量走 `HOME-VLESS`；
- DNS A/AAAA 与数据流使用同一规则体系；
- TCP、UDP、QUIC 均可由 R3 处理；
- IPv4 有独立 fail-closed WAN guard；
- 原 IPv6 WAN guard 继续保留，防止启动/重载窗口直接泄漏到 WAN；
- firewall reload 后 Family 策略可自动恢复；
- 整机 reboot 后 Docker、SSH、R3/R6/R10/IPv6 guard 与 Family 均已验证恢复；
- PPPoE 重拨导致家庭 IPv6 `/64` 变化时，Family 会自动重新发现当前前缀；
- R6/R10 继续保留为 `br-miot` 兼容和故障回退路径；
- `br-miot` 当前没有真实活动客户端，因此没有把 MIoT 迁移长期固化到 R3；
- R1/R2 测试容器已删除，历史配置目录保留；
- `HOME-VLESS` 节点入口当前固定为 `ip-version: ipv4`，用于降低节点双栈接入抖动。

## 文档导航

- [Docker 页面误报修复](docs/docker-ui-recovery.md)
- [SSH 开启与持久化](docs/ssh-persistence.md)
- [当前运行基线](docs/runtime-baseline.md)
- [R3 Family TUN 双栈迁移、持久化与性能诊断](docs/family-tun-migration-20260920.md)
- [完整恢复顺序与回滚](docs/recovery-runbook.md)
- [测试容器清理记录](docs/container-cleanup-20260911.md)
- [透明代理故障、迁移与容量记录](docs/proxy-incidents.md)
- [故障排查索引](docs/troubleshooting.md)
- [敏感信息规则](SECURITY.md)
- [脚本说明](scripts/README.md)

## 当前架构

```text
br-lan
  -> Family policy routing
  -> R3 unified TUN
     -> CN IPv4/IPv6: DIRECT
     -> foreign IPv4/IPv6: HOME-VLESS

br-miot
  -> 旧 R6/R10 兼容路径
  -> 当前无真实活动客户端

IPv6 WAN guard
  -> 保留，作为直接 WAN 泄漏的 fail-closed 防线
```

R6/R10 不应因为 `br-lan` 已迁移就直接删除。它们仍有 `br-miot` 兼容和故障回退价值。

## 重要原则

1. 先做只读检查，再修改。
2. 每次只改变一层，必须保留明确回滚路径。
3. 不运行 `docker system prune`，不对未知容器批量删除。
4. 删除测试容器时不使用 `-v`，避免误删数据卷。
5. 长期容器和脚本必须位于 USB 或 `/data` 持久路径；不要从 `/tmp`、`/root` 或根目录 bind mount。
6. 不删除或覆盖小米固件已有 IPv6 policy rule。
7. Mihomo 自动生成的 TUN IPv6 rule 只按语义识别，不硬编码动态 preference。
8. 如果只是代理节点线路慢，不通过继续叠加路由/防火墙规则来“修线路”。
9. 本仓库不提交代理节点、订阅、UUID、私钥、设备 MAC、磁盘 UUID、公网地址或完整日志。

## 已验证边界

当前状态不是仅凭配置推断，而是经过实际运行验证：

- Docker 官方完整性与运行状态；
- `firewall reload` 后 Family 自动恢复；
- 整机 reboot 后 Docker、SimpleDocker、SSH、R3/R6/R10/IPv6 guard 自动恢复；
- PPPoE 重连后动态 IPv6 `/64` 变化自动适配；
- 多台真实设备与米家网关业务；
- R1/R2 测试容器清理后生产容器保持运行；
- ChatGPT / Google / GitHub 外网慢速问题通过 route、Mihomo 日志、Windows curl、节点 IPv4/IPv6 RTT 和 IPv4-only A/B 进行定位。

> 这是特定 BE7000、固件和现场网络的恢复记录。执行任何写操作前先运行只读审计，并根据实际 USB 路径、镜像 ID、容器状态和接口名调整；不要整段盲目复制。
