#!/bin/sh
set -eu

REDIRECT_PORT=7895
DNS_PORT=7853
REDIRECT_PORT_HEX=1ED7
DNS_PORT_HEX=1EAD
CHAIN=B7G_0904_P6
COMMENT=B7G_0904_PERSISTENT_FAMILY_REDIR_DNS

IP=/sbin/ip
IPT=/usr/sbin/iptables-legacy
IPTSAVE=/usr/sbin/iptables-legacy-save
SHA256=/usr/bin/sha256sum

fail() {
  printf 'PERSISTENT_FAMILY_RULES_BLOCKED=%s\n' "$1"
  exit 70
}

listener_present() {
  hex_port=$1
  shift
  for table in "$@"; do
    test -r "$table" || continue
    grep -qi ":$hex_port " "$table" && return 0
  done
  return 1
}

cleanup_rules() {
  set +e
  for iface in br-lan br-miot; do
    "$IPT" -t filter -D FORWARD -i "$iface" -p udp --dport 443 -m comment --comment "$COMMENT" -j REJECT --reject-with icmp-port-unreachable >/dev/null 2>&1
    "$IPT" -t nat -D PREROUTING -i "$iface" -m comment --comment "$COMMENT" -j "$CHAIN" >/dev/null 2>&1
  done
  "$IPT" -t nat -F "$CHAIN" >/dev/null 2>&1
  "$IPT" -t nat -X "$CHAIN" >/dev/null 2>&1
  set -e
}

rollback() {
  original_exit=$?
  trap - 0 INT TERM HUP
  cleanup_rules
  cleanup_ok=1
  "$IPT" -t nat -S "$CHAIN" >/dev/null 2>&1 && cleanup_ok=0
  "$IPTSAVE" -t nat | grep -F "$COMMENT" >/dev/null 2>&1 && cleanup_ok=0
  "$IPTSAVE" -t filter | grep -F "$COMMENT" >/dev/null 2>&1 && cleanup_ok=0
  if test "$cleanup_ok" -eq 1; then
    printf 'PERSISTENT_FAMILY_RULES_ROLLBACK_VERIFIED\n'
    exit "$original_exit"
  fi
  printf 'PERSISTENT_FAMILY_RULES_ROLLBACK_FAILED\n'
  exit 90
}

for tool in "$IP" "$IPT" "$IPTSAVE" "$SHA256"; do
  test -x "$tool" || fail TOOL_MISSING
done
test -n "${EXPECTED_SELF_SHA256:-}" || fail SELF_SHA256_MISSING
set -- $("$SHA256" /guard.sh)
test "$1" = "$EXPECTED_SELF_SHA256" || fail SELF_SHA256_MISMATCH
printf 'PERSISTENT_FAMILY_GUARD_SELF_SHA256=%s\n' "$1"

listener_present "$REDIRECT_PORT_HEX" /proc/net/tcp /proc/net/tcp6 || fail CORE_LISTENER_LOST_TCP_7895
listener_present "$DNS_PORT_HEX" /proc/net/udp /proc/net/udp6 || fail CORE_LISTENER_LOST_DNS_7853
for iface in br-lan br-miot; do
  "$IP" link show dev "$iface" >/dev/null 2>&1 || fail "INTERFACE_$iface_MISSING"
done

trap 'rollback' 0
trap 'exit 130' INT TERM HUP

# Recover only this project's exact stale markers after an unclean guard exit.
cleanup_rules
"$IPT" -t nat -S "$CHAIN" >/dev/null 2>&1 && fail STALE_CHAIN_CLEANUP_FAILED || :
"$IPTSAVE" -t nat | grep -F "$COMMENT" >/dev/null 2>&1 && fail STALE_NAT_MARKER_CLEANUP_FAILED || :
"$IPTSAVE" -t filter | grep -F "$COMMENT" >/dev/null 2>&1 && fail STALE_FILTER_MARKER_CLEANUP_FAILED || :

"$IPT" -t nat -N "$CHAIN"
"$IPT" -t nat -A "$CHAIN" -p udp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"
"$IPT" -t nat -A "$CHAIN" -p tcp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"
for cidr in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
  "$IPT" -t nat -A "$CHAIN" -d "$cidr" -j RETURN
done
"$IPT" -t nat -A "$CHAIN" -p tcp -j REDIRECT --to-ports "$REDIRECT_PORT"

for iface in br-lan br-miot; do
  "$IPT" -t nat -I PREROUTING 1 -i "$iface" -m comment --comment "$COMMENT" -j "$CHAIN"
  "$IPT" -t filter -I FORWARD 1 -i "$iface" -p udp --dport 443 -m comment --comment "$COMMENT" -j REJECT --reject-with icmp-port-unreachable
done

printf 'PERSISTENT_FAMILY_RULES_ACTIVE=br-lan,br-miot\n'
printf 'PERSISTENT_FAMILY_SCOPE=IPV4_TCP_DNS_WITH_QUIC_FALLBACK\n'

while :; do
  sleep 5
  listener_present "$REDIRECT_PORT_HEX" /proc/net/tcp /proc/net/tcp6 || fail CORE_LISTENER_LOST_TCP_7895
  listener_present "$DNS_PORT_HEX" /proc/net/udp /proc/net/udp6 || fail CORE_LISTENER_LOST_DNS_7853
  for iface in br-lan br-miot; do
    "$IPT" -t nat -C PREROUTING -i "$iface" -m comment --comment "$COMMENT" -j "$CHAIN" >/dev/null 2>&1 || fail "NAT_HOOK_LOST_$iface"
    "$IPT" -t filter -C FORWARD -i "$iface" -p udp --dport 443 -m comment --comment "$COMMENT" -j REJECT --reject-with icmp-port-unreachable >/dev/null 2>&1 || fail "QUIC_GUARD_LOST_$iface"
  done
done
