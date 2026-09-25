#!/usr/bin/env bash
# E404 folio G1: additive type/layout shim from upstream folio-5.16.
# This is intentionally opt-in and does not enable mTHP yet.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g1.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G1 ausente" >&2; exit 1; }

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G1 ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

grep -q 'struct folio' "$KERNEL_DIR/include/linux/mm_types.h"
grep -q 'page_folio' "$KERNEL_DIR/include/linux/page-flags.h"
grep -q 'folio_nr_pages' "$KERNEL_DIR/include/linux/mm.h"
! grep -q 'CONFIG_MTHP' "$KERNEL_DIR/mm/Kconfig"

echo "Folio G1 integrado; mTHP permanece deliberadamente desabilitado."
