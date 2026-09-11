#!/bin/sh
set -eu

TABLE=b7g_ipv6_wan_guard_17
# nft object: table inet b7g_ipv6_wan_guard_17
COMMENT=B7G_0908_FAMILY_IPV6_WAN_GUARD_R17
EXPECTED_SELF_SHA256=${EXPECTED_SELF_SHA256:?EXPECTED_SELF_SHA256 missing}
NFT=/usr/sbin/nft
SHA256=/usr/bin/sha256sum

fail() { printf 'FAMILY_IPV6_WAN_GUARD_BLOCKED=%s\n' "$1"; exit "${2:-70}"; }
test -x "$NFT" || fail NFT_MISSING
test -x "$SHA256" || fail SHA256_MISSING
set -- $("$SHA256" /controller.sh)
test "$1" = "$EXPECTED_SELF_SHA256" || fail SELF_SHA256_MISMATCH
printf 'FAMILY_IPV6_WAN_GUARD_CONTROLLER_SELF_SHA256=%s\n' "$1"
"$NFT" list table inet "$TABLE" >/dev/null 2>&1 && fail TABLE_ALREADY_EXISTS

cleanup() {
  code=$?
  trap - 0 INT TERM HUP
  set +e
  "$NFT" list table inet "$TABLE" >/dev/null 2>&1 && "$NFT" delete table inet "$TABLE" >/dev/null 2>&1
  "$NFT" list table inet "$TABLE" >/dev/null 2>&1 && { printf 'FAMILY_IPV6_WAN_GUARD_CLEANUP_FAILED\n'; exit 90; }
  printf 'FAMILY_IPV6_WAN_GUARD_CLEANUP_VERIFIED\n'
  exit "$code"
}
trap cleanup 0
trap 'exit 130' INT TERM HUP

# One nft batch atomically creates the private table and both WAN reject rules.
# Policy form: iifname "br-lan" oifname "pppoe-wan" ip6 saddr != fc00::/7 reject with icmpv6 type no-route
# Policy form: iifname "br-miot" oifname "pppoe-wan" ip6 saddr != fc00::/7 reject with icmpv6 type no-route
"$NFT" -f - <<EOF
add table inet $TABLE
add chain inet $TABLE forward { type filter hook forward priority -1; policy accept; }
add rule inet $TABLE forward iifname "br-lan" oifname "pppoe-wan" ip6 saddr != fc00::/7 counter reject with icmpv6 type no-route comment "$COMMENT br-lan"
add rule inet $TABLE forward iifname "br-miot" oifname "pppoe-wan" ip6 saddr != fc00::/7 counter reject with icmpv6 type no-route comment "$COMMENT br-miot"
EOF
"$NFT" list table inet "$TABLE" | grep -F 'reject with icmpv6 no-route' >/dev/null || fail TABLE_RULES_MISSING
printf 'FAMILY_IPV6_WAN_GUARD_ACTIVE=br-lan,br-miot->pppoe-wan\n'
printf 'FAMILY_IPV6_WAN_GUARD_SCOPE=IPV6_WAN_ONLY_LOCAL_PRESERVED\n'
while :; do
  sleep 5
  "$NFT" list table inet "$TABLE" >/dev/null 2>&1 || fail NFT_TABLE_LOST
  "$NFT" list table inet "$TABLE" | grep -F 'reject with icmpv6 no-route' >/dev/null || fail NFT_RULES_LOST
done
