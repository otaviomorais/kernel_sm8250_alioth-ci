#!/usr/bin/env bash
# Validate the final MagicTime .config after KernelSU-Next + SUSFS integration.
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <kernel-dir> <final-config>" >&2
    exit 2
fi

KERNEL="$(cd "$1" && pwd)"
CONFIG="$2"

if [[ ! -d "$KERNEL" || ! -f "$CONFIG" ]]; then
    echo "error: kernel directory or config is missing" >&2
    exit 1
fi

require_equal() {
    local symbol="$1"
    if ! grep -q "^CONFIG_${symbol}=y$" "$CONFIG"; then
        echo "error: CONFIG_${symbol}=y is missing" >&2
        grep -E "CONFIG_${symbol}(=| is not set)" "$CONFIG" || true
        exit 1
    fi
}

require_equal KSU
require_equal KSU_LSM_SECURITY_HOOKS
require_equal KSU_SUSFS
require_equal KSU_SUSFS_HAS_MAGIC_MOUNT
require_equal KSU_SUSFS_SUS_PATH
require_equal KSU_SUSFS_SUS_MOUNT
require_equal KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT
require_equal KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT
require_equal KSU_SUSFS_SUS_KSTAT
require_equal KSU_SUSFS_SUS_OVERLAYFS
require_equal KSU_SUSFS_TRY_UMOUNT
require_equal KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT
require_equal KSU_SUSFS_SPOOF_UNAME
require_equal KSU_SUSFS_ENABLE_LOG
require_equal KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
require_equal KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
require_equal KSU_SUSFS_OPEN_REDIRECT
require_equal KSU_SUSFS_SUS_MAPS
require_equal FHANDLE

if grep -q '^CONFIG_KSU_KPROBES_HOOK=y$' "$CONFIG"; then
    echo "error: CONFIG_KSU_KPROBES_HOOK must remain disabled for the MagicTime hook patch" >&2
    exit 1
fi

if [[ ! -f "$KERNEL/drivers/kernelsu/ksu.c" || ! -f "$KERNEL/drivers/kernelsu/Makefile" ]]; then
    echo "error: KernelSU-Next sources are missing" >&2
    exit 1
fi
for source in fs/susfs.c fs/sus_su.c include/linux/susfs.h include/linux/susfs_def.h; do
    if [[ ! -f "$KERNEL/$source" ]]; then
        echo "error: SUSFS asset is missing: $source" >&2
        exit 1
    fi
done
if [[ -e "$KERNEL/KernelSU" ]]; then
    echo "error: embedded MagicTime KernelSU remains" >&2
    exit 1
fi
if [[ -f "$KERNEL/.gitmodules" ]] && grep -q '^\[submodule "KernelSU"\]$' "$KERNEL/.gitmodules"; then
    echo "error: MagicTime KernelSU submodule declaration remains" >&2
    exit 1
fi

echo "KernelSU-Next + SUSFS configuration validated:"
grep -E '^CONFIG_(KSU|KSU_SUSFS|FHANDLE)' "$CONFIG"
echo "Embedded MagicTime KernelSU is absent; replacement sources are present."
