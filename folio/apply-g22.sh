#!/usr/bin/env bash
# E404 folio G2.2a: upstream folio flag manipulation, re-derived for E404.
# Header-only: include/linux/page-flags.h.  No page cache, LRU or mTHP.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g2.2a.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G2.2a ausente" >&2; exit 1; }

# G2.2a depende do G2.1.  Os scripts anteriores sao idempotentes.
bash "$SCRIPT_DIR/apply-g2.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G2.2a ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

F="$KERNEL_DIR/include/linux/page-flags.h"
grep -q 'PG_readahead = PG_reclaim' "$F"
grep -q 'static inline unsigned long \*folio_flags' "$F"
grep -q 'folio_test_swapcache' "$F"
grep -q 'folio_test_uptodate' "$F"
grep -q 'folio_test_double_map' "$F"
grep -q 'folio_has_private' "$F"
! grep -q 'CONFIG_MTHP' "$KERNEL_DIR/mm/Kconfig"

echo "Folio G2.2a integrado; apenas page-flags.h foi alterado."
