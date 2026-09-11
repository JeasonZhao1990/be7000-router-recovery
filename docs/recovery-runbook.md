# 完整恢复顺序与回滚

本文记录 2026-09-11 已验证的现场顺序。目标是恢复现有安装，不是无条件重装 Docker。

## 0. 安全边界

- 不重启路由器，不拔移动硬盘；
- 不运行 `docker system prune`，不使用 `docker rm -v`；
- 不把 VLESS 配置、SSH 私钥、设备标识或完整日志提交到 Git；
- 每次只改变一层，先 core 后 rules；停止时反向，先 rules 后 core；
- 所有常驻脚本必须放在 `/mnt/usb-xxxx/...`。

## 1. 建立 SSH

Windows 连接方式见 [SSH 持久化](ssh-persistence.md)。登录后先确认：

```sh
nvram get ssh_en
uci -q show dropbear
```

## 2. 定位 Docker 与 USB 路径

现场路径如下，其他机器必须替换 `usb-xxxx`：

```sh
DOCKER=/mnt/usb-xxxx/mi_docker/docker-binaries/docker
HOST=unix:///var/run/docker.sock
BASE=/mnt/usb-xxxx/be7000_proxy_20260904

"$DOCKER" -H "$HOST" version
"$DOCKER" -H "$HOST" ps -a
```

必须先确认 Docker 20.10.17、linux/arm64、数据目录和移动硬盘均可访问。

## 3. 准备私密 bundle

GitHub 不保存以下文件的真实内容：

```text
$BASE/config.json
$BASE/rules/cn-domain.mrs
$BASE/rules/cn-ip.mrs
```

`config.json` 包含私密 VLESS/Reality 参数，只能从自己的离线备份恢复。启动前运行 Mihomo 配置检查并重新计算 SHA256；不要照抄文档中的历史校验值覆盖新文件。

## 4. 恢复基础 R6

R6 是稳定回落路径：

1. 确认核心镜像和观察工具镜像仍存在；
2. 确认 bundle 三个文件哈希符合自己的备份；
3. 创建 `be7000-family-proxy-core-r6-20260907`，使用 host 网络、只读根文件系统、`NET_ADMIN`/`NET_RAW`、96 MiB 内存、USB bundle 只读挂载；
4. 启动 core，确认 TCP 7895 和 DNS 7853 监听；
5. 将 `scripts/reference/persistent-family-rules-guard-r6.sh` 放入 USB，计算 SHA256；该脚本会直接修改防火墙，只能由经过审核、带回滚的 rules 容器运行；
6. 创建 rules 容器并通过 `EXPECTED_SELF_SHA256` 传入该值；
7. 启动 rules，确认 `B7G_0904_PERSISTENT_FAMILY_REDIR_DNS` 对 `br-lan` 和 `br-miot` 各只有一个 hook。

如果 R6 已运行，不要重新创建。

## 5. 恢复 R10 HTTPS 目标纠正层

R10 依赖 R6，不能替代 R6。将以下脚本复制到 USB：

```text
$BASE/persistent-scripts/family-override-core-r10.sh
$BASE/persistent-scripts/family-override-guard-r10.sh
```

R10 core 的关键创建参数：

```text
name=be7000-family-override-core-r10-20260911
network=host
read-only=true
cap-drop=ALL
cap-add=NET_ADMIN,NET_RAW
memory=192 MiB
pids-limit=64
cpus=0.25
nofile=8192:8192
restart=always
bundle mount=USB -> /bundle, read-only
script mount=USB -> /core.sh, read-only
```

R10 rules 的关键参数：

```text
name=be7000-family-override-rules-r10-20260911
network=host
pid=container:R10-core
read-only=true
cap-drop=ALL
cap-add=NET_ADMIN,NET_RAW
memory=64 MiB
pids-limit=32
cpus=0.25
restart=always
script mount=USB -> /guard.sh, read-only
```

启动 core 后确认 7897 监听，再启动 rules。确认 TCP/443 hook 标记 `B7G_0911_FAMILY_OVERRIDE_R10` 在 `br-lan` 和 `br-miot` 各出现一次。

禁止使用 `/tmp/*.sh` 作为 bind mount；这会再次触发小米 `valid_mountpath()` 误判。

## 6. 恢复 IPv6 WAN 防护

将 `scripts/reference/family-ipv6-wan-guard-r17.sh` 放到 USB，按其 SHA256 创建容器。只允许它创建私有 nft table `b7g_ipv6_wan_guard_17`，作用域应为：

```text
br-lan,br-miot -> pppoe-wan：全球 IPv6 reject
局域网、本地链路 IPv6：保留
```

## 7. 验证顺序

1. `check_integrity=0`、`is_running=0`；
2. 恰好 6 个保留容器，全部 `running|always`；
3. 无非 USB/system-socket 挂载；
4. 百度与米家正常；
5. Google、Wikipedia 正常；
6. `api.ipify.org` 显示代理 IPv4；
7. `api6.ipify.org` 无法访问（当前设计如此）；
8. ChatGPT App 与桌面端均能保持连接。

## 8. 故障时的最小回滚

如果启用 R10 后 ChatGPT 或家庭网络异常，只停 R10：

先把仓库中的脚本复制到 USB，再在路由器上执行：

```sh
/bin/sh /mnt/usb-xxxx/be7000_proxy_20260904/persistent-scripts/stop-r10-overlay.sh --confirm
```

该顺序先停 rules，再停 core，R6 保持运行。恢复 R10 前先检查节点日志和 7897 监听，然后运行：

```sh
/bin/sh /mnt/usb-xxxx/be7000_proxy_20260904/persistent-scripts/start-r10-overlay.sh --confirm
```

如果 R6 本身异常，停止继续操作并保留 SSH 会话；不要在同一轮叠加新规则或重启路由器。
