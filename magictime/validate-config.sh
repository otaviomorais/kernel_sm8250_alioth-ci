#!/usr/bin/env bash
# Validate the generated AOSP16 .config for the experimental EEVDF/CASS port.
set -euo pipefail

CONFIG="${1:-}"
if [[ -z "$CONFIG" || ! -f "$CONFIG" ]]; then
    echo "usage: $0 <kernel/out/.config>" >&2
    exit 2
fi

require_equal() {
    local symbol="$1"
    if ! grep -q "^CONFIG_${symbol}=y$" "$CONFIG"; then
        echo "error: CONFIG_${symbol}=y is missing" >&2
        grep -E "CONFIG_${symbol}(=| is not set)" "$CONFIG" || true
        exit 1
    fi
}

forbid_enabled() {
    local symbol="$1"
    if grep -Eq "^CONFIG_${symbol}=(y|m)$" "$CONFIG"; then
        echo "error: CONFIG_${symbol} must not be enabled" >&2
        exit 1
    fi
}

require_equal SMP
require_equal SCHED_MC
require_equal ENERGY_MODEL
require_equal CPU_FREQ
require_equal CPU_FREQ_GOV_SCHEDUTIL
require_equal SCHED_CASS
require_equal SCHED_THERMAL_PRESSURE
require_equal UCLAMP_TASK
require_equal UCLAMP_TASK_GROUP
forbid_enabled SCHED_WALT
forbid_enabled SCHED_TUNE
forbid_enabled SCHED_CORE_CTL

# cgroup bandwidth settings are intentionally not rejected. Their interaction
# with EEVDF is a separate runtime/test matrix, not silently changed here.
echo "MagicTime EEVDF/CASS configuration validated:"
grep -E '^CONFIG_(SCHED_CASS|SCHED_THERMAL_PRESSURE|UCLAMP_TASK|UCLAMP_TASK_GROUP|RT_SOFTIRQ_AWARE_SCHED|UCLAMP_ASSIST|FAIR_GROUP_SCHED|CFS_BANDWIDTH|RT_GROUP_SCHED)=' "$CONFIG" || true
echo "WALT, SCHED_TUNE and SCHED_CORE_CTL are not enabled."
