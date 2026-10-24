#!/bin/bash
# Builds out/boot/initrd.btf from the stock Jetson initrd by replacing its
# modules (NVMe, PCIe, Ethernet, ...) with the same modules from the new build.
# The root filesystem is on NVMe, so a missing module here means no boot.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
new=$(cat "$here/out/kernel.release")
old=$(cat "$here/running.uname")
rm -rf "$here/initrd-btf"
cp -a "$here/initrd-stock/root" "$here/initrd-btf"
cd "$here/initrd-btf/usr/lib/modules"
mkdir "$new"
(cd "$old" && find . -name '*.ko*' | sed 's#^\./##') | while read -r rel; do
  mkdir -p "$new/$(dirname "$rel")"
  cp "$here/out/lib/modules/$new/$rel" "$new/$rel"
done
cp "$here/out/lib/modules/$new"/modules.builtin* "$here/out/lib/modules/$new/modules.order" "$new/"
rm -rf "$old"
depmod -b "$here/initrd-btf/usr" -a "$new"
cd "$here/initrd-btf"
find . -print0 | sort -z | cpio --null -o -H newc -R 0:0 --quiet | gzip -9 -n > "$here/out/boot/initrd.btf"
echo "initrd modules: $(find "$here/initrd-btf/usr/lib/modules/$new" -name '*.ko*' | wc -l)"
