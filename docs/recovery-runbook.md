# 完整恢复顺序与回滚

本文记录当前生产架构的恢复顺序。目标是恢复现有安装，不是无条件重装 Docker。

## 0. 安全边界

- 不运行 `docker system prune`；
- 不使用 `docker rm -v` 清理未知容器；
- 不删除 Docker 数据目录；
- 不删除或覆盖小米固件已有 IPv6 policy rule；
- 不从 `/tmp`、`/root` 或根目录给长期容器 bind mount；
- 不把 VLESS 配置、SSH 私钥、设备标识或完整日志提交到 Git；
- 每次只改变一层，必须保留回滚路径；
- 如果只是代理节点线路慢，不通过叠加路由/防火墙规则处理。

## 1. 建立 SSH

Windows 连接方式见 [SSH 持久化](ssh-persistence.md)。

登录后先确认：

```sh
nvram get ssh_en
uci -q show dropbear
uci -q show firewall.auto_ssh
```

## 2. 定位 Docker 与 USB

不要把 USB mount suffix 写死到新脚本。先查找：

```sh
for x in /mnt/usb-*/mi_docker/docker-binaries/docker; do
    [ -x "$x" ] && echo "$x"
done
```

然后：

```sh
DOCKER=/mnt/usb-xxxx/mi_docker/docker-binaries/docker
"$DOCKER" version
"$DOCKER" ps -a
```

## 3. Docker 官方健康检查

```sh
/etc/init.d/mi_docker check_integrity
echo "integrity_exit=$?"

/etc/init.d/mi_docker is_running
echo "running_exit=$?"
```

预期两项均为 0。

如果失败，优先排查容器挂载来源，不要先删除数据目录。

## 4. 核对生产容器

当前重点检查：

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

R1/R2 测试容器已删除，不应为了“恢复”重新创建，除非重新做实验。

## 5. 恢复 R6/R10 旧回退路径

如果 R6/R10 已运行，不要重建。

先确认：

- R6 core/rules 运行；
- R10 core/rules 运行；
- R10 HTTPS listener 存在；
- IPv6 guard 存在；
- 没有来自 `/tmp` 或根目录的违规长期 bind mount。

旧路径仍有 `br-miot` 兼容和 R3 故障回退价值。

## 6. 恢复 R3 core

R3 配置应位于 USB 持久目录。

关键条件：

```text
network=host
TUN=b7g-tun-r3
MTU=1400
auto-route=false
auto-redirect=false
strict-route=true
IPv4/IPv6=true
DNS IPv6=true
restart=always
```

`HOME-VLESS` 当前额外使用：

```json
"ip-version": "ipv4"
```

该字段只用于节点接入 A/B 后的稳定性优化，不代表客户端 IPv6 被关闭。

启动或切换配置前，先使用 Mihomo 自身做配置检查。现场容器目录挂载到 `/run/mihomo`，因此候选配置可这样测试：

```sh
docker exec be7000-family-tun-r3-unified \
  /usr/local/bin/mihomo \
  -t \
  -d /run/mihomo \
  -f /run/mihomo/<candidate-config>.json
```

不得把真实 config 上传到 Git。

## 7. 恢复 Family policy

生产脚本位于：

```text
/data/be7000-r3-family/
```

正常情况下由：

```text
/data/be7000-r3-family/restore.sh
```

完成恢复。

restore 会：

- 加锁；
- 等待 R3/R6/R10/guard 就绪；
- 重试 apply；
- 动态发现当前 LAN IPv6 `/64`；
- 建立 table 2074；
- 恢复 IPv4/IPv6 policy；
- 恢复 DNS/TUN FORWARD；
- 恢复 IPv4 fail-closed；
- 让 `br-lan` 绕过旧 R6/R10。

## 8. 验证 Family

```sh
ip link show b7g-tun-r3
ip route show table 2074
ip -6 route show table 2074
ip rule show
ip -6 rule show
```

客户端 route-get 应显示 `br-lan` 公网目标进入 table 2074/TUN。

不要要求 Mihomo 自建 IPv6 TUN `oif` rule 固定为某个 preference；该 preference 可变化。

## 9. 恢复持久化 hook

应存在：

```sh
uci -q show firewall.auto_ssh
uci -q show firewall.r3_family
```

对应：

```text
/data/auto_ssh/auto_ssh.sh
/data/be7000-r3-family/firewall-hook.sh
```

如果 hook 丢失，先恢复 UCI include，再做受控 firewall reload。

## 10. firewall reload 验证

只有在 SSH 管理通道稳定时执行。

reload 后检查：

- Family restore 日志；
- R3 TUN；
- table 2074；
- DNS；
- IPv4/IPv6 fail-closed；
- 客户端网页和米家。

不要在 reload 失败后马上重启路由器；先保留 SSH 会话并执行 rollback/旧路径恢复。

## 11. 整机 reboot 恢复预期

当前架构已经通过真实 reboot 验证。

启动顺序允许出现短暂依赖未就绪：

1. Docker 启动；
2. R3/R6/R10/guard 容器恢复；
3. firewall include 调用 Family restore；
4. restore 发现依赖未就绪时重试；
5. PPPoE/IPv6 前缀稳定后动态写入当前 `/64`；
6. Family 恢复完成。

如果网络在启动初期短暂不可用属于恢复窗口；最终不应需要人工 SSH 修规则。

## 12. MIoT / br-miot

当前不要为 `br-miot` 增加新的持久化 R3 hook。

原因：

- 现场没有真实 `br-miot` station；
- `br-miot` 迁移已经做过非持久化 apply/rollback；
- 真正米家设备主要位于 `br-lan`。

只有未来 `wl13/br-miot` 出现真实客户端时，再重新做 canary。

## 13. 故障时的最小回滚

如果 R3/Family 异常：

1. 保持 SSH；
2. 不删除任何生产容器；
3. 执行 `/data/be7000-r3-family/rollback.sh`；
4. 确认 R6/R10 旧链恢复 `br-lan`；
5. 保留 IPv6 guard；
6. 再分析 R3 日志和配置。

如果只是 `HOME-VLESS` 节点慢：

- 不 rollback Family；
- 不关闭客户端 IPv6；
- 不盲目改 TUN MTU；
- 先测节点 RTT、丢包、TLS/TTFB；
- 优先更换或增加更优节点。

## 14. 测试容器清理

R1/R2 已删除，不需要再次清理。

如果未来出现新的实验容器：

- 先核对名称；
- 核对 `restart policy`；
- 核对 mounts/volumes；
- 确认不是生产依赖；
- 删除时不带 `-v`。
