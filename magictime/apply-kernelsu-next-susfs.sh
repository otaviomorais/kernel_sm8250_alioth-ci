#!/usr/bin/env bash
# Integrate the pinned MagicTime tree with KernelSU-Next and SUSFS.
#
# This script deliberately does not use git apply -3: a three-way merge could
# silently accept a hook in the wrong VFS path.  The hook patch must either
# apply cleanly or be already present.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECTED_MAGICTIME="eba8dbd9d11b479cae68918826c344065a6b5d3c"

if [[ $# -lt 1 || $# -gt 5 ]]; then
    echo "Uso: $0 <kernel-dir> [kernelsu-assets-dir] [enable_susfs:true|false] [defconfig] [hook-patch]" >&2
    exit 2
fi

KERNEL_DIR="$(cd "$1" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSET_DIR="$(cd "${2:-$REPO_DIR/kernelsu}" && pwd)"
ENABLE_SUSFS="${3:-true}"
CONFIG_FILE="${4:-$KERNEL_DIR/arch/arm64/configs/alioth_defconfig}"
if [[ ! -f "$CONFIG_FILE" && -f "$KERNEL_DIR/$CONFIG_FILE" ]]; then
    CONFIG_FILE="$KERNEL_DIR/$CONFIG_FILE"
fi
HOOK_PATCH="${5:-$SCRIPT_DIR/patches/ksu-susfs-magictime.patch}"
if [[ ! -f "$HOOK_PATCH" && -f "$SCRIPT_DIR/$HOOK_PATCH" ]]; then
    HOOK_PATCH="$SCRIPT_DIR/$HOOK_PATCH"
fi

case "$ENABLE_SUSFS" in
    true|false) ;;
    *) echo "enable_susfs deve ser true ou false" >&2; exit 2 ;;
esac

[[ -f "$ASSET_DIR/drivers/kernelsu/Kconfig" ]] || {
    echo "assets incompletos: $ASSET_DIR/drivers/kernelsu" >&2
    exit 1
}
[[ -f "$ASSET_DIR/fs/susfs.c" ]] || {
    echo "assets incompletos: $ASSET_DIR/fs/susfs.c" >&2
    exit 1
}
[[ -f "$HOOK_PATCH" ]] || {
    echo "patch de hooks não encontrado: $HOOK_PATCH" >&2
    exit 1
}
[[ -f "$CONFIG_FILE" ]] || {
    echo "defconfig não encontrado: $CONFIG_FILE" >&2
    exit 1
}

if ! git -C "$KERNEL_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "kernel-dir não é um worktree git: $KERNEL_DIR" >&2
    exit 1
fi
ACTUAL_SHA="$(git -C "$KERNEL_DIR" rev-parse HEAD)"
if [[ "$ACTUAL_SHA" != "$EXPECTED_MAGICTIME" && "${ALLOW_OTHER_MAGICTIME:-0}" != 1 ]]; then
    echo "SHA inesperado: $ACTUAL_SHA (esperado $EXPECTED_MAGICTIME)" >&2
    echo "Use ALLOW_OTHER_MAGICTIME=1 somente para uma revisão explícita." >&2
    exit 1
fi

# Preflight the hook patch before changing the checkout.  This prevents a
# conflict from leaving a half-removed embedded KernelSU behind.
if git -C "$KERNEL_DIR" apply --check "$HOOK_PATCH" >/dev/null 2>&1; then
    PATCH_ACTION=apply
elif git -C "$KERNEL_DIR" apply --reverse --check "$HOOK_PATCH" >/dev/null 2>&1; then
    PATCH_ACTION=already-applied
else
    git -C "$KERNEL_DIR" apply --check "$HOOK_PATCH" || true
    echo "patch de hooks não aplica limpo; nenhum merge automático foi tentado" >&2
    exit 1
fi

# Remove the old gitlink/symlink integration before copying KernelSU-Next.
# rm -rf on a symlink removes the link itself and does not follow it.
if [[ -f "$KERNEL_DIR/.gitmodules" ]]; then
    sed -i '/^\[submodule "KernelSU"\]$/,/^$/d' "$KERNEL_DIR/.gitmodules"
    if ! grep -q '^\[submodule ' "$KERNEL_DIR/.gitmodules"; then
        rm -f "$KERNEL_DIR/.gitmodules"
    fi
fi
rm -rf "$KERNEL_DIR/KernelSU"
COMMON_CONFIG="$KERNEL_DIR/arch/arm64/configs/vendor/xiaomi/magictime-common.config"
if [[ -f "$COMMON_CONFIG" ]]; then
    # The native MagicTime fragment used to enable the gitlink copy.  The
    # replacement options are written to the selected defconfig below.
    sed -i -E '/^[[:space:]]*#[[:space:]]*KernelSU[[:space:]]*\r?$/d; /^[[:space:]]*CONFIG_KSU([A-Z0-9_]+)?[[:space:]]*=/d' \
        "$COMMON_CONFIG"
fi
if [[ -L "$KERNEL_DIR/drivers/kernelsu" ]]; then
    rm -f "$KERNEL_DIR/drivers/kernelsu"
else
    rm -rf "$KERNEL_DIR/drivers/kernelsu"
fi

# Remove the old registration lines, then register the copied tree.  Keeping
# this explicit makes the transition from the MagicTime gitlink reproducible.
sed -i '/^[[:space:]]*obj-\$(CONFIG_KSU)[[:space:]]*+=[[:space:]]*kernelsu\/[[:space:]]*$/d' \
    "$KERNEL_DIR/drivers/Makefile"
sed -i '/^[[:space:]]*source[[:space:]]*"drivers\/kernelsu\/Kconfig"[[:space:]]*$/d' \
    "$KERNEL_DIR/drivers/Kconfig"
printf 'obj-$(CONFIG_KSU) += kernelsu/\n' >> "$KERNEL_DIR/drivers/Makefile"
sed -i '/^endmenu[[:space:]]*$/i source "drivers/kernelsu/Kconfig"' \
    "$KERNEL_DIR/drivers/Kconfig"

cp -a "$ASSET_DIR/drivers/kernelsu" "$KERNEL_DIR/drivers/kernelsu"

if [[ "$ENABLE_SUSFS" == true ]]; then
    cp -f "$ASSET_DIR/fs/susfs.c" "$KERNEL_DIR/fs/susfs.c"
    cp -f "$ASSET_DIR/fs/sus_su.c" "$KERNEL_DIR/fs/sus_su.c"
    cp -f "$ASSET_DIR/include/linux/susfs.h" "$KERNEL_DIR/include/linux/susfs.h"
    cp -f "$ASSET_DIR/include/linux/susfs_def.h" "$KERNEL_DIR/include/linux/susfs_def.h"
else
    rm -f "$KERNEL_DIR/fs/susfs.c" "$KERNEL_DIR/fs/sus_su.c" \
        "$KERNEL_DIR/include/linux/susfs.h" "$KERNEL_DIR/include/linux/susfs_def.h"
fi

# Apply the adapted hook patch, or accept an already-applied patch on a rerun.
if [[ "$PATCH_ACTION" == apply ]]; then
    git -C "$KERNEL_DIR" apply "$HOOK_PATCH"
else
    echo "hooks já aplicados; nada a fazer" >&2
fi

# Replace stale KSU/SUSFS lines in the selected defconfig.  This is idempotent
# and also handles a defconfig that was previously processed by origin/main's
# apply.sh.
sed -i -E '/^# KernelSU-Next integration \(MagicTime\)$/d; /^(CONFIG_KSU([A-Z0-9_]+)?=|CONFIG_FHANDLE=|# CONFIG_KSU([A-Z0-9_]+)? is not set)/d' \
    "$CONFIG_FILE"
{
    echo '# KernelSU-Next integration (MagicTime)'
    echo 'CONFIG_KSU=y'
    echo 'CONFIG_KSU_LSM_SECURITY_HOOKS=y'
    echo '# CONFIG_KSU_KPROBES_HOOK is not set'
    if [[ "$ENABLE_SUSFS" == true ]]; then
        echo 'CONFIG_KSU_SUSFS=y'
        echo 'CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y'
        echo 'CONFIG_KSU_SUSFS_SUS_PATH=y'
        echo 'CONFIG_KSU_SUSFS_SUS_MOUNT=y'
        echo 'CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y'
        echo 'CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y'
        echo 'CONFIG_KSU_SUSFS_SUS_KSTAT=y'
        echo 'CONFIG_KSU_SUSFS_SUS_OVERLAYFS=y'
        echo 'CONFIG_KSU_SUSFS_TRY_UMOUNT=y'
        echo 'CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y'
        echo 'CONFIG_KSU_SUSFS_SPOOF_UNAME=y'
        echo 'CONFIG_KSU_SUSFS_ENABLE_LOG=y'
        echo 'CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y'
        echo 'CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y'
        echo 'CONFIG_KSU_SUSFS_OPEN_REDIRECT=y'
        # Kept for parity with origin/main.  The v1.5.5 source has the
        # SUS_KSTAT map spoof hook, but no separate map-filter data structure.
        echo 'CONFIG_KSU_SUSFS_SUS_MAPS=y'
    fi
    echo 'CONFIG_FHANDLE=y'
} >> "$CONFIG_FILE"

if [[ "$ENABLE_SUSFS" == true ]]; then
    echo "MagicTime + KernelSU-Next + SUSFS integracao preparada em $KERNEL_DIR"
else
    echo "MagicTime + KernelSU-Next integracao preparada em $KERNEL_DIR"
fi
