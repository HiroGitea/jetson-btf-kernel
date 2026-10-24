#!/bin/bash
# Run as root on the Jetson while the stock kernel is running:
#   sudo ./uninstall-on-jetson.sh
# Restores extlinux.conf from the backup install-on-jetson.sh made and removes
# the BTF kernel, initrd, System.map and modules.
set -euo pipefail
conf=/boot/extlinux/extlinux.conf
release=$(sed -n 's/.*MENU LABEL BTF kernel (\(.*\))$/\1/p' "$conf")
test -n "$release" || { echo "no BTF entry in $conf" >&2; exit 1; }
test "$release" != "$(uname -r)" || { echo "boot the stock kernel before uninstalling" >&2; exit 1; }
test -f "$conf.orig"
mv "$conf.orig" "$conf"
rm -f /boot/Image.btf /boot/initrd.btf "/boot/System.map-$release"
rm -rf "/lib/modules/$release"
echo "Removed $release; $conf restored."
