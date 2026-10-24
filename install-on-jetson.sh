#!/bin/bash
# Run as root on the Jetson: sudo ./install-on-jetson.sh jetson-btf-kernel.tar.gz
# Installs the BTF kernel next to the stock one, adds a "btf" extlinux entry
# and makes it the default. Running it again replaces an earlier BTF build.
# The stock kernel, its modules and the "primary" entry are not changed.
set -euo pipefail
bundle=${1:?usage: $0 jetson-btf-kernel.tar.gz}
conf=/boot/extlinux/extlinux.conf
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tar -xzf "$bundle" -C "$work"
release=$(ls "$work/lib/modules")
test "$(echo "$release" | wc -w)" -eq 1
test "$release" != "$(uname -r)" || { echo "refusing to replace the running kernel $release" >&2; exit 1; }

install -o root -g root -m 0644 "$work/boot/Image" /boot/Image.btf
install -o root -g root -m 0644 "$work/boot/initrd.btf" /boot/initrd.btf
install -o root -g root -m 0644 "$work/boot/System.map-$release" "/boot/System.map-$release"
rm -rf "/lib/modules/$release"
cp -a "$work/lib/modules/$release" "/lib/modules/$release"
chown -R root:root "/lib/modules/$release"
depmod -a "$release"

if ! grep -q '^LABEL btf$' "$conf"; then
  cp -a "$conf" "$conf.orig"
  append=$(awk '/^LABEL primary/{p=1} p && /^[[:space:]]*APPEND/{sub(/^[[:space:]]*APPEND[[:space:]]*/, ""); print; exit}' "$conf")
  test -n "$append"
  python3 - "$conf" "$append" "$release" <<'EOF'
import sys
path, append, release = sys.argv[1:]
text = open(path).read()
entry = (
    "LABEL btf\n"
    f"      MENU LABEL BTF kernel ({release})\n"
    "      LINUX /boot/Image.btf\n"
    "      INITRD /boot/initrd.btf\n"
    f"      APPEND {append}\n\n"
)
assert "LABEL primary\n" in text
text = text.replace("LABEL primary\n", entry + "LABEL primary\n", 1)
open(path, "w").write(text)
EOF
fi
sed -i 's/^DEFAULT .*/DEFAULT btf/' "$conf"
diff -u "$conf.orig" "$conf" || true
echo "Installed $release. Reboot to use it; choose \"primary kernel\" in the boot menu to fall back."
