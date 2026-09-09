# 修复完成后的运行基线

## 环境

- 设备：Xiaomi BE7000（RC06）
- 固件：1.1.38 稳定版
- 内核：5.4.164 aarch64
- Docker Engine：20.10.17
- Docker 数据目录：USB 存储下的 `mi_docker/lib/docker`

## 已验证的常驻服务

修复完成时以下容器均为 `running`：

```text
simple-docker
be7000-mihomo-core-20260904
be7000-family-proxy-core-r6-20260907
be7000-family-proxy-rules-r6-20260907
be7000-family-ipv6-wan-guard-r17-20260908
```

后四个名称是本次现场环境的历史名称。再次部署时不要盲目照抄名称，应先通过 `docker ps -a` 核对。

## 网络目标

- 中国大陆域名/IP：直连；
- 其他 IPv4 流量：代理；
- 局域网、本地发现和智能家居本地通信：直连；
- IPv6 广域网访问：当前采用阻断策略，避免绕过 IPv4 代理；
- 本地 IPv6 通信保留。

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
