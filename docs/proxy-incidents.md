# 透明代理故障与容量记录

## 最终目标

- 所有家庭设备使用同一规则；
- 中国大陆域名/IP 直连；
- 其他 IPv4 流量代理；
- 局域网和智能家居本地通信直连；
- IPv6 WAN 阻断，避免绕过 IPv4 代理；
- 不重启路由器，不拔移动硬盘。

## 关键故障与结论

### TPROXY 在设备上不可作为最终 IPv4 方案

内核具备 TPROXY、ipset 和策略路由能力，但真实转发路径、硬件加速和固件行为导致多轮 TPROXY/TUN 金丝雀不稳定。最终 IPv4 采用 TCP REDIRECT + DNS 劫持，并拒绝 UDP/443 触发 QUIC 回退。

### IPv6 代理尝试不稳定

VLESS 出口本身支持 IPv6，但路由器侧 IPv6 TUN/TPROXY 路径不稳定。最终不做代理 IPv6，而是在 WAN 转发层阻断全球 IPv6，保留本地 IPv6。

### ChatGPT 非预期 SSL 证书

原因是污染 DNS 与透明代理原始目标不一致。R10 对 TCP/443 启用 Mihomo `override-destination`，按嗅探域名重新解析后恢复 ChatGPT App。

### R8 文件句柄耗尽

R8 运行约 26 分钟后出现 `socket: too many open files`，容器上限为 1024。修正版设置 `nofile=8192:8192`；35 分钟全家庭容量金丝雀通过，观测峰值约 5170，并验证自动回滚。

### 单节点瞬时重置

R10 运行期间曾观察到 VLESS 出口对 Cloudflare 批量返回 EOF、reset 和 timeout，桌面 ChatGPT 短时反复重连，节点恢复后自动恢复。当前仍是单节点架构，这是已知单点；后续若增加第二节点，应先做独立金丝雀和长时间容量验证。

## 验收结果

现场测试覆盖多台设备：百度、Google、Wikipedia、ChatGPT App、桌面 ChatGPT、常用应用和米家均可使用。`api.ipify.org` 显示代理 IPv4；`api6.ipify.org` 按当前 IPv6 防泄漏设计不可访问。
