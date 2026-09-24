#!/usr/bin/env bash
# Install the repository's KernelSU-Next + SUSFS integration into the pinned
# MagicTime source after removing MagicTime's embedded KernelSU.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <magictime-kernel>" >&2
    exit 2
fi

KERNEL="$(cd "$1" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_PATCH="$SCRIPT_DIR/patches/ksu-susfs-magictime.patch"
DEFCONFIG="$KERNEL/arch/arm64/configs/alioth_defconfig"

[[ -f "$HOOKS_PATCH" ]] || {
    echo "error: missing MagicTime SUSFS hook patch: $HOOKS_PATCH" >&2
    exit 1
}
[[ -f "$DEFCONFIG" ]] || {
    echo "error: missing defconfig: $DEFCONFIG" >&2
    exit 1
}

bash "$SCRIPT_DIR/prepare-magictime-kernelsu.sh" "$KERNEL"
bash "$REPO_DIR/kernelsu/apply.sh" \
    "$KERNEL" true "$DEFCONFIG" "$HOOKS_PATCH"

echo "KernelSU-Next + SUSFS installed into MagicTime."
