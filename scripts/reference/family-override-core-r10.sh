#!/bin/sh
set -eu

nofile=$(ulimit -n)
[ "$nofile" -ge 8192 ] || { echo "FAMILY_OVERRIDE_CORE_BLOCKED=NOFILE_$nofile"; exit 70; }
check() { printf '%s  %s\n' "$1" "$2" | sha256sum -c - >/dev/null; }
check 15089b1aad4c793f72b2c0ef8a2d67a9d4b95ccbad8a406439a835a11d96fb76 /bundle/config.json
check f661b3b816b2ae819a19c73f681e9f54949cc58fcb90bbfe86adca81920f8ea4 /bundle/rules/cn-domain.mrs
check e2f47822bcd37f867673f0b5d95bae0f1f1fb07a7af52ed1408b1df27c1c4822 /bundle/rules/cn-ip.mrs

mkdir -p /run/mihomo/rules
sed \
  -e 's/"type": "tproxy"/"type": "redir"/' \
  -e 's/"listen": "::"/"listen": "0.0.0.0"/' \
  -e 's/"port": 7894/"port": 7897/' \
  -e 's/"ipv6": true/"ipv6": false/g' \
  -e 's/"override-destination": false/"override-destination": true/' \
  -e 's/"log-level": "silent"/"log-level": "warning"/' \
  -e '/"udp": true/d' \
  /bundle/config.json | awk '
    { print }
    /^[[:space:]]*"dns":[[:space:]]*\{[[:space:]]*$/ {
      print "    \"listen\": \"0.0.0.0:7855\","
    }
  ' > /run/mihomo/config.json

grep -F '"type": "redir"' /run/mihomo/config.json >/dev/null
grep -F '"listen": "0.0.0.0"' /run/mihomo/config.json >/dev/null
grep -F '"port": 7897' /run/mihomo/config.json >/dev/null
grep -F '"listen": "0.0.0.0:7855"' /run/mihomo/config.json >/dev/null
grep -F '"override-destination": true' /run/mihomo/config.json >/dev/null
cp /bundle/rules/cn-domain.mrs /run/mihomo/rules/cn-domain.mrs
cp /bundle/rules/cn-ip.mrs /run/mihomo/rules/cn-ip.mrs
chmod 0600 /run/mihomo/config.json /run/mihomo/rules/cn-domain.mrs /run/mihomo/rules/cn-ip.mrs

/usr/local/bin/mihomo -t -d /run/mihomo -f /run/mihomo/config.json
echo FAMILY_OVERRIDE_CORE_READY_NOFILE_8192
exec /usr/local/bin/mihomo -d /run/mihomo -f /run/mihomo/config.json
