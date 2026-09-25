#!/usr/bin/env bash
# E404 folio G2.3e: folio_wake_bit() (upstream patch 28/90).
# Upstream patch 30/90 is intentionally NOT included: the E404 tree has
# neither include/linux/netfs.h nor end_page_private_2() /
# wait_on_page_private_2(), so there is no page-level machinery to derive
# the folio variants from.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g2.3e.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G2.3e ausente" >&2; exit 1; }

bash "$SCRIPT_DIR/apply-g23d.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G2.3e ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

F="$KERNEL_DIR/mm/filemap.c"
grep -q 'static void folio_wake_bit' "$F"
[ "$(grep -c '^static void wake_up_page_bit' "$F")" = "1" ]
[ "$(grep -c '^static void folio_wake_bit' "$F")" = "1" ]

! grep -q 'CONFIG_MTHP' "$KERNEL_DIR/mm/Kconfig"

echo "Folio G2.3e integrado; wake_up_page_bit() intacto."
