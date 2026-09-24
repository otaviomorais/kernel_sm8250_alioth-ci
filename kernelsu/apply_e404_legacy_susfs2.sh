#!/usr/bin/env bash
# Experimental only: KernelSU-Next legacy + SUSFS v2.3 bridge for E404 4.19.
# This path is intentionally separate from apply_e404.sh (the known-good v1.x path).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECTED_KSU_COMMIT="f6a1570cc7857141b8acef9b3073840f59539359"

if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
    echo "Uso: $0 <kernel> <defconfig> <ksu_repo> <susfs_repo> [enable_susfs:true|false]" >&2
    exit 1
fi

KERNEL_DIR="$(cd "$1" && pwd)"
CONFIG_FILE="$2"
KSU_REPO="$(cd "$3" && pwd)"
SUSFS_REPO="$(cd "$4" && pwd)"
ENABLE_SUSFS="${5:-true}"

case "$ENABLE_SUSFS" in
    true|false) ;;
    *) echo "FATAL: enable_susfs deve ser true ou false." >&2; exit 1 ;;
esac

[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel inválido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$CONFIG_FILE" ] || { echo "FATAL: defconfig inexistente: $CONFIG_FILE" >&2; exit 1; }
[ -f "$KSU_REPO/kernel/Kbuild" ] || { echo "FATAL: checkout do KernelSU-Next inválido: $KSU_REPO" >&2; exit 1; }
[ -f "$SUSFS_REPO/kernel_patches/fs/susfs.c" ] || { echo "FATAL: checkout do SUSFS inválido: $SUSFS_REPO" >&2; exit 1; }

printf '%s\n' '======================================================'
printf '%s\n' ' Port EXPERIMENTAL: KernelSU-Next legacy + SUSFS v2.3'
printf ' Kernel: %s\n' "$KERNEL_DIR"
printf ' KSU source: %s\n' "$KSU_REPO"
printf ' SUSFS source: %s\n' "$SUSFS_REPO"
printf ' SUSFS enabled: %s\n' "$ENABLE_SUSFS"
printf '%s\n' '======================================================'

# Pin the non-GKI source. The bridge patch was authored against the legacy
# source shape; accepting another KSU checkout here would make the build
# silently mix incompatible APIs.
if git -C "$KSU_REPO" rev-parse --verify HEAD >/dev/null 2>&1; then
    KSU_COMMIT="$(git -C "$KSU_REPO" rev-parse HEAD)"
    if [ "$KSU_COMMIT" != "$EXPECTED_KSU_COMMIT" ]; then
        echo "FATAL: KSU commit inesperado: $KSU_COMMIT" >&2
        echo "Use o commit f6a1570c... do ramo legacy não-GKI." >&2
        exit 1
    fi
    echo "KSU-Next commit fixado: $KSU_COMMIT"
else
    echo "FATAL: o checkout do KSU deve preservar .git para validar o commit." >&2
    exit 1
fi

grep -q '#define SUSFS_VERSION "v2.3.0"' "$SUSFS_REPO/kernel_patches/include/linux/susfs.h" || {
    echo "FATAL: a fonte do SUSFS não é v2.3.0." >&2
    exit 1
}

# ---------------------------------------------------------------------------
# KernelSU-Next legacy bridge
# ---------------------------------------------------------------------------
KSU_PATCH="$SCRIPT_DIR/patches/ksun-legacy-susfs-v2.3.0.patch"
KSU_KCONFIG_PATCH="$SCRIPT_DIR/patches/e404-ksu-susfs-kconfig.patch"

if ! grep -q 'menu "KernelSU - SUSFS"' "$KSU_REPO/kernel/Kconfig"; then
    set +e
    git -C "$KSU_REPO" apply --reject --whitespace=nowarn "$KSU_PATCH"
    KSU_APPLY_RC=$?
    set -e

    if [ "$KSU_APPLY_RC" -ne 0 ]; then
        mapfile -t KSU_REJECTS < <(find "$KSU_REPO" -type f -name '*.rej' -print)
        if [ "${#KSU_REJECTS[@]}" -ne 1 ] || [ "${KSU_REJECTS[0]}" != "$KSU_REPO/kernel/Kconfig.rej" ]; then
            echo "FATAL: rejeitos inesperados no patch KSU:" >&2
            printf '  %s\n' "${KSU_REJECTS[@]}" >&2
            exit 1
        fi
    fi

    # f6a1570c adds KSU_SYSCALL_TABLE_HOOK before the final endmenu, so the
    # bridge's original KSU_KPROBES context is intentionally replaced here.
    git -C "$KSU_REPO" apply --check "$KSU_KCONFIG_PATCH"
    git -C "$KSU_REPO" apply "$KSU_KCONFIG_PATCH"
    rm -f "$KSU_REPO/kernel/Kconfig.rej"
fi

if find "$KSU_REPO" -type f -name '*.rej' -print -quit | grep -q .; then
    echo "FATAL: rejeitos pendentes na integração KSU." >&2
    find "$KSU_REPO" -type f -name '*.rej' -print >&2
    exit 1
fi

grep -q 'config KSU_SUSFS' "$KSU_REPO/kernel/Kconfig" || {
    echo "FATAL: KSU_SUSFS não entrou no Kconfig." >&2
    exit 1
}
grep -q 'ksu_handle_sys_reboot' "$KSU_REPO/kernel/supercall/supercall.c" || {
    echo "FATAL: bridge SUSFS não expõe ksu_handle_sys_reboot." >&2
    exit 1
}

# Replace the upstream/Kowsu driver with the pinned KSU source.
rm -rf "$KERNEL_DIR/KernelSU" "$KERNEL_DIR/drivers/kernelsu"
cp -a "$KSU_REPO/kernel" "$KERNEL_DIR/drivers/kernelsu"
# f6a1570c keeps the UAPI headers as a sibling of kernel/ and exposes
# kernel/include/uapi as a relative symlink. Copy the real directory too;
# after relocating kernel/ into drivers/, that symlink would otherwise point
# at a nonexistent drivers/uapi path.
if [ -d "$KSU_REPO/uapi" ]; then
    rm -rf "$KERNEL_DIR/drivers/kernelsu/uapi"
    cp -a "$KSU_REPO/uapi" "$KERNEL_DIR/drivers/kernelsu/uapi"
    if [ -L "$KERNEL_DIR/drivers/kernelsu/include/uapi" ] || [ -e "$KERNEL_DIR/drivers/kernelsu/include/uapi" ]; then
        rm -rf "$KERNEL_DIR/drivers/kernelsu/include/uapi"
        cp -a "$KSU_REPO/uapi" "$KERNEL_DIR/drivers/kernelsu/include/uapi"
    fi
fi

# E404 already has these entries, but keep the experimental script self-contained.
if ! grep -q 'source "drivers/kernelsu/Kconfig"' "$KERNEL_DIR/drivers/Kconfig"; then
    printf '\nsource "drivers/kernelsu/Kconfig"\n' >> "$KERNEL_DIR/drivers/Kconfig"
fi
if ! grep -q 'obj-$(CONFIG_KSU).*kernelsu/' "$KERNEL_DIR/drivers/Makefile"; then
    printf '\nobj-$(CONFIG_KSU)\t+= kernelsu/\n' >> "$KERNEL_DIR/drivers/Makefile"
fi

# ---------------------------------------------------------------------------
# Manual KernelSU-Next hooks required by the non-GKI KSU legacy layer
# ---------------------------------------------------------------------------
MANUAL_HOOKS_PATCH="$SCRIPT_DIR/patches/e404-ksu-legacy-manual-hooks.patch"
# The manual syscall hooks are required by the legacy KSU layer even when
# SUSFS is disabled; keep them independent from the optional v2.3 block.
git -C "$KERNEL_DIR" apply --check "$MANUAL_HOOKS_PATCH"
git -C "$KERNEL_DIR" apply "$MANUAL_HOOKS_PATCH"
echo "Hooks manuais KernelSU-Next non-GKI aplicados."

# ---------------------------------------------------------------------------
# SUSFS v2.3 kernel integration
# ---------------------------------------------------------------------------
if [ "$ENABLE_SUSFS" = "true" ]; then
    SUSFS_PATCH="$SCRIPT_DIR/patches/susfs-v2.3-e404-4.19.patch"
    SUSFS_COMPAT_PATCH="$SCRIPT_DIR/patches/e404-susfs-v2.3-compat.patch"

    # The generic 4.19 patch creates these files. They must not be tracked
    # files in the upstream E404 checkout.
    for generated in fs/susfs.c include/linux/susfs.h include/linux/susfs_def.h; do
        if git -C "$KERNEL_DIR" ls-files --error-unmatch "$generated" >/dev/null 2>&1; then
            echo "FATAL: $generated já é rastreado no E404; abortando para não apagar fonte." >&2
            exit 1
        fi
        rm -f "$KERNEL_DIR/$generated"
    done

    set +e
    git -C "$KERNEL_DIR" apply --reject --whitespace=nowarn "$SUSFS_PATCH"
    SUSFS_APPLY_RC=$?
    set -e

    if [ "$SUSFS_APPLY_RC" -ne 0 ]; then
        mapfile -t SUSFS_REJECTS < <(find "$KERNEL_DIR" -type f -name '*.rej' -print)
        allowed_rejects=0
        for reject in "${SUSFS_REJECTS[@]}"; do
            case "$reject" in
                "$KERNEL_DIR/fs/stat.c.rej"|"$KERNEL_DIR/fs/proc/task_mmu.c.rej"|"$KERNEL_DIR/kernel/sys.c.rej"|"$KERNEL_DIR/mm/memory.c.rej")
                    allowed_rejects=1
                    ;;
                *)
                    echo "FATAL: rejeito SUSFS inesperado: $reject" >&2
                    exit 1
                    ;;
            esac
        done
        [ "$allowed_rejects" -eq 1 ] || {
            echo "FATAL: o patch SUSFS falhou sem rejeitos conhecidos." >&2
            exit 1
        }
    fi

    # Resolve the four E404-specific context differences (vendor proc/stat,
    # vendor uname, and mm include placement).
    git -C "$KERNEL_DIR" apply --check "$SUSFS_COMPAT_PATCH"
    git -C "$KERNEL_DIR" apply "$SUSFS_COMPAT_PATCH"
    rm -f \
        "$KERNEL_DIR/fs/stat.c.rej" \
        "$KERNEL_DIR/fs/proc/task_mmu.c.rej" \
        "$KERNEL_DIR/kernel/sys.c.rej" \
        "$KERNEL_DIR/mm/memory.c.rej"

    if find "$KERNEL_DIR" -type f -name '*.rej' -print -quit | grep -q .; then
        echo "FATAL: rejeitos pendentes após a compatibilização SUSFS." >&2
        find "$KERNEL_DIR" -type f -name '*.rej' -print >&2
        exit 1
    fi

    grep -q '#define SUSFS_VERSION "v2.3.0"' "$KERNEL_DIR/include/linux/susfs.h" || {
        echo "FATAL: include/linux/susfs.h não foi instalado." >&2
        exit 1
    }
    grep -q 'susfs_init();' "$KERNEL_DIR/drivers/kernelsu/core/init.c" || {
        echo "FATAL: susfs_init não foi ligado ao KSU." >&2
        exit 1
    }
    echo "SUSFS v2.3.0 non-GKI aplicado ao E404."
fi

# ---------------------------------------------------------------------------
# Defconfig: this experiment deliberately uses manual hooks, not kprobes.
# ---------------------------------------------------------------------------
sed -i \
    -e '/^CONFIG_KSU/d' \
    -e '/^# CONFIG_KSU/d' \
    -e '/^CONFIG_FHANDLE/d' \
    -e '/^# CONFIG_FHANDLE/d' \
    "$CONFIG_FILE"

cat >> "$CONFIG_FILE" <<'EOF'
# EXPERIMENTAL: KernelSU-Next legacy non-GKI + SUSFS v2.3
CONFIG_THREAD_INFO_IN_TASK=y
CONFIG_KSU=y
CONFIG_KSU_MANUAL_HOOK=y
# CONFIG_KSU_KPROBES_HOOK is not set
# CONFIG_KSU_SYSCALL_TABLE_HOOK is not set
CONFIG_FHANDLE=y
EOF

if [ "$ENABLE_SUSFS" = "true" ]; then
    cat >> "$CONFIG_FILE" <<'EOF'
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
# CONFIG_KSU_SUSFS_ENABLE_LOG is not set
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
EOF
fi

echo 'Config experimental KSU/SUSFS injetado no defconfig.'
echo '======================================================'
echo ' Integração experimental concluída.'
echo '======================================================'
