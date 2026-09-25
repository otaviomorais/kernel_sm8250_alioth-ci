#!/usr/bin/env bash
# E404 folio G2.2b: classic LRU folio helpers + per-folio private data.
# Derived from upstream folio-5.16 patches 11/90 and 12/90.
# Additive only: no caller is converted yet, page cache/LRU/swap untouched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g2.2b.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G2.2b ausente" >&2; exit 1; }

# G2.2b depende de G2.2a.  Os scripts anteriores sao idempotentes.
bash "$SCRIPT_DIR/apply-g22.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G2.2b ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

grep -q 'folio_is_file_lru' "$KERNEL_DIR/include/linux/mm_inline.h"
grep -q 'folio_lru_list' "$KERNEL_DIR/include/linux/mm_inline.h"
grep -q 'lruvec_add_folio' "$KERNEL_DIR/include/linux/mm_inline.h"
grep -q 'lruvec_del_folio' "$KERNEL_DIR/include/linux/mm_inline.h"
grep -q '__folio_clear_lru_flags' "$KERNEL_DIR/include/linux/mm_inline.h"
grep -q 'folio_get_private' "$KERNEL_DIR/include/linux/mm.h"
grep -q 'folio_attach_private' "$KERNEL_DIR/include/linux/pagemap.h"
grep -q 'folio_detach_private' "$KERNEL_DIR/include/linux/pagemap.h"
grep -q 'attach_page_private' "$KERNEL_DIR/include/linux/pagemap.h"
! grep -q 'CONFIG_MTHP' "$KERNEL_DIR/mm/Kconfig"

echo "Folio G2.2b integrado; LRU classic e private data sem conversao de callers."
