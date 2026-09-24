#!/usr/bin/env bash
# Apply the adapted EEVDF/CASS scheduler series to an exact AOSP16 checkout.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <aosp16-kernel>" >&2
    exit 2
fi

KERNEL="$(cd "$1" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECTED_AOSP16_SHA="10f8a106de65d4fb5cd9c2f2fe2714f11d97bcd5"
actual="$(git -C "$KERNEL" rev-parse HEAD 2>/dev/null || true)"

if [[ "$actual" != "$EXPECTED_AOSP16_SHA" ]]; then
    echo "error: expected AOSP16 $EXPECTED_AOSP16_SHA, got ${actual:-<unavailable>}" >&2
    exit 1
fi

patches=(
    "$SCRIPT_DIR/patches/0001-walt-eevdf-cass-core.patch"
    "$SCRIPT_DIR/patches/0002-aosp-abi-thermal-platform.patch"
    "$SCRIPT_DIR/patches/0003-aosp16-core-api-bridge.patch"
    "$SCRIPT_DIR/patches/0004-aosp16-aux-api-bridge.patch"
    "$SCRIPT_DIR/patches/0005-aosp16-rbtree-waitqueue-bridge.patch"
    "$SCRIPT_DIR/patches/0006-aosp16-rbtree-erase-bridge.patch"
    "$SCRIPT_DIR/patches/0007-aosp16-topology-irqwork-bridge.patch"
    "$SCRIPT_DIR/patches/0008-aosp16-psi-membarrier-bridge.patch"
    "$SCRIPT_DIR/patches/0009-aosp16-psi-memstall-flag.patch"
    "$SCRIPT_DIR/patches/0010-aosp16-task-abi-bridge.patch"
    "$SCRIPT_DIR/patches/0011-aosp16-scheduler-annotation-bridge.patch"
    "$SCRIPT_DIR/patches/0012-aosp16-cgroup-rbtree-proc-bridge.patch"
    "$SCRIPT_DIR/patches/0013-aosp16-rtree-prio-bridge.patch"
    "$SCRIPT_DIR/patches/0014-aosp16-rcu-vmalloc-bridge.patch"
    "$SCRIPT_DIR/patches/0015-aosp16-nhz-load-bridge.patch"
    "$SCRIPT_DIR/patches/0016-aosp16-rt-walt-sysfs-bridge.patch"
    "$SCRIPT_DIR/patches/0017-aosp16-runtime-walt-bridge.patch"
    "$SCRIPT_DIR/patches/0018-aosp16-sysctl-bridge.patch"
    "$SCRIPT_DIR/patches/0019-aosp16-irq-work-smp-bridge.patch"
    "$SCRIPT_DIR/patches/0020-aosp16-smp-topology-bridge.patch"
    "$SCRIPT_DIR/patches/0021-aosp16-cpufreq-bridge.patch"
    "$SCRIPT_DIR/patches/0022-aosp16-cpufreq-gov-attr-bridge.patch"
    "$SCRIPT_DIR/patches/0023-aosp16-qcom-em-bridge.patch"
)

for patch in "${patches[@]}"; do
    [[ -f "$patch" ]] || { echo "error: missing patch: $patch" >&2; exit 1; }
    echo "checking $(basename "$patch")"
    git -C "$KERNEL" apply --check "$patch"
    git -C "$KERNEL" apply --index "$patch"
    echo "applied $(basename "$patch")"
done

if ! git -C "$KERNEL" diff --check; then
    echo "warning: inherited scheduler whitespace warnings detected" >&2
fi

[[ -f "$KERNEL/kernel/sched/cass.c" ]] || {
    echo "error: CASS source is missing after patch application" >&2
    exit 1
}
[[ ! -e "$KERNEL/kernel/sched/walt.c" && ! -e "$KERNEL/kernel/sched/walt.h" ]] || {
    echo "error: stale WALT source exists after patch application" >&2
    exit 1
}

echo "Adapted MagicTime EEVDF/CASS scheduler series applied to AOSP16."
