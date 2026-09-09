# SSH 开启、密钥登录与持久化

## 已发现的固件限制

BE7000 稳定版的 `/etc/init.d/dropbear` 会同时检查 NVRAM 中的 `ssh_en` 和固件渠道；即使 `ssh_en=1`，release 渠道仍可能直接返回而不启动 Dropbear。

修复前还发现：

- 22 端口未监听；
- 没有 `authorized_keys`；
- `/etc/dropbear/dropbear_rsa_host_key` 是 0 字节空文件；
- 路由器的旧版 Dropbear 不接受本次生成的 Ed25519 用户密钥，需要 RSA 用户密钥兼容。

## Windows 客户端密钥

生成专用 RSA-3072 密钥：

```powershell
ssh-keygen -t rsa -b 3072 -f "$env:USERPROFILE\.ssh\be7000_codex_rsa3072" -C "be7000-router"
```

只把 `.pub` 公钥复制到路由器。私钥不得上传到 GitHub、移动硬盘或聊天记录。

## 路由器端持久化布局

本次使用：

```text
/data/auto_ssh/auto_ssh.sh
/data/auto_ssh/authorized_keys
/etc/dropbear/authorized_keys
```

并在 `/etc/rc.local` 的 `exit 0` 前加入：

```sh
/data/auto_ssh/auto_ssh.sh >/tmp/auto_ssh.log 2>&1
```

恢复脚本的职责：

1. 设置并提交 `ssh_en=1`；
2. 恢复 release 渠道的 Dropbear 启动修正；
3. 把持久化公钥复制到 `/etc/dropbear/authorized_keys`；
4. 设置正确权限；
5. 关闭密码登录；
6. 启动或重启 Dropbear。

核心配置应为：

```sh
uci set dropbear.@dropbear[0].Port='22'
uci set dropbear.@dropbear[0].PasswordAuth='off'
uci set dropbear.@dropbear[0].RootPasswordAuth='off'
uci commit dropbear
```

授权文件权限：

```sh
chmod 700 /etc/dropbear
chmod 600 /etc/dropbear/authorized_keys
chmod 700 /data/auto_ssh/auto_ssh.sh
chmod 600 /data/auto_ssh/authorized_keys
```

## 空主机密钥修复

先备份异常文件，再重新生成：

```sh
mkdir -p /data/codex-backups
cp -p /etc/dropbear/dropbear_rsa_host_key \
  /data/codex-backups/dropbear_rsa_host_key.before-repair
rm -f /etc/dropbear/dropbear_rsa_host_key
dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
test -s /etc/dropbear/dropbear_rsa_host_key
```

不要在不能访问 `/dev/nvram` 的普通容器里判断 SSH 开关。本次立即启动阶段使用了映射 `/dev/nvram` 的一次性维护容器；持久化脚本在真实路由器启动环境运行，不受该容器设备权限限制。

## 登录命令

旧版 Dropbear 只提供 `ssh-rsa` 主机算法，Windows 新版 OpenSSH 需要针对该路由器显式兼容：

```powershell
ssh -i "$env:USERPROFILE\.ssh\be7000_codex_rsa3072" `
  -o HostKeyAlgorithms=+ssh-rsa `
  -o PubkeyAcceptedAlgorithms=+ssh-rsa `
  root@192.168.31.1
```

成功标志：

```text
root@XiaoQiang:~#
```

## 验证

```sh
nvram get ssh_en
uci -q show dropbear
test -s /data/auto_ssh/auto_ssh.sh
test -s /data/auto_ssh/authorized_keys
```

预期：`ssh_en=1`，端口为 22，两个密码登录选项均为 `off`。

## 备份与回滚

本次备份目录：

```text
/data/codex-backups/
```

回滚前必须保持一个已验证的管理通道。恢复备份后再执行：

```sh
/etc/init.d/dropbear restart
```

注意：本次遵循“不重启路由器”的要求，因此只验证了当前服务、密钥登录和持久化文件，没有执行整机重启测试。
