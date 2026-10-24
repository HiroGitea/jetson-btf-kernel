#!/bin/bash
# Downloads and extracts the Jetson Linux r39.2.1 kernel sources and NVIDIA's
# cross toolchain into this directory, verifying the published archives.
set -euo pipefail
cd "$(dirname "$0")"

L4T=https://developer.nvidia.com/downloads/embedded/L4T
download() {
  local url=$1 file=$2 sha256=$3
  [ -f "$file" ] || curl -fL --retry 3 -o "$file" "$url"
  echo "$sha256  $file" | sha256sum -c -
}
download "$L4T/r39_Release_v2.1/sources/public_sources.tbz2" public_sources.tbz2 \
  8346f0371649a92c42293b2d4a7bf3d69e4dd1de23009e1463ea910994a81371
# The JetPack 7.2.1 download page links this toolchain from the r38 path.
download "$L4T/r38_Release_v2.0/release/x-tools.tbz2" x-tools.tbz2 \
  6bf10ad05bc6a5f296e592a78d87771b87f0dc917337ba9f4ab4b0f7aabad889

tar xf public_sources.tbz2
mkdir -p toolchain
tar xf x-tools.tbz2 -C toolchain
cd Linux_for_Tegra/source
for name in kernel_src kernel_oot_modules_src kernel_nvgpu_src \
  nvidia_kernel_display_driver_source nvidia_unified_gpu_display_driver_source; do
  # The .sha1sum files name NVIDIA's build paths, so compare the hash only.
  test "$(sha1sum "$name.tbz2" | cut -d' ' -f1)" = "$(cut -d' ' -f1 "$name.tbz2.sha1sum")"
  tar xf "$name.tbz2"
done
echo "Sources ready in Linux_for_Tegra/source"
