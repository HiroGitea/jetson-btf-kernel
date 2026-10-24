#!/bin/bash
# Copies the running kernel's config and the stock initrd from a Jetson.
# Usage: ./fetch-from-board.sh user@jetson
# Nothing on the board is changed.
set -euo pipefail
cd "$(dirname "$0")"
board=${1:?usage: $0 user@jetson}

ssh "$board" uname -r > running.uname
ssh "$board" zcat /proc/config.gz > running.config
rm -rf initrd-stock && mkdir -p initrd-stock/root
ssh "$board" cat /boot/initrd > initrd-stock/initrd.gz
(cd initrd-stock/root && zcat ../initrd.gz | cpio -id --quiet)
echo "Board kernel: $(cat running.uname)"
echo "Modules in the stock initrd: $(find initrd-stock/root -name '*.ko*' | wc -l)"
