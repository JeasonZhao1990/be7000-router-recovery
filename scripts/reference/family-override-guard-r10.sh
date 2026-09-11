#!/bin/sh
set -eu

ipt=/usr/sbin/iptables-legacy
chain=B7G_0911_OVR10
marker=B7G_0911_FAMILY_OVERRIDE_R10
disabled=0

cleanup() {
  for iface in br-lan br-miot; do
    while "$ipt" -t nat -C PREROUTING -i "$iface" -p tcp --dport 443 -m comment --comment "$marker" -j "$chain" 2>/dev/null; do
      "$ipt" -t nat -D PREROUTING -i "$iface" -p tcp --dport 443 -m comment --comment "$marker" -j "$chain" || true
    done
  done
  "$ipt" -t nat -F "$chain" 2>/dev/null || true
  "$ipt" -t nat -X "$chain" 2>/dev/null || true
}
disable_to_fallback() {
  reason=$1
  cleanup
  echo "FAMILY_OVERRIDE_FALLBACK_ACTIVE=$reason"
  disabled=1
}
trap cleanup EXIT INT TERM
cleanup

grep -qi ':1ED9 ' /proc/net/tcp /proc/net/tcp6 || {
  echo FAMILY_OVERRIDE_GUARD_BLOCKED=PORT_7897_NOT_LISTENING
  exit 70
}

"$ipt" -t nat -N "$chain"
for cidr in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
  "$ipt" -t nat -A "$chain" -d "$cidr" -j RETURN
done
"$ipt" -t nat -A "$chain" -p tcp --dport 443 -j REDIRECT --to-ports 7897
"$ipt" -t nat -I PREROUTING 1 -i br-lan -p tcp --dport 443 -m comment --comment "$marker" -j "$chain"
"$ipt" -t nat -I PREROUTING 1 -i br-miot -p tcp --dport 443 -m comment --comment "$marker" -j "$chain"

echo FAMILY_OVERRIDE_GUARD_ACTIVE=br-lan,br-miot:tcp443
echo FAMILY_OVERRIDE_FALLBACK=OLD_PERSISTENT_PATH
while :; do
  sleep 15
  [ "$disabled" -eq 0 ] || continue
  if ! grep -qi ':1ED9 ' /proc/net/tcp /proc/net/tcp6; then
    disable_to_fallback LISTENER_7897_MISSING
    continue
  fi
  if [ ! -d /proc/1/fd ]; then
    disable_to_fallback CORE_PROCESS_MISSING
    continue
  fi
  fd=$(ls -1 /proc/1/fd 2>/dev/null | wc -l)
  if [ "$fd" -ge 7000 ] 2>/dev/null; then
    disable_to_fallback "FD_LIMIT_NEAR_$fd"
    continue
  fi
done
