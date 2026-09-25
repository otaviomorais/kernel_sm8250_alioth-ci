#!/usr/bin/env bash
# Backport completo do MGLRU (Multi-Gen LRU) do AOSPA para o E404 4.19.404R.
# A patch e' aplicada antes das integrations KSU/SUSFS e DroidSpaces para
# manter os contextos dessas integrations baseados no E404 original.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
CONFIG_FILE="${2:-}"

if [ -z "$KERNEL_DIR" ] || [ -z "$CONFIG_FILE" ]; then
    echo "Uso: $0 <kernel> <defconfig>" >&2
    exit 1
fi

KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
PATCH="$SCRIPT_DIR/e404-mglru-complete.patch"

[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$CONFIG_FILE" ] || { echo "FATAL: defconfig inexistente: $CONFIG_FILE" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch MGLRU ausente: $PATCH" >&2; exit 1; }

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "MGLRU ja integrado; preservando a integracao existente."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

if find "$KERNEL_DIR" -type f -name '*.rej' -print -quit | grep -q .; then
    echo "FATAL: rejeitos pendentes apos MGLRU." >&2
    find "$KERNEL_DIR" -type f -name '*.rej' -print >&2
    exit 1
fi

# O perfil MGLRU e opt-in: o baseline UAPI2/DroidSpaces existente permanece
# intacto quando este script nao e chamado.
sed -i \
    -e '/^CONFIG_LRU_GEN=/d' \
    -e '/^# CONFIG_LRU_GEN/d' \
    "$CONFIG_FILE"
cat >> "$CONFIG_FILE" <<'EOF'
# MGLRU AOSPA -> E404 4.19.404R (backport opt-in)
CONFIG_LRU_GEN=y
CONFIG_LRU_GEN_ENABLED=y
EOF

grep -q '^CONFIG_LRU_GEN=y' "$CONFIG_FILE"
grep -q '^CONFIG_LRU_GEN_ENABLED=y' "$CONFIG_FILE"
grep -q 'config LRU_GEN' "$KERNEL_DIR/mm/Kconfig"
grep -q 'lru_gen_init_lruvec' "$KERNEL_DIR/mm/vmscan.c"
grep -q 'walk_page_range_with_walk' "$KERNEL_DIR/mm/pagewalk.c"

echo "MGLRU completo integrado no E404; Xarray e pagewalk 4.19 preservados."
