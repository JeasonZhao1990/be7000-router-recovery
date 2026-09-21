# SSH 开启、密钥登录与持久化

## 固件限制

BE7000 稳定版的 `/etc` 会在启动后重建，因此只修改 `/etc/dropbear` 不足以保证 reboot 后 SSH 继续存在。

旧版 Dropbear 与 Windows 新版 OpenSSH 还存在算法兼容问题。

## Windows 客户端密钥

建议使用专用 RSA-3072 密钥：

```powershell
ssh-keygen -t rsa -b 3072 -f "$env:USERPROFILE\.ssh\be7000_router_rsa3072" -C "be7000-router"
```

只把 `.pub` 公钥复制到路由器。

私钥不得上传到 GitHub、移动硬盘共享目录或聊天记录。

## 持久化布局

当前使用：

```text
/data/auto_ssh/auto_ssh.sh
/data/auto_ssh/authorized_keys
```

运行时恢复到：

```text
/etc/dropbear/authorized_keys
```

`/data/auto_ssh/auto_ssh.sh` 的职责包括：

1. 恢复 SSH enable 状态；
2. 恢复 Dropbear 启动条件；
3. 将持久化公钥复制到运行时目录；
4. 设置正确权限；
5. 关闭密码登录；
6. 启动或重启 Dropbear。

## UCI firewall include

当前不再依赖只写 `/etc/rc.local` 作为唯一恢复入口。

持久化入口：

```text
firewall.auto_ssh.path=/data/auto_ssh/auto_ssh.sh
firewall.auto_ssh.reload=1
```

检查：

```sh
uci -q show firewall.auto_ssh
```

这样在 firewall 初始化/重载阶段可以从 `/data` 恢复 SSH 运行状态。

## Dropbear 配置

核心目标：

```sh
uci set dropbear.@dropbear[0].Port='22'
uci set dropbear.@dropbear[0].PasswordAuth='off'
uci set dropbear.@dropbear[0].RootPasswordAuth='off'
uci commit dropbear
```

权限：

```sh
chmod 700 /etc/dropbear
chmod 600 /etc/dropbear/authorized_keys
chmod 700 /data/auto_ssh/auto_ssh.sh
chmod 600 /data/auto_ssh/authorized_keys
```

## Windows 登录

旧 Dropbear 可能需要：

```powershell
ssh -i "$env:USERPROFILE\.ssh\be7000_router_rsa3072" `
  -o HostKeyAlgorithms=+ssh-rsa `
  -o PubkeyAcceptedAlgorithms=+ssh-rsa `
  root@192.168.31.1
```

## 只读验证

```sh
nvram get ssh_en
uci -q show dropbear
uci -q show firewall.auto_ssh
test -s /data/auto_ssh/auto_ssh.sh
test -s /data/auto_ssh/authorized_keys
```

## reboot 验证

与仓库早期版本不同，当前 SSH 持久化已经通过真实整机 reboot：

- 路由器重启后 Dropbear 自动恢复；
- 22 端口可重新连接；
- 密钥登录正常；
- 无需人工重新写入 `/etc`。

因此当前状态不再是“只验证落盘、未验证重启”。

## 回滚原则

SSH 相关写操作前必须保留一个已验证管理通道。

如果修改 SSH 恢复脚本：

1. 先备份；
2. shell 语法检查；
3. 手工执行测试；
4. 再更新 UCI include；
5. 不要为了验证小改动反复整机重启。
