#!/bin/sh
set -eu

DOCKER=${DOCKER:-/mnt/usb-fea0df2e/mi_docker/docker-binaries/docker}
HOST=${HOST:-unix:///var/run/docker.sock}
USB_ROOT=${USB_ROOT:-/mnt/usb-fea0df2e}
dc() { "$DOCKER" -H "$HOST" "$@"; }

echo BEGIN_INVALID_MOUNT_AUDIT
found=0
for id in $(dc ps -aq); do
  name=$(dc inspect "$id" --format '{{.Name}}')
  state=$(dc inspect "$id" --format '{{.State.Status}}')
  mounts=$(dc inspect "$id" --format '{{range .Mounts}}{{.Source}}{{println}}{{end}}')
  for src in $mounts; do
    case "$src" in
      "$USB_ROOT"/*|/var/run/docker.sock) : ;;
      *) echo "INVALID|$name|$state|$src"; found=1 ;;
    esac
  done
done
[ "$found" -eq 0 ] && echo INVALID_MOUNTS=0
echo END_INVALID_MOUNT_AUDIT
