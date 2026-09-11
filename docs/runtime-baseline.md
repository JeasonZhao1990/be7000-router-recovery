# 修复完成后的运行基线

## 环境

- 设备：Xiaomi BE7000（RC06）
- 固件：1.1.38 稳定版
- 内核：5.4.164 aarch64
- Docker Engine：20.10.17
- Docker 数据目录：USB 存储下的 `mi_docker/lib/docker`

## 已验证的常驻服务

2026-09-11 最终核验时总计 6 个容器，全部为 `running|restart=always`，停止容器为 0：

```text
simple-docker
be7000-family-proxy-core-r6-20260907
be7000-family-proxy-rules-r6-20260907
be7000-family-ipv6-wan-guard-r17-20260908
be7000-family-override-core-r10-20260911
be7000-family-override-rules-r10-20260911
```

这些名称是本次现场环境的固定名称。再次部署时先通过 `docker ps -a` 核对，禁止在同名容器存在时创建替代品。

## 分层职责

- R6 core：Mihomo 基础核心，IPv4 TCP redir `7895`，DNS `7853`。
- R6 rules：`br-lan`、`br-miot` 的 DNS 与 IPv4 TCP 导流，同时拒绝 UDP/443，让客户端回退到 TCP。
- R10 core：HTTPS 目标纠正层，redir `7897`，启用 `override-destination`，用于纠正污染 DNS 导致的错误原始目标。
- R10 rules：仅接管 `br-lan`、`br-miot` 的 TCP/443；核心异常时清除自己的规则并回落到 R6。
- IPv6 guard：只阻断 LAN/IoT 到 `pppoe-wan` 的全球 IPv6，保留本地 IPv6。
- `simple-docker`：官方第三方管理界面。

R10 core 的关键容量参数：

```text
memory=192 MiB
pids-limit=64
nofile=8192:8192
privileged=false
cap-add=NET_ADMIN,NET_RAW
read-only=true
```

## 网络目标

- 中国大陆域名/IP：直连；
- 其他 IPv4 流量：代理；
- 局域网、本地发现和智能家居本地通信：直连；
- IPv6 广域网访问：当前采用阻断策略，避免绕过 IPv4 代理；
- 本地 IPv6 通信保留。
- 当前只有一个 VLESS 出口节点，没有自动节点故障切换；出口服务器发生 EOF/reset 时可能短暂影响 Cloudflare/ChatGPT 长连接。

本仓库不保存 VLESS 节点、订阅、服务器域名、UUID、公钥参数或 Reality 参数。

## 健康检查

```sh
/etc/init.d/mi_docker check_integrity
echo "integrity_exit=$?"
/etc/init.d/mi_docker is_running
echo "running_exit=$?"

nvram get ssh_en
uci -q show dropbear
```

Docker 两项退出码应为 `0`；SSH 开关应为 `1`，密码登录应为 `off`。

完整容器与挂载审计可运行：

```sh
/bin/sh /mnt/usb-xxxx/be7000_proxy_20260904/persistent-scripts/audit-current-state.sh
```
