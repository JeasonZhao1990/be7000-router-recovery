# Docker 页面“文件缺失”误报修复

## 现象

小米后台显示：

> 不可用，检测到已安装的 Docker 文件缺失，请卸载 Docker 后重新安装

与此同时，Docker Engine、SimpleDocker 和既有容器可能仍在正常运行。

## 已确认的根因

固件脚本 `/etc/init.d/mi_docker` 的 `check_integrity()` 不只校验 Docker 二进制，还会通过 `valid_mountpath()` 扫描所有容器配置，包括已停止容器。

允许的挂载源通常限于：

- 当前 USB 存储路径，例如 `/mnt/usb-xxxx/...`；
- `/var/run/docker.sock`。

本次故障由 3 个已经停止的临时诊断容器引起，共有 4 条违规挂载，来源为 `/`、`/dev` 和 `/sys`。Mihomo 容器的挂载都位于 USB 路径下，不是故障源。

## 只读检查

登录路由器后运行：

```sh
/etc/init.d/mi_docker check_integrity
echo "integrity_exit=$?"

/etc/init.d/mi_docker is_running
echo "running_exit=$?"
```

两个退出码均为 `0` 才表示官方检查通过。

定位 Docker CLI：

```sh
DOCKER_BIN=/mnt/usb-xxxx/mi_docker/docker-binaries/docker
DOCKER_HOST=unix:///var/run/docker.sock

"$DOCKER_BIN" --host "$DOCKER_HOST" version
"$DOCKER_BIN" --host "$DOCKER_HOST" ps -a
```

逐个查看可疑容器挂载：

```sh
"$DOCKER_BIN" --host "$DOCKER_HOST" inspect CONTAINER_NAME \
  --format '{{.Name}} state={{.State.Status}}{{println}}{{range .Mounts}}{{.Source}} -> {{.Destination}} rw={{.RW}}{{println}}{{end}}'
```

重点检查已停止的诊断或维护容器是否挂载了 `/`、`/dev`、`/sys`、`/proc` 等系统路径。

## 最小修复

仅在确认容器为已停止、可丢弃的临时诊断容器后执行：

```sh
"$DOCKER_BIN" --host "$DOCKER_HOST" rm EXACT_STOPPED_CONTAINER_NAME
```

注意：

- 不使用 `-v`；
- 不使用通配符或批量清理；
- 不删除正在运行的业务容器；
- 不卸载 Docker；
- 不修改 Docker 数据目录。

删除后重新运行官方检查：

```sh
/etc/init.d/mi_docker check_integrity
echo "integrity_exit=$?"
/etc/init.d/mi_docker is_running
echo "running_exit=$?"
```

本次最终结果均为 `0`，刷新小米后台后 Docker 恢复“运行中”，第三方管理工具恢复“可用”。

## 不推荐的方法

网上常见做法是在 `valid_mountpath()` 开头加入 `return 0`。它可以隐藏报错，但会整体关闭小米的挂载路径安全检查。本次没有采用该方法，而是删除确切的违规临时容器，从根因恢复检查。
