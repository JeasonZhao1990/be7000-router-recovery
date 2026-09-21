# 脚本说明

## 可直接用于只读检查

- `audit-current-state.sh`：核对当前 R3/R6/R10/IPv6 guard/SimpleDocker/OpenList、Docker 官方检查、Family policy、UCI 持久化入口和 TUN 状态。
- `audit-mount-sources.sh`：扫描所有容器挂载，输出不符合小米 USB/socket 规则的来源。

## 有状态操作，必须先读脚本

仓库历史脚本：

- `stop-r10-overlay.sh --confirm`：只停 R10 rules/core，保留 R6 与 IPv6 guard。
- `start-r10-overlay.sh --confirm`：只恢复已经存在的 R10 容器，并验证监听和规则。

当前 R3 Family 的生产脚本实际存放于路由器：

```text
/data/be7000-r3-family/
```

包括：

```text
apply-core.sh
apply.sh
rollback.sh
restore.sh
firewall-hook.sh
```

这些脚本与现场接口、策略表、容器名称和固件规则高度耦合。本仓库当前记录其行为和恢复顺序，不伪造一份脱离现场验证的“通用安装器”。

## 参考脚本

`reference/` 保存旧 R6/R10/IPv6 guard 的脱敏副本。它们依赖现场镜像、USB bundle、接口名和哈希，不是通用安装器。

复制到路由器时：

- 必须放在 USB 或 `/data` 持久路径；
- 不要从 `/tmp` bind mount 到长期容器；
- 重新计算并核对完整性；
- 写操作前先运行只读审计。

## 安全边界

仓库不保存：

- VLESS/Mihomo 真实 `config.json`；
- 节点域名或服务器公网地址；
- UUID / Reality 参数；
- 规则数据库；
- SSH 密钥；
- 完整日志；
- 设备 MAC 或家庭公网 IPv6 前缀。
