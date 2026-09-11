# BE7000 OpenList NAS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不重启路由器、不拔移动硬盘、不改变现有透明代理的条件下，部署一个仅局域网开放、可整盘读写 USB 硬盘的 OpenList v4.2.6 容器。

**Architecture:** 使用官方 ARM64 OpenList 镜像、Docker bridge 网络和仅绑定 `192.168.31.1:5244` 的端口。配置目录与整盘数据均从 USB 路径 bind mount；首次以 `restart=no` 运行 120 秒健康门，任何技术检查失败只回滚 OpenList，成功后改为 `unless-stopped`。

**Tech Stack:** Xiaomi BE7000 / OpenWrt BusyBox、Docker Engine 20.10.17 arm64、OpenList v4.2.6、POSIX `sh`、HTTP 5244。

**Spec:** `docs/superpowers/specs/2026-09-11-openlist-nas-design.md`

## Global Constraints

- 不重启路由器，不拔移动硬盘，不重启 Docker 服务。
- 保留并持续验证现有 6 个容器；不修改 R6、R10 或 IPv6 防护规则。
- 镜像固定为 `openlistteam/openlist:v4.2.6`，拉取后必须验证 `linux/arm64`。
- 容器名固定为 `openlist`，服务端口固定为 `192.168.31.1:5244/tcp`。
- 配置目录固定为 `/mnt/usb-fea0df2e/openlist-data`，整盘挂载固定为 `/mnt/usb-fea0df2e:/storage:rw`。
- 容器不得使用 privileged、Docker Socket、host network 或非 USB bind mount。
- 失败时只停止并删除 `openlist` 容器，不使用 `-v`，不删除配置目录或镜像。
- 管理员密码不得写入 Git、脚本、环境变量或归档日志。

---

## File Structure

- Create: `scripts/openlist/deploy-openlist.sh` — 完成预检、固定镜像拉取、容器创建、120 秒健康门与失败回滚。
- Create: `scripts/openlist/audit-openlist.sh` — 只读核对镜像、参数、挂载、端口、HTTP、官方 Docker 状态和原 6 个服务。
- Create: `scripts/openlist/rollback-openlist.sh` — 经显式确认后仅停止并删除 OpenList 容器，保留数据。
- Create: `docs/openlist-nas-runbook.md` — 面向用户记录登录、添加 Local 存储、验收、升级和恢复方法。
- Modify: `README.md` — 加入 OpenList NAS 文档入口。

脚本通过固定输出标记通信：部署成功产生 `OPENLIST_DEPLOYMENT_COMPLETE`；审计成功产生 `OPENLIST_AUDIT_PASS`；回滚成功产生 `OPENLIST_ROLLBACK_COMPLETE_DATA_PRESERVED`。

---

### Task 1: 编写事务式部署脚本

**Files:**
- Create: `scripts/openlist/deploy-openlist.sh`
- Test: 路由器 BusyBox `/bin/sh -n`

**Interfaces:**
- Consumes: Docker Socket `unix:///var/run/docker.sock`、USB 根目录 `/mnt/usb-fea0df2e`、固定镜像标签。
- Produces: 容器 `openlist`，成功标记 `OPENLIST_DEPLOYMENT_COMPLETE`；失败时容器不存在且配置目录保留。

- [ ] **Step 1: 写入部署脚本的固定变量和预检**

脚本必须以以下内容开始：

```sh
#!/bin/sh
set -eu

[ "${1:-}" = "--confirm" ] || { echo 'Usage: deploy-openlist.sh --confirm'; exit 64; }
DOCKER=/mnt/usb-fea0df2e/mi_docker/docker-binaries/docker
HOST=unix:///var/run/docker.sock
USB=/mnt/usb-fea0df2e
CONFIG=$USB/openlist-data
IMAGE_TAG=openlistteam/openlist:v4.2.6
NAME=openlist
created=0
complete=0
dc() { "$DOCKER" -H "$HOST" "$@"; }
fail() { echo "OPENLIST_DEPLOYMENT_BLOCKED=$1"; exit 70; }

for stable in \
  simple-docker \
  be7000-family-proxy-core-r6-20260907 \
  be7000-family-proxy-rules-r6-20260907 \
  be7000-family-ipv6-wan-guard-r17-20260908 \
  be7000-family-override-core-r10-20260911 \
  be7000-family-override-rules-r10-20260911; do
  state=$(dc inspect "$stable" --format '{{.State.Status}}|res={{.HostConfig.RestartPolicy.Name}}')
  case "$state" in 'running|res=always') : ;; *) fail "STABLE_SERVICE_$stable:$state" ;; esac
done
dc inspect "$NAME" >/dev/null 2>&1 && fail CONTAINER_NAME_EXISTS || :
grep -qi ':147C ' /proc/net/tcp /proc/net/tcp6 2>/dev/null && fail PORT_5244_IN_USE || :
test -d "$USB" || fail USB_ROOT_MISSING
df -m "$USB" | awk 'NR==2 {exit !($4 >= 1024)}' || fail USB_FREE_SPACE_LT_1G
```

- [ ] **Step 2: 加入失败回滚 trap**

```sh
rollback() {
  code=$?
  trap - EXIT INT TERM HUP
  if [ "$complete" -ne 1 ] && [ "$created" -eq 1 ]; then
    dc update --restart no "$NAME" >/dev/null 2>&1 || true
    [ "$(dc inspect "$NAME" --format '{{.State.Status}}' 2>/dev/null || true)" != running ] ||
      dc stop -t 10 "$NAME" >/dev/null 2>&1 || true
    dc rm "$NAME" >/dev/null 2>&1 || true
    echo OPENLIST_AUTOMATIC_ROLLBACK_CONTAINER_REMOVED
    echo OPENLIST_CONFIG_PRESERVED=$CONFIG
  fi
  exit "$code"
}
trap rollback EXIT
trap 'exit 130' INT TERM HUP
```

- [ ] **Step 3: 加入镜像拉取和身份验证**

```sh
dc pull "$IMAGE_TAG"
IMAGE_ID=$(dc image inspect "$IMAGE_TAG" --format '{{.Id}}')
IMAGE_AUDIT=$(dc image inspect "$IMAGE_ID" --format '{{.Id}}|{{.Os}}/{{.Architecture}}')
[ "$IMAGE_AUDIT" = "$IMAGE_ID|linux/arm64" ] || fail "IMAGE_IDENTITY:$IMAGE_AUDIT"
REPO_DIGEST=$(dc image inspect "$IMAGE_ID" --format '{{join .RepoDigests ","}}')
echo "OPENLIST_IMAGE=$IMAGE_TAG|$IMAGE_ID|$REPO_DIGEST"
```

- [ ] **Step 4: 加入配置目录创建和容器创建**

```sh
mkdir -p "$CONFIG"
chmod 700 "$CONFIG"
id=$(dc create \
  --name "$NAME" \
  --label be7000.project=openlist-nas \
  --label be7000.role=local-storage-ui \
  --network bridge \
  --publish 192.168.31.1:5244:5244/tcp \
  --user 0:0 \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --restart no \
  --pids-limit 128 \
  --memory 192m \
  --cpus 0.50 \
  --ulimit nofile=4096:4096 \
  --tmpfs /tmp:rw,nosuid,nodev,noexec,size=64m \
  --env UMASK=022 \
  --env TZ=Asia/Shanghai \
  --mount "type=bind,src=$CONFIG,dst=/opt/openlist/data" \
  --mount "type=bind,src=$USB,dst=/storage" \
  "$IMAGE_ID")
[ -n "$id" ] || fail CONTAINER_ID_EMPTY
created=1
```

- [ ] **Step 5: 加入创建参数审计门**

审计以下字段，任何不一致调用 `fail`：

```sh
network=$(dc inspect "$NAME" --format '{{.HostConfig.NetworkMode}}')
case "$network" in default|bridge) : ;; *) fail "NETWORK:$network" ;; esac
profile=$(dc inspect "$NAME" --format '{{.HostConfig.Privileged}}|{{.HostConfig.ReadonlyRootfs}}|{{.Config.User}}|{{.HostConfig.RestartPolicy.Name}}|{{json .HostConfig.CapDrop}}|{{json .HostConfig.CapAdd}}|{{json .HostConfig.SecurityOpt}}|{{.HostConfig.PidsLimit}}|{{.HostConfig.Memory}}|{{.HostConfig.NanoCpus}}')
expected='false|true|0:0|no|["ALL"]|null|["no-new-privileges:true"]|128|201326592|500000000'
[ "$profile" = "$expected" ] || fail "PROFILE:$profile"
[ "$(dc inspect "$NAME" --format '{{len .Mounts}}')" = 2 ] || fail MOUNT_COUNT
mounts=$(dc inspect "$NAME" --format '{{range .Mounts}}{{.Source}}>{{.Destination}}|rw={{.RW}}{{println}}{{end}}')
echo "$mounts" | grep -Fx "$CONFIG>/opt/openlist/data|rw=true" >/dev/null || fail CONFIG_MOUNT
echo "$mounts" | grep -Fx "$USB>/storage|rw=true" >/dev/null || fail STORAGE_MOUNT
ports=$(dc inspect "$NAME" --format '{{json .HostConfig.PortBindings}}')
echo "$ports" | grep -F '"HostIp":"192.168.31.1","HostPort":"5244"' >/dev/null || fail LAN_PORT_BINDING
```

- [ ] **Step 6: 加入启动和 120 秒健康门**

```sh
dc start "$NAME" >/dev/null
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do
  sleep 10
  [ "$(dc inspect "$NAME" --format '{{.State.Status}}')" = running ] || {
    dc logs --tail 80 "$NAME" 2>&1 || true
    fail "CONTAINER_STOPPED_AT_${n}0S"
  }
  wget -q -T 5 -O /dev/null http://192.168.31.1:5244/ || fail "HTTP_FAILED_AT_${n}0S"
  for stable in simple-docker be7000-family-proxy-core-r6-20260907 be7000-family-proxy-rules-r6-20260907 be7000-family-ipv6-wan-guard-r17-20260908 be7000-family-override-core-r10-20260911 be7000-family-override-rules-r10-20260911; do
    [ "$(dc inspect "$stable" --format '{{.State.Status}}')" = running ] || fail "STABLE_SERVICE_LOST_$stable"
  done
  /etc/init.d/mi_docker check_integrity >/dev/null 2>&1 || fail "MI_DOCKER_INTEGRITY_AT_${n}0S"
done
dc update --restart unless-stopped "$NAME" >/dev/null
[ "$(dc inspect "$NAME" --format '{{.State.Status}}|{{.HostConfig.RestartPolicy.Name}}')" = 'running|unless-stopped' ] || fail FINAL_STATE
complete=1
trap - EXIT INT TERM HUP
echo OPENLIST_DEPLOYMENT_COMPLETE
```

- [ ] **Step 7: 在路由器 BusyBox 中验证完整脚本语法**

运行：

```sh
/bin/sh -n scripts/openlist/deploy-openlist.sh
```

预期：退出码 `0`。本步骤只做语法检查，不传 `--confirm`，不得创建容器。

- [ ] **Step 8: 提交 Task 1**

```sh
git add scripts/openlist/deploy-openlist.sh
git commit -m "feat: add transactional OpenList deployment"
```

---

### Task 2: 编写只读审计与显式回滚脚本

**Files:**
- Create: `scripts/openlist/audit-openlist.sh`
- Create: `scripts/openlist/rollback-openlist.sh`
- Test: 路由器 BusyBox `/bin/sh -n`

**Interfaces:**
- Consumes: 已存在的 `openlist` 容器和现有 6 个服务。
- Produces: 只读状态标记或只删除容器、保留数据的回滚标记。

- [ ] **Step 1: 编写 `audit-openlist.sh`**

脚本必须检查并输出：

```sh
#!/bin/sh
set -eu
DOCKER=/mnt/usb-fea0df2e/mi_docker/docker-binaries/docker
HOST=unix:///var/run/docker.sock
dc() { "$DOCKER" -H "$HOST" "$@"; }
echo BEGIN_OPENLIST_AUDIT
dc inspect openlist --format 'STATE={{.State.Status}}|RESTART={{.HostConfig.RestartPolicy.Name}}|IMAGE={{.Image}}|PRIVILEGED={{.HostConfig.Privileged}}|READONLY={{.HostConfig.ReadonlyRootfs}}|USER={{.Config.User}}'
dc inspect openlist --format 'MOUNTS={{range .Mounts}}{{.Source}}>{{.Destination}}|rw={{.RW}};{{end}}'
dc inspect openlist --format 'PORTS={{json .HostConfig.PortBindings}}'
wget -q -T 5 -O /dev/null http://192.168.31.1:5244/
for stable in simple-docker be7000-family-proxy-core-r6-20260907 be7000-family-proxy-rules-r6-20260907 be7000-family-ipv6-wan-guard-r17-20260908 be7000-family-override-core-r10-20260911 be7000-family-override-rules-r10-20260911; do
  [ "$(dc inspect "$stable" --format '{{.State.Status}}|{{.HostConfig.RestartPolicy.Name}}')" = 'running|always' ]
done
/etc/init.d/mi_docker check_integrity >/dev/null 2>&1
/etc/init.d/mi_docker is_running >/dev/null 2>&1
echo OPENLIST_AUDIT_PASS
echo END_OPENLIST_AUDIT
```

- [ ] **Step 2: 编写 `rollback-openlist.sh`**

```sh
#!/bin/sh
set -eu
[ "${1:-}" = "--confirm" ] || { echo 'Usage: rollback-openlist.sh --confirm'; exit 64; }
DOCKER=/mnt/usb-fea0df2e/mi_docker/docker-binaries/docker
HOST=unix:///var/run/docker.sock
dc() { "$DOCKER" -H "$HOST" "$@"; }
dc inspect openlist >/dev/null 2>&1 || { echo OPENLIST_NOT_PRESENT; exit 0; }
dc update --restart no openlist >/dev/null
[ "$(dc inspect openlist --format '{{.State.Status}}')" != running ] || dc stop -t 10 openlist >/dev/null
dc rm openlist >/dev/null
[ ! -e /mnt/usb-fea0df2e/openlist-data ] || echo OPENLIST_DATA_PRESERVED=/mnt/usb-fea0df2e/openlist-data
for stable in simple-docker be7000-family-proxy-core-r6-20260907 be7000-family-proxy-rules-r6-20260907 be7000-family-ipv6-wan-guard-r17-20260908 be7000-family-override-core-r10-20260911 be7000-family-override-rules-r10-20260911; do
  [ "$(dc inspect "$stable" --format '{{.State.Status}}')" = running ]
done
echo OPENLIST_ROLLBACK_COMPLETE_DATA_PRESERVED
```

- [ ] **Step 3: 验证两个脚本的语法和危险命令边界**

运行：

```sh
/bin/sh -n scripts/openlist/audit-openlist.sh
/bin/sh -n scripts/openlist/rollback-openlist.sh
rg -n 'system prune|rm -v|rm -rf|mi_docker.*rm|be7000-family.*rm' scripts/openlist
```

预期：两个语法检查退出 `0`；危险命令扫描无输出。

- [ ] **Step 4: 提交 Task 2**

```sh
git add scripts/openlist/audit-openlist.sh scripts/openlist/rollback-openlist.sh
git commit -m "feat: add OpenList audit and rollback controls"
```

---

### Task 3: 执行部署并通过技术健康门

**Files:**
- Use: `scripts/openlist/deploy-openlist.sh`
- Use: `scripts/openlist/audit-openlist.sh`
- No router files outside `/mnt/usb-fea0df2e/openlist-data` are created or modified.

**Interfaces:**
- Consumes: Task 1、Task 2 已验证脚本。
- Produces: 运行中的 `openlist` 容器和 LAN URL `http://192.168.31.1:5244`。

- [ ] **Step 1: 执行最后一次只读预检**

核对输出必须包含 `TOTAL=6`、`RUNNING=6`、`CHECK_INTEGRITY_EXIT=0`、`IS_RUNNING_EXIT=0`、`INVALID_MOUNTS=0`、`PORT_5244=FREE`。

- [ ] **Step 2: 把三个脚本复制到 USB 的固定目录**

目标目录：

```text
/mnt/usb-fea0df2e/be7000_proxy_20260904/persistent-scripts/openlist/
```

复制后逐个核对 SHA256，并从 USB 文件重新运行 `/bin/sh -n`。不得从 `/tmp` bind mount 或执行常驻脚本。

- [ ] **Step 3: 执行事务式部署**

```sh
/bin/sh /mnt/usb-fea0df2e/be7000_proxy_20260904/persistent-scripts/openlist/deploy-openlist.sh --confirm
```

预期末行：`OPENLIST_DEPLOYMENT_COMPLETE`。若出现 `OPENLIST_DEPLOYMENT_BLOCKED=*`，停止本任务并收集该标记、OpenList 末尾 80 行日志和原 6 个容器状态；不得手工绕过审计门。

- [ ] **Step 4: 运行只读审计**

```sh
/bin/sh /mnt/usb-fea0df2e/be7000_proxy_20260904/persistent-scripts/openlist/audit-openlist.sh
```

预期末尾包含 `OPENLIST_AUDIT_PASS`。

---

### Task 4: 完成 OpenList 首次登录和整盘读写验收

**Files:**
- Create: `docs/openlist-nas-runbook.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: `http://192.168.31.1:5244` 和容器路径 `/storage`。
- Produces: OpenList Local 存储条目、用户确认的整盘读写能力和运维文档。

- [ ] **Step 1: 仅显示首次管理员密码，不落盘**

```sh
/mnt/usb-fea0df2e/mi_docker/docker-binaries/docker -H unix:///var/run/docker.sock logs openlist 2>&1 |
  grep -F 'initial password' | tail -n 1
```

不要把输出写入文件、GitHub 或诊断归档。用户登录后立即在 OpenList 后台更改强密码。

- [ ] **Step 2: 在网页后台添加 Local 存储**

使用以下固定值：

```text
Driver: Local
Mount Path: /storage
Web Mount Path: /
Read only: false
```

不得把路由器宿主路径 `/mnt/usb-fea0df2e` 填入 OpenList；后台只能识别容器路径 `/storage`。

- [ ] **Step 3: 执行限定测试目录的读写验收**

在 `/storage` 下创建 `openlist-write-test-20260911`，上传一个小文本文件，完成读取、重命名和删除，最后删除测试目录。不得使用 `mi_docker`、`be7000_proxy_20260904` 或 `openlist-data` 做测试。

- [ ] **Step 4: 验证家庭网络未受影响**

用户确认百度、Google、ChatGPT、米家和常用设备正常；验证 `http://192.168.31.1:5244` 可从 LAN 打开。不要建立任何公网端口映射。

- [ ] **Step 5: 编写运维文档并添加 README 入口**

文档必须记录：访问地址、容器名、镜像固定版本、两条挂载、密码重置命令、审计命令、回滚命令、升级前备份原则，以及整盘读写风险。不得记录真实密码或文件清单。

- [ ] **Step 6: 提交 Task 4**

```sh
git add docs/openlist-nas-runbook.md README.md
git commit -m "docs: add OpenList NAS operating runbook"
```

---

### Task 5: 最终验证与 GitHub 交付

**Files:**
- Verify: `scripts/openlist/*.sh`
- Verify: `docs/openlist-nas-runbook.md`
- Verify: `README.md`

**Interfaces:**
- Consumes: Tasks 1–4 的全部产物。
- Produces: 远端私有仓库中可重复执行的、无敏感信息的最终版本。

- [ ] **Step 1: 对全部 Shell 脚本执行路由器原生语法检查**

```sh
for f in scripts/openlist/*.sh; do /bin/sh -n "$f" || exit; done
```

预期：退出码 `0`。

- [ ] **Step 2: 扫描敏感信息**

```sh
rg -n -i 'vless://|vmess://|trojan://|private key|authorization:|bearer |password=.*|krv\.vwind|64\.110\.91\.7|<VLESS_SERVER_IPV6_PREFIX>|@gmail\.com' scripts/openlist docs/openlist-nas-runbook.md
```

预期：无输出。文档中的通用单词“密码”不属于匹配范围；真实密码不得出现。

- [ ] **Step 3: 最终现场审计**

必须同时满足：

```text
容器总数=7
运行容器=7
openlist=running|unless-stopped
openlist HTTP 5244=OK
原 6 个容器=running
check_integrity=0
is_running=0
非 USB/system-socket 违规挂载=0
```

- [ ] **Step 4: 检查 Git 差异并提交遗漏内容**

```sh
git diff --check
git status --short
```

若只存在计划内文档或脚本，完成对应提交；不得包含 OpenList 配置数据库、密码、日志或硬盘文件。

- [ ] **Step 5: 推送并核对远端提交**

```sh
git push origin main
git rev-parse HEAD
git ls-remote origin refs/heads/main
```

预期：本地 HEAD 与远端 `main` 哈希一致，仓库可见性仍为 `PRIVATE`。
