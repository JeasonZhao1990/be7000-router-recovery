#!/bin/sh
# Read-only audit for the current BE7000 production layout.
# This script intentionally makes no network/firewall/container changes.

set -u

find_docker() {
    if [ -n "${DOCKER:-}" ] && [ -x "$DOCKER" ]; then
        return 0
    fi

    for x in /mnt/usb-*/mi_docker/docker-binaries/docker; do
        if [ -x "$x" ]; then
            DOCKER="$x"
            return 0
        fi
    done
    return 1
}

if ! find_docker; then
    echo "ERROR: Docker CLI not found. Set DOCKER=/mnt/usb-xxxx/mi_docker/docker-binaries/docker"
    exit 2
fi

HOST=${HOST:-unix:///var/run/docker.sock}
dc() { "$DOCKER" -H "$HOST" "$@"; }

R3=be7000-family-tun-r3-unified
R6C=be7000-family-proxy-core-r6-20260907
R6R=be7000-family-proxy-rules-r6-20260907
R10C=be7000-family-override-core-r10-20260911
R10R=be7000-family-override-rules-r10-20260911
V6G=be7000-family-ipv6-wan-guard-r17-20260908

rc=0

echo "BEGIN_BE7000_AUDIT"
echo "DOCKER=$DOCKER"

echo "===== DOCKER VERSION ====="
dc version --format 'CLIENT={{.Client.Version}}/{{.Client.Arch}} SERVER={{.Server.Version}}/{{.Server.Arch}} API={{.Server.APIVersion}}' 2>/dev/null || rc=1

printf 'TOTAL='
dc ps -aq 2>/dev/null | wc -l
printf 'RUNNING='
dc ps -q 2>/dev/null | wc -l

echo "===== EXPECTED CONTAINERS ====="
for name in \
  "$R3" \
  "$R6C" \
  "$R6R" \
  "$R10C" \
  "$R10R" \
  "$V6G" \
  simple-docker \
  openlist
do
    if dc inspect "$name" >/dev/null 2>&1; then
        dc inspect "$name" --format '{{.Name}}|{{.State.Status}}|restart={{.HostConfig.RestartPolicy.Name}}|privileged={{.HostConfig.Privileged}}|mounts={{range .Mounts}}{{.Source}}>{{.Destination}};{{end}}'
    else
        echo "MISSING|$name"
        rc=1
    fi
done

echo "===== OBSOLETE TEST CONTAINERS ====="
for name in be7000-family-tun-r1-lab be7000-family-tun-r2-hostcanary; do
    if dc inspect "$name" >/dev/null 2>&1; then
        echo "PRESENT|$name"
    else
        echo "ABSENT|$name"
    fi
done

echo "===== DOCKER OFFICIAL CHECKS ====="
integrity_exit=0
/etc/init.d/mi_docker check_integrity >/dev/null 2>&1 || integrity_exit=$?
echo "CHECK_INTEGRITY_EXIT=$integrity_exit"
[ "$integrity_exit" -eq 0 ] || rc=1

running_exit=0
/etc/init.d/mi_docker is_running >/dev/null 2>&1 || running_exit=$?
echo "IS_RUNNING_EXIT=$running_exit"
[ "$running_exit" -eq 0 ] || rc=1

echo "===== UCI PERSISTENCE ====="
uci -q show firewall.auto_ssh || {
    echo "MISSING firewall.auto_ssh"
    rc=1
}
uci -q show firewall.r3_family || {
    echo "MISSING firewall.r3_family"
    rc=1
}

echo "===== R3 TUN ====="
ip link show b7g-tun-r3 2>/dev/null || {
    echo "MISSING b7g-tun-r3"
    rc=1
}

echo "===== TABLE 2074 IPv4 ====="
ip route show table 2074 2>/dev/null || rc=1

echo "===== TABLE 2074 IPv6 ====="
ip -6 route show table 2074 2>/dev/null || rc=1

echo "===== POLICY RULES ====="
ip rule show 2>/dev/null | grep -E '2074[0-9]|lookup 2074' || true
ip -6 rule show 2>/dev/null | grep -E '20760|lookup 2074|b7g-tun-r3|lookup 2022' || true

echo "===== R3 CONFIG / HOME-VLESS IP VERSION ====="
R3_CFG_DIR=$(
    dc inspect "$R3" \
      --format '{{range .Mounts}}{{if eq .Destination "/run/mihomo"}}{{.Source}}{{end}}{{end}}' \
      2>/dev/null
)

if [ -n "$R3_CFG_DIR" ] && [ -f "$R3_CFG_DIR/config.json" ]; then
    echo "R3_CONFIG_PRESENT=$R3_CFG_DIR/config.json"
    if command -v jsonfilter >/dev/null 2>&1; then
        ipver=$(
            jsonfilter -i "$R3_CFG_DIR/config.json" \
              -e '@.proxies[@.name="HOME-VLESS"]' 2>/dev/null |
            jsonfilter -e '@["ip-version"]' 2>/dev/null
        )
        [ -n "$ipver" ] && echo "HOME_VLESS_IP_VERSION=$ipver" || echo "HOME_VLESS_IP_VERSION=<default/unspecified>"
    else
        echo "HOME_VLESS_IP_VERSION=<jsonfilter unavailable>"
    fi
else
    echo "R3_CONFIG_NOT_VISIBLE_AT_EXPECTED_MOUNT"
fi

echo "===== IPv6 WAN GUARD ====="
dc exec "$V6G" sh -c \
  'nft list table inet b7g_ipv6_wan_guard_17 2>/dev/null' || rc=1

echo "===== FAMILY RESTORE LOG TAIL ====="
for f in /tmp/b7g_r3_family_restore.log /tmp/r3-family-restore.log; do
    if [ -f "$f" ]; then
        echo "LOG=$f"
        tail -n 40 "$f"
    fi
done

echo "AUDIT_RC=$rc"
echo "END_BE7000_AUDIT"
exit "$rc"
