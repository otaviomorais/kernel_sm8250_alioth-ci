#!/usr/bin/env bash
# E404 folio G2.3d: folio_wait_bit()/folio_wait_bit_killable().
# Derived from upstream folio-5.16 patch 27/90, but translating the E404
# wait_on_page_bit_common() shape rather than the upstream 5.16 algorithm.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g2.3d.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G2.3d ausente" >&2; exit 1; }

bash "$SCRIPT_DIR/apply-g23c.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G2.3d ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

F="$KERNEL_DIR/mm/filemap.c"
grep -q 'static inline __sched int folio_wait_bit_common' "$F"
grep -q 'void __sched folio_wait_bit' "$F"
grep -q 'int __sched folio_wait_bit_killable' "$F"
grep -q 'folio_wait_bit' "$KERNEL_DIR/include/linux/pagemap.h"

# caminho de struct page intacto
grep -q 'static inline __sched int wait_on_page_bit_common' "$F"
grep -q 'void __sched wait_on_page_bit' "$F"
grep -q 'int __sched wait_on_page_bit_killable' "$F"

! grep -q 'CONFIG_MTHP' "$KERNEL_DIR/mm/Kconfig"

echo "Folio G2.3d integrado; wait_on_page_bit() intacto."
