# 测试容器清理记录（2026-09-11）

## 清理前

```text
总容器：132
运行中：7
已退出：124
created：1
```

审计确认 126 个候选均为 `be7000-*` 前期测试、reader、loader、canary、probe、build 或诊断容器：

- 无 Docker 数据卷；
- restart policy 均为 `no`；
- 非项目停止容器为 0；
- 唯一仍运行的候选 `be7000-mihomo-core-20260904` 没有规则或容器依赖。

## 归档

删除前保存了 126 份名称、完整 inspect 和每个容器末尾 500 行日志：

```text
/mnt/usb-xxxx/be7000_proxy_20260904/container-cleanup-20260911/
├── archive-complete.txt
├── container-names.txt          # 126 行
├── containers.inspect.json
├── log-tail/
└── log-tail.tar.gz
```

这些现场日志可能包含网络目标和设备地址，因此没有上传 GitHub。

## 清理后

```text
总容器：6
运行中：6
已退出：0
created：0
违规挂载：0
```

没有删除镜像、数据卷、脚本、配置或 Docker 数据目录。

## 不可照搬的地方

历史清理脚本使用了“候选必须恰好为 126”的现场门槛。未来数量必然不同，不能重跑该脚本。应先生成新清单，明确保留名单，逐个确认数据卷和运行状态，再取得新的删除授权。
