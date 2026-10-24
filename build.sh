#!/bin/bash
# Builds the Jetson Linux kernel with BTF, the function tracer and socket diag
# from the board's running config, plus NVIDIA's out-of-tree modules.
# Runs inside an ubuntu:24.04 container with this directory mounted at /k;
# use ./build-in-docker.sh rather than running it directly.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends build-essential bc flex bison libssl-dev \
  libelf-dev zstd dwarves kmod cpio python3 rsync ca-certificates >/dev/null
# DEBUG_INFO_BTF needs pahole from dwarves.
pahole --version

cd /k/Linux_for_Tegra/source
export CROSS_COMPILE=/k/toolchain/x-tools/aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-
# A separate release string, such as 6.8.12-1021-tegra-btf, keeps the stock
# kernel's /lib/modules untouched so it remains a working fallback.
stock=$(cat /k/running.uname)
export LOCALVERSION=-${stock#*-}-btf
KSRC=$PWD/kernel/kernel-noble

# Start from the running kernel's config and change only what is needed.
# DEBUG_INFO_REDUCED blocks DEBUG_INFO_BTF, so it must be turned off.
cp /k/running.config "$KSRC/.config"
"$KSRC/scripts/config" --file "$KSRC/.config" \
  --disable DEBUG_INFO_REDUCED \
  --enable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT \
  --enable DEBUG_INFO_BTF \
  --enable DEBUG_INFO_BTF_MODULES \
  --enable FTRACE \
  --enable FUNCTION_TRACER \
  --enable DYNAMIC_FTRACE \
  --enable UNIX_DIAG \
  --enable NETLINK_DIAG \
  --enable PACKET_DIAG
make -C "$KSRC" ARCH=arm64 LOCALVERSION="$LOCALVERSION" olddefconfig
# kernel/Makefile runs "make defconfig" first, which would overwrite .config.
cp "$KSRC/.config" "$KSRC/arch/arm64/configs/tegra_btf_defconfig"
cp "$KSRC/.config" /k/btf.config
grep -E "CONFIG_(DEBUG_INFO_BTF|DEBUG_INFO_BTF_MODULES|DEBUG_INFO_REDUCED|FUNCTION_TRACER|DYNAMIC_FTRACE_WITH_DIRECT_CALLS|UNIX_DIAG|NETLINK_DIAG|PACKET_DIAG|MODULE_SIG_ALL)[= ]" "$KSRC/.config" || true

make -C kernel KERNEL_DEF_CONFIG=tegra_btf_defconfig
export KERNEL_HEADERS=$KSRC kernel_name=noble
# Out-of-tree modules are not relinked when vmlinux changes, but their split
# BTF must match it or the kernel refuses to load them ("BTF: -22"), which
# takes down the Ethernet, GPU and display drivers.
make clean
make modules
stale=$(find nvidia-oot nvgpu hwpm nvdisplay unifiedgpudisp -name '*.ko' ! -newer "$KSRC/vmlinux" 2>/dev/null | wc -l)
test "$stale" -eq 0 || { echo "$stale out-of-tree modules are older than vmlinux" >&2; exit 1; }

rm -rf /k/out && mkdir -p /k/out/boot
export INSTALL_MOD_PATH=/k/out
# Strip debug info during install, before MODULE_SIG_ALL signs each module.
# Stripping afterwards would remove the signatures. BTF sections are kept.
export INSTALL_MOD_STRIP=1
make -C kernel KERNEL_DEF_CONFIG=tegra_btf_defconfig install
make modules_install
release=$(cat "$KSRC/include/config/kernel.release")
cp "$KSRC/System.map" "/k/out/boot/System.map-$release"
echo "$release" > /k/out/kernel.release
rm -f "/k/out/lib/modules/$release/build"

# A few staging modules are installed unsigned; sign them with the same key.
find "/k/out/lib/modules/$release" -name '*.ko' | while read -r module; do
  tail -c 28 "$module" | grep -q "Module signature appended" ||
    "$KSRC/scripts/sign-file" sha512 "$KSRC/certs/signing_key.pem" "$KSRC/certs/signing_key.x509" "$module"
done
ls -la /k/out/boot "/k/out/lib/modules/$release"
