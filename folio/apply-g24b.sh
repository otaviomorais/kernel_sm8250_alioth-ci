#!/usr/bin/env bash
# E404 folio G2.4b: workingset_refault() por folio (upstream patch 80/90).
#
# workingset_refault() now takes a struct folio; its single caller in this
# tree, add_to_page_cache_lru(), resolves page_folio().  PG_active and
# PG_workingset are both PF_HEAD flags, so setting them through the folio
# accessors anchors the operation on the head page.
#
# MGLRU's own lru_gen_refault() is left page-based on purpose: it belongs to
# the MGLRU series, not to this conversion.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g2.4b.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G2.4b ausente" >&2; exit 1; }

bash "$SCRIPT_DIR/apply-g24a.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G2.4b ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

bash "$SCRIPT_DIR/verify-g24b.sh" "$KERNEL_DIR"

! grep -q 'CONFIG_MTHP' "$KERNEL_DIR/mm/Kconfig"

echo "Folio G2.4b integrado; workingset_refault() opera sobre o folio, caminho do MGLRU intacto."
