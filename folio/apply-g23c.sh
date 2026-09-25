#!/usr/bin/env bash
# E404 folio G2.3c: folio writeback end + folio rotate-reclaimable.
# Derived from upstream folio-5.16 patches 23/90 and 24/90.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g2.3c.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G2.3c ausente" >&2; exit 1; }

bash "$SCRIPT_DIR/apply-g23b.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G2.3c ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

grep -q 'void folio_rotate_reclaimable' "$KERNEL_DIR/mm/swap.c"
grep -q 'void folio_end_writeback' "$KERNEL_DIR/mm/filemap.c"
grep -q 'static void folio_wake' "$KERNEL_DIR/mm/filemap.c"
grep -q 'folio_end_writeback' "$KERNEL_DIR/include/linux/pagemap.h"
grep -q 'folio_rotate_reclaimable' "$KERNEL_DIR/include/linux/swap.h"

# caminhos de struct page intactos
grep -q '^void rotate_reclaimable_page(struct page \*page)' "$KERNEL_DIR/mm/swap.c"
grep -q '^void end_page_writeback(struct page \*page)' "$KERNEL_DIR/mm/filemap.c"
grep -q 'rotate_reclaimable_page' "$KERNEL_DIR/include/linux/swap.h"

! grep -q 'CONFIG_MTHP' "$KERNEL_DIR/mm/Kconfig"

echo "Folio G2.3c integrado; APIs novas, caminhos de pagina intactos."
