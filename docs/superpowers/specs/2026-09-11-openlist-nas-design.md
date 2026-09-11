# BE7000 OpenList 简易 NAS 部署设计

日期：2026-09-11

## 目标

在不重启 BE7000、不拔移动硬盘、不改动现有透明代理容器的前提下，部署官方 OpenList，把当前 USB 移动硬盘整盘作为可读写本地存储，仅供家庭局域网访问。

OpenList 提供网页文件管理和后续 WebDAV 能力；它不替代路由器已有的 SMB 服务。

## 已确认现场条件

- Docker Engine `20.10.17`，架构 `linux/arm64`；
- 当前 6 个容器全部运行；
- 移动硬盘挂载点为 `/mnt/usb-fea0df2e`；
- 硬盘容量约 916.8 GiB，当前可用约 151.4 GiB；
- 路由器可用内存（扣除缓存口径）约 278 MiB，另有可用 swap；
- TCP 5244 当前未占用；
- 当前不存在 OpenList/AList 容器、镜像或配置目录。

## 选型

采用社区治理的官方 OpenList 项目与官方镜像：

```text
image: openlistteam/openlist:v4.2.6
container: openlist
architecture: linux/arm64
```

不使用浮动的 `latest`、beta、AIO、FFmpeg 或 Aria2 变体。拉取完成后必须核对镜像架构并记录不可变 image ID/RepoDigest，创建容器时使用已核验的镜像 ID，防止标签漂移。

## 存储布局

```text
/mnt/usb-fea0df2e/openlist-data  -> /opt/openlist/data  (读写，OpenList 配置)
/mnt/usb-fea0df2e                -> /storage            (整盘读写，NAS 数据)
```

OpenList 后台添加 Local 存储时使用容器路径 `/storage`。

整盘读写意味着 OpenList 管理员也能访问或删除以下关键目录：

- `/storage/mi_docker`；
- `/storage/be7000_proxy_20260904`；
- `/storage/openlist-data`；
- 硬盘上的其他用户数据。

这是用户明确接受的权限范围。首次进入后台后应设置强密码，并避免把上述系统目录作为普通文件操作目标。

## 容器隔离和资源参数

```text
network: bridge
publish: 192.168.31.1:5244 -> 5244/tcp
user: 0:0
privileged: false
cap-drop: ALL
security-opt: no-new-privileges:true
read-only rootfs: true
tmpfs: /tmp (64 MiB, nosuid,nodev,noexec)
memory: 192 MiB
pids-limit: 128
cpus: 0.50
nofile: 4096:4096
environment: UMASK=022, TZ=Asia/Shanghai
```

`user=0:0` 是为了保证整盘现有目录的读写兼容性；它扩大了容器内进程对硬盘文件的权限，但不授予 privileged、Docker Socket 或路由器系统目录访问权。

端口只绑定路由器 LAN 地址 `192.168.31.1`，不新增公网端口转发，也不接入 `br-lan`、`br-miot` 的透明代理入口规则。

## 事务式部署流程

1. 再次检查 6 个现有容器、5244 端口、硬盘与内存；
2. 拉取固定版本镜像，核对 `linux/arm64` 和镜像身份；
3. 创建 `/mnt/usb-fea0df2e/openlist-data`，不改动其他目录；
4. 以 `restart=no` 创建 `openlist`，核对全部容器参数和两条挂载；
5. 启动后验证日志、5244 监听和局域网 HTTP 响应；
6. 通过网页确认登录，并完成 `/storage` 本地存储的读取、创建、重命名与删除测试；
7. 检查原 6 个容器、透明代理、米家、小米 Docker `check_integrity` 与违规挂载；
8. 全部通过后，把重启策略改为 `unless-stopped`。

## 失败处理

任何检查失败时：

1. 将 OpenList 重启策略保持或改回 `no`；
2. 停止并删除且仅删除 `openlist` 容器，不使用 `-v`；
3. 保留 `openlist-data` 供诊断，不删除硬盘文件；
4. 复核原 6 个容器仍为运行状态；
5. 不重启 Docker 服务或路由器，不叠加防火墙规则。

镜像拉取本身不会改变现有容器。若拉取失败，仅保留或删除未使用镜像层，不触碰现有服务。

## 验收标准

- `http://192.168.31.1:5244` 可从家庭 LAN 打开；
- OpenList 容器为 `running|unless-stopped`；
- OpenList 能读取硬盘现有文件，并在指定测试目录完成写入、重命名和删除；
- 不从外网开放 5244；
- 原 6 个容器持续运行，Google、ChatGPT、百度和米家正常；
- 小米 Docker `check_integrity=0`、`is_running=0`；
- 所有 OpenList bind mount 来源均位于 USB 路径，不触发 `valid_mountpath()` 误判。

## 凭据处理

不把管理员密码写入环境变量、部署脚本、GitHub 或完整日志。首次启动读取随机初始密码，登录后立即修改；忘记密码时使用官方命令：

```sh
docker exec -it openlist ./openlist admin random
```

## 官方参考

- OpenList 官方仓库：https://github.com/OpenListTeam/OpenList
- OpenList Docker 安装：https://doc.oplist.org/guide/installation/docker
- 官方镜像标签：https://hub.docker.com/r/openlistteam/openlist/tags
