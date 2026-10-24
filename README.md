# jetson-btf-kernel

Scripts that rebuild the NVIDIA Jetson Linux kernel with BTF and the function tracer, so that modern eBPF tools (CO-RE programs, `tp_btf`, `fentry`/`fexit`) work on a Jetson. The stock JetPack 7.2 kernel is built without `CONFIG_DEBUG_INFO_BTF` and `CONFIG_FUNCTION_TRACER`, so such programs fail to load, for example with `ESRCH`.

The new kernel is installed next to the stock one with its own release string, such as `6.8.12-1021-tegra-btf`. The stock kernel, its modules and its boot entry are not changed, so you can always boot back into it.

I wrote this to run [ProcInSh](https://github.com/akawashiro/procinsh)'s eBPF sensors on a Jetson, but nothing here is specific to ProcInSh.

## Tested on

- Jetson Orin Nano 4GB developer kit, JetPack 7.2.1 (Jetson Linux r39.2.1), kernel `6.8.12-1021-tegra`, rootfs on NVMe, Secure Boot off
- Build host: x86-64 Linux with Docker

Other boards and releases may need different download URLs, hashes or initrd contents. Treat them as untested.

## Config changes

The build starts from the board's running config (`/proc/config.gz`) and changes only these options:

| Option | Value | Why |
|---|---|---|
| `DEBUG_INFO_BTF`, `DEBUG_INFO_BTF_MODULES` | on | `/sys/kernel/btf/vmlinux` and module BTF for CO-RE and `tp_btf` |
| `DEBUG_INFO_REDUCED` | off | It blocks `DEBUG_INFO_BTF` |
| `FTRACE`, `FUNCTION_TRACER`, `DYNAMIC_FTRACE` | on | `fentry`/`fexit`; on arm64 this also enables `DYNAMIC_FTRACE_WITH_DIRECT_CALLS` |
| `UNIX_DIAG`, `NETLINK_DIAG`, `PACKET_DIAG` | on | Socket diagnostics, for example UNIX socket peers in `ss -xp` |

## Usage

You need about 25 GB of free disk space on the build host, SSH access to the Jetson and a serial console in case the new kernel does not boot.

```sh
# 1. Download NVIDIA's r39.2.1 sources and cross toolchain (about 450 MB).
./fetch-sources.sh

# 2. Copy the running kernel config and the stock initrd from the board.
./fetch-from-board.sh user@jetson

# 3. Cross-compile the kernel and NVIDIA's out-of-tree modules in Docker,
#    then pack the initrd and jetson-btf-kernel.tar.gz.
./build-in-docker.sh

# 4. Install on the board and reboot.
scp jetson-btf-kernel.tar.gz install-on-jetson.sh user@jetson:
ssh -t user@jetson 'sudo ./install-on-jetson.sh jetson-btf-kernel.tar.gz && sudo reboot'
```

After the reboot, check:

```sh
uname -r                          # 6.8.12-1021-tegra-btf
ls -l /sys/kernel/btf/vmlinux     # present
cat /proc/sys/kernel/tainted      # 4096 (out-of-tree modules only, like the stock kernel)
lsmod | grep -E '^(r8168|nvgpu|nvidia) '
systemctl --failed
```

To update to a new build, boot the stock kernel and run `install-on-jetson.sh` again.

## Falling back and uninstalling

The boot menu waits 3 seconds on the serial console. Choose `primary kernel` to boot the stock kernel. To remove the BTF kernel, boot the stock kernel and run:

```sh
sudo ./uninstall-on-jetson.sh
```

This restores `/boot/extlinux/extlinux.conf` from the backup taken on the first install and removes the BTF kernel's files.

An upgrade of `nvidia-l4t-kernel` resets `DEFAULT` in `extlinux.conf` to the stock kernel. Set it back to `btf` or rerun the install script.

## Pitfalls these scripts handle

- **Out-of-tree modules must be rebuilt after every kernel change.** NVIDIA's modules (Ethernet, GPU, display, ...) are not relinked when `vmlinux` changes. Their BTF then no longer matches the kernel, and the kernel refuses to load them with `failed to validate module [r8168] BTF: -22`, which takes down the network. `build.sh` runs `make clean` first and fails if any out-of-tree module is older than `vmlinux`.
- **Strip modules before signing, not after.** Full debug info makes the modules about 2 GB. `INSTALL_MOD_STRIP=1` strips them during install, before `MODULE_SIG_ALL` signs them. Running `strip` afterwards removes the signatures and taints the kernel. BTF sections survive stripping.
- **The initrd needs matching modules.** The stock initrd loads NVMe, PCIe and Ethernet modules for the running kernel's release. `pack-initrd.sh` copies the stock initrd and replaces those modules with the new build's.
- **`kernel/Makefile` regenerates `.config` from a defconfig.** The modified config is saved as `tegra_btf_defconfig` and passed as `KERNEL_DEF_CONFIG`.
- **Secure Boot.** These scripts do not sign the kernel or initrd for UEFI Secure Boot. With Secure Boot enabled, follow NVIDIA's Secure Boot guide.

## What is not included

This repository contains only scripts. NVIDIA's sources and toolchain are downloaded from NVIDIA by `fetch-sources.sh`. The build generates its own module signing key under `Linux_for_Tegra/source/kernel/kernel-noble/certs/`. Keep it private if you share builds.

## References

- [Kernel Customization, Jetson Linux r39.2.1 Developer Guide](https://docs.nvidia.com/jetson/archives/r39.2.1/DeveloperGuide/SD/Kernel/KernelCustomization.html)
- [JetPack 7.2.1 downloads](https://developer.nvidia.com/embedded/jetpack/downloads/archive-7.2.1.md)

## License

MIT. See [LICENSE](LICENSE).
