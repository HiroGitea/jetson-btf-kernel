#!/bin/bash
# Runs build.sh in a throwaway ubuntu:24.04 container, then packs the initrd
# and the bundle that install-on-jetson.sh expects.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
docker run --rm --mount "type=bind,src=$here,dst=/k" ubuntu:24.04 \
  bash -c "/k/build.sh; rc=\$?; chown -R $(id -u):$(id -g) /k; exit \$rc"
"$here/pack-initrd.sh"
(cd "$here/out" && tar -czf "$here/jetson-btf-kernel.tar.gz" boot lib)
echo "Bundle: $here/jetson-btf-kernel.tar.gz"
