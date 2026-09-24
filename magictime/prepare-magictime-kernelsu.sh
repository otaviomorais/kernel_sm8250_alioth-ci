#!/usr/bin/env bash
# Remove the KernelSU copy embedded in the pinned MagicTime source.
# The replacement KernelSU-Next/SUSFS is installed by kernelsu/apply.sh.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <magictime-kernel>" >&2
    exit 2
fi

KERNEL="$(cd "$1" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_REMOVAL_PATCH="$SCRIPT_DIR/patches/remove-magictime-kernelsu-hooks.patch"
EXPECTED_MAGIC_SHA="eba8dbd9d11b479cae68918826c344065a6b5d3c"
actual="$(git -C "$KERNEL" rev-parse HEAD 2>/dev/null || true)"

if [[ "$actual" != "$EXPECTED_MAGIC_SHA" ]]; then
    echo "error: expected MagicTime $EXPECTED_MAGIC_SHA, got ${actual:-<unavailable>}" >&2
    exit 1
fi

# Remove the tree-wide hooks from MagicTime's old KernelSU integration first.
# This is separate from removing the gitlink/symlink below because the hooks
# live in normal kernel source files.
[[ -f "$HOOKS_REMOVAL_PATCH" ]] || {
    echo "error: missing KernelSU hook removal patch: $HOOKS_REMOVAL_PATCH" >&2
    exit 1
}
git -C "$KERNEL" apply --check "$HOOKS_REMOVAL_PATCH"
git -C "$KERNEL" apply "$HOOKS_REMOVAL_PATCH"

# MagicTime tracks KernelSU as a gitlink and exposes it through this symlink.
# Remove both before copying the KernelSU-Next tree from this repository.
rm -rf -- "$KERNEL/KernelSU" "$KERNEL/drivers/kernelsu"

# Remove the old KSU wiring. kernelsu/apply.sh + the MagicTime-specific hook
# patch add the replacement wiring after the cleanup.
if [[ -f "$KERNEL/drivers/Kconfig" ]]; then
    sed -i -E '/^[[:space:]]*source[[:space:]]+"drivers\/kernelsu\/Kconfig"[[:space:]]*$/d' \
        "$KERNEL/drivers/Kconfig"
    sed -i ':a;N;$!ba;s/source "drivers\/energy_model\/Kconfig"\n\nendmenu/source "drivers\/energy_model\/Kconfig"\nendmenu/' \
        "$KERNEL/drivers/Kconfig"
fi
if [[ -f "$KERNEL/drivers/Makefile" ]]; then
    sed -i -E '/^[[:space:]]*obj-\$\(CONFIG_KSU\)[[:space:]]*\+=[[:space:]]*kernelsu\/[[:space:]]*$/d' \
        "$KERNEL/drivers/Makefile"
    # The old KSU line was preceded by a blank line; remove that separator so
    # the replacement KSU line has the same context as the hook patch.
    sed -i '${/^$/d;}' "$KERNEL/drivers/Makefile"
fi

# Do not leave the old submodule declaration in the checkout metadata.
if [[ -f "$KERNEL/.gitmodules" ]]; then
    sed -i '/^\[submodule "KernelSU"\]$/,/^$/d' "$KERNEL/.gitmodules"
fi

# Remove stale KSU options from every ARM64 config fragment, including the
# CRLF-formatted MagicTime vendor fragment. The replacement integration adds
# the final options to alioth_defconfig below.
if [[ -d "$KERNEL/arch/arm64/configs" ]]; then
    while IFS= read -r -d '' config; do
        sed -i -E \
            '/^[[:space:]]*#[[:space:]]*KernelSU[[:space:]]*\r?$/d; /^[[:space:]]*CONFIG_KSU(_[A-Za-z0-9_]+)?([[:space:]]*=|[[:space:]])/d' \
            "$config"
    done < <(find "$KERNEL/arch/arm64/configs" -type f -print0)
fi

if [[ -e "$KERNEL/KernelSU" || -e "$KERNEL/drivers/kernelsu" ]]; then
    echo "error: embedded KernelSU paths remain after cleanup" >&2
    exit 1
fi
if grep -R -n -E 'drivers/kernelsu/Kconfig|obj-\$\(CONFIG_KSU\)' \
    "$KERNEL/drivers/Kconfig" "$KERNEL/drivers/Makefile" 2>/dev/null; then
    echo "error: old KernelSU wiring remains after cleanup" >&2
    exit 1
fi
if grep -n -E 'CONFIG_KSU|ksu_|KernelSU|on_head|untagged_addr' \
    "$KERNEL/fs/exec.c" "$KERNEL/fs/open.c" "$KERNEL/fs/read_write.c" \
    "$KERNEL/fs/stat.c" "$KERNEL/kernel/reboot.c" \
    "$KERNEL/security/selinux/hooks.c" \
    "$KERNEL/security/selinux/include/objsec.h" 2>/dev/null; then
    echo "error: old KernelSU hooks remain after cleanup" >&2
    exit 1
fi

echo "Embedded KernelSU removed from MagicTime $EXPECTED_MAGIC_SHA."
