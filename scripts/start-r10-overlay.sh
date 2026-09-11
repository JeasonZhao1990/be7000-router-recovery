#!/bin/sh
set -eu

[ "${1:-}" = --confirm ] || { echo 'Usage: start-r10-overlay.sh --confirm'; exit 64; }
DOCKER=${DOCKER:-/mnt/usb-fea0df2e/mi_docker/docker-binaries/docker}
HOST=${HOST:-unix:///var/run/docker.sock}
CORE=be7000-family-override-core-r10-20260911
RULES=be7000-family-override-rules-r10-20260911
dc() { "$DOCKER" -H "$HOST" "$@"; }

for stable in be7000-family-proxy-core-r6-20260907 be7000-family-proxy-rules-r6-20260907 be7000-family-ipv6-wan-guard-r17-20260908; do
  [ "$(dc inspect "$stable" --format '{{.State.Status}}|{{.HostConfig.RestartPolicy.Name}}')" = 'running|always' ] || {
    echo "BLOCKED_STABLE_SERVICE=$stable"
    exit 70
  }
done

[ "$(dc inspect "$CORE" --format '{{.State.Status}}')" != running ] || { echo R10_CORE_ALREADY_RUNNING; exit 70; }
[ "$(dc inspect "$RULES" --format '{{.State.Status}}')" != running ] || { echo R10_RULES_ALREADY_RUNNING; exit 70; }

rollback() {
  dc update --restart no "$RULES" >/dev/null 2>&1 || true
  dc stop -t 10 "$RULES" >/dev/null 2>&1 || true
  dc update --restart no "$CORE" >/dev/null 2>&1 || true
  dc stop -t 10 "$CORE" >/dev/null 2>&1 || true
}
trap rollback EXIT INT TERM

dc start "$CORE" >/dev/null
sleep 4
[ "$(dc inspect "$CORE" --format '{{.State.Status}}')" = running ] || exit 70
grep -qi ':1ED9 ' /proc/net/tcp /proc/net/tcp6 || exit 70
dc start "$RULES" >/dev/null
sleep 4
[ "$(dc inspect "$RULES" --format '{{.State.Status}}')" = running ] || exit 70
[ "$(iptables-save 2>/dev/null | grep -c B7G_0911_FAMILY_OVERRIDE_R10)" -eq 2 ] || exit 70
dc update --restart always "$CORE" >/dev/null
dc update --restart always "$RULES" >/dev/null
trap - EXIT INT TERM
echo R10_OVERLAY_RUNNING
