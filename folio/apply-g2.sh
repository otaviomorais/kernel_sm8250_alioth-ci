#!/usr/bin/env bash
# E404 folio G2.1: upstream folio refcount/get/put/RCU helpers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g2.1.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G2.1 ausente" >&2; exit 1; }

# G2.1 depende do G1.  O script G1 e idempotente.
bash "$SCRIPT_DIR/apply-g1.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G2.1 ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

grep -q 'folio_ref_count' "$KERNEL_DIR/include/linux/page_ref.h"
grep -q 'folio_get' "$KERNEL_DIR/include/linux/mm.h"
grep -q 'folio_put' "$KERNEL_DIR/include/linux/mm.h"
! grep -q 'CONFIG_MTHP' "$KERNEL_DIR/mm/Kconfig"

echo "Folio G2.1 integrado; page cache, flags e mTHP continuam fora deste estagio."
