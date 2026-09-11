# 脚本说明

## 可直接用于只读检查

- `audit-current-state.sh`：核对 6 个正式容器、官方 Docker 检查、规则标记和监听端口。
- `audit-mount-sources.sh`：扫描所有容器挂载，输出不符合小米 USB/socket 规则的来源。

## 有状态操作，必须先读脚本

- `stop-r10-overlay.sh --confirm`：只停 R10 rules/core，保留 R6 与 IPv6 防护。
- `start-r10-overlay.sh --confirm`：只恢复已经存在的 R10 容器，并验证监听和规则。

## 参考脚本

`reference/` 保存当前正式 guard/core 的脱敏副本。它们依赖现场镜像、USB bundle、接口名和哈希，不是通用安装器，也不会自动创建容器。复制到路由器时必须放到 USB 路径，并重新计算 SHA256。

仓库不保存 VLESS `config.json`、规则数据库、SSH 密钥或完整日志。
