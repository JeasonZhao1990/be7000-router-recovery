#!/bin/sh
set -eu

[ "${1:-}" = --confirm ] || { echo 'Usage: stop-r10-overlay.sh --confirm'; exit 64; }
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

dc update --restart no "$RULES" >/dev/null
[ "$(dc inspect "$RULES" --format '{{.State.Status}}')" != running ] || dc stop -t 10 "$RULES" >/dev/null
dc update --restart no "$CORE" >/dev/null
[ "$(dc inspect "$CORE" --format '{{.State.Status}}')" != running ] || dc stop -t 10 "$CORE" >/dev/null

iptables-save 2>/dev/null | grep -q B7G_0911_FAMILY_OVERRIDE_R10 && {
  echo R10_ROLLBACK_BLOCKED=MARKER_REMAINS
  exit 70
}
echo R10_OVERLAY_STOPPED_R6_PRESERVED
