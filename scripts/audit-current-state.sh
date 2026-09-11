#!/bin/sh
set -eu

DOCKER=${DOCKER:-/mnt/usb-fea0df2e/mi_docker/docker-binaries/docker}
HOST=${HOST:-unix:///var/run/docker.sock}
dc() { "$DOCKER" -H "$HOST" "$@"; }

echo BEGIN_BE7000_AUDIT
dc version --format 'CLIENT={{.Client.Version}}/{{.Client.Arch}} SERVER={{.Server.Version}}/{{.Server.Arch}} API={{.Server.APIVersion}}'
printf 'TOTAL='; dc ps -aq | wc -l
printf 'RUNNING='; dc ps -q | wc -l

for name in \
  be7000-family-proxy-core-r6-20260907 \
  be7000-family-proxy-rules-r6-20260907 \
  be7000-family-override-core-r10-20260911 \
  be7000-family-override-rules-r10-20260911 \
  be7000-family-ipv6-wan-guard-r17-20260908 \
  simple-docker; do
  dc inspect "$name" --format '{{.Name}}|{{.State.Status}}|restart={{.HostConfig.RestartPolicy.Name}}|privileged={{.HostConfig.Privileged}}|mounts={{range .Mounts}}{{.Source}}>{{.Destination}};{{end}}'
done

integrity_exit=0
/etc/init.d/mi_docker check_integrity >/dev/null 2>&1 || integrity_exit=$?
echo CHECK_INTEGRITY_EXIT=$integrity_exit
running_exit=0
/etc/init.d/mi_docker is_running >/dev/null 2>&1 || running_exit=$?
echo IS_RUNNING_EXIT=$running_exit

dc exec be7000-family-proxy-rules-r6-20260907 /usr/sbin/iptables-legacy-save 2>/dev/null |
  grep -E 'B7G_0904_PERSISTENT_FAMILY_REDIR_DNS|B7G_0911_FAMILY_OVERRIDE_R10' || true
dc exec be7000-family-ipv6-wan-guard-r17-20260908 \
  /usr/sbin/nft list table inet b7g_ipv6_wan_guard_17 2>/dev/null || true
echo END_BE7000_AUDIT
