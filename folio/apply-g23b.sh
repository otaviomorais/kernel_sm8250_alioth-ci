#!/usr/bin/env bash
# E404 folio G2.3b: folio page-lock API (upstream patches 17-22, adapted).
# Additive only: the existing struct page lock path is untouched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g2.3b.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G2.3b ausente" >&2; exit 1; }

bash "$SCRIPT_DIR/apply-g23a.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G2.3b ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

P="$KERNEL_DIR/include/linux/pagemap.h"
for sym in __folio_lock __folio_lock_killable __folio_lock_or_retry \
           folio_unlock folio_trylock folio_lock folio_lock_killable \
           folio_lock_or_retry folio_wait_locked folio_wait_locked_killable; do
    grep -q "$sym" "$P" || { echo "FATAL: falta $sym em pagemap.h"; exit 1; }
done

for sym in folio_unlock __folio_lock __folio_lock_killable __folio_lock_or_retry; do
    grep -q "$sym" "$KERNEL_DIR/mm/filemap.c" || \
        { echo "FATAL: falta $sym em filemap.c"; exit 1; }
done

# caminho de struct page intacto
for sym in "__lock_page" "__lock_page_killable" "__lock_page_or_retry" "unlock_page"; do
    grep -q "$sym" "$P" || { echo "FATAL: $sym de pagina sumiu"; exit 1; }
done

! grep -q 'CONFIG_MTHP' "$KERNEL_DIR/mm/Kconfig"

echo "Folio G2.3b integrado; API de lock de folio presente, caminho de pagina intacto."
