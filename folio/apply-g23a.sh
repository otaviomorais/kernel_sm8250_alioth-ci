#!/usr/bin/env bash
# E404 folio G2.3a: page cache index/position/mapping helpers.
# Derived from upstream folio-5.16 patches 13/90..16/90, adapted additively.
# No caller is converted yet: this only adds the folio_* API surface.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g2.3a.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G2.3a ausente" >&2; exit 1; }

# G2.3a depende de G2.2b.  Os scripts anteriores sao idempotentes.
bash "$SCRIPT_DIR/apply-g22b.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G2.3a ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

P="$KERNEL_DIR/include/linux/pagemap.h"
grep -q 'folio_index' "$P"
grep -q 'folio_next_index' "$P"
grep -q 'folio_file_page' "$P"
grep -q 'folio_contains' "$P"
grep -q 'folio_file_mapping' "$P"
grep -q 'folio_pos' "$P"
grep -q 'folio_file_pos' "$P"
grep -q 'folio_swap_entry' "$KERNEL_DIR/include/linux/swap.h"
grep -q 'folio_mapping' "$KERNEL_DIR/mm/util.c"
grep -q 'swapcache_mapping' "$KERNEL_DIR/mm/swapfile.c"

# page_mapping() / page_mapping_file() / __page_file_mapping() intactos
grep -q '^struct address_space \*page_mapping(struct page \*page)' "$KERNEL_DIR/mm/util.c"
grep -q '__page_file_mapping' "$KERNEL_DIR/mm/swapfile.c"

! grep -q 'CONFIG_MTHP' "$KERNEL_DIR/mm/Kconfig"

echo "Folio G2.3a integrado; API de page cache presente, callers ainda nao convertidos."
