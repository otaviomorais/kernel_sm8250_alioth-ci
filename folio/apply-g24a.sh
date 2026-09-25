#!/usr/bin/env bash
# E404 folio G2.4a: __folio_end_writeback() (upstream patch 66/90).
#
# Moves test_clear_page_writeback() out of include/linux/page-flags.h into
# mm/internal.h, renames it to __folio_end_writeback(), takes a struct folio
# and returns bool.
#
# The writeback accounting deliberately stays in whole pages: upstream counts
# folio_nr_pages() through the wb_stat_mod() / lruvec_stat_mod_folio() family
# from the vmstat rework (upstream patches 50-56), which this tree does not
# have.  Every page here is order-0 anyway, since CONFIG_TRANSPARENT_HUGEPAGE
# is not set, so a folio is always exactly one page.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g2.4a.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G2.4a ausente" >&2; exit 1; }

bash "$SCRIPT_DIR/apply-g23f.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G2.4a ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

bash "$SCRIPT_DIR/verify-g24a.sh" "$KERNEL_DIR"

! grep -q 'CONFIG_MTHP' "$KERNEL_DIR/mm/Kconfig"

echo "Folio G2.4a integrado; end_page_writeback() e folio_end_writeback() convergem para __folio_end_writeback()."
