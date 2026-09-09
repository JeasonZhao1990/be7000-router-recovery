# Security policy

本仓库只保存经过脱敏的恢复方法。

禁止提交：

- VLESS、VMess、Trojan、Clash 或 Mihomo 的完整节点/订阅；
- UUID、Reality public key、short ID、服务器域名和公网地址；
- SSH 私钥、完整 `authorized_keys`、密码和访问令牌；
- 用户邮箱、真实姓名、设备 MAC、磁盘 UUID 和公网 IPv6 地址；
- 浏览器登录态、SimpleDocker JWT 或 GitHub token；
- 未审查的容器配置、日志转储或 shell 历史。

提交前应使用 GitHub Secret Scanning 或本地秘密扫描工具，至少覆盖代理分享链接、PEM/OpenSSH 私钥头、Authorization 请求头、令牌和密码字段；不要只依赖人工检查。

任何实际密钥都应保存在本机受保护目录中，而不是仓库内。
