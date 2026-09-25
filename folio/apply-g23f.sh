#!/usr/bin/env bash
# E404 folio G2.3f: Convert page wait queues to be folios (upstream patch 29/90).
#
# This is the first stage that changes an existing type rather than adding a
# parallel one: struct wait_page_key / struct wait_page_queue now hold a
# struct folio, and page_waitqueue() becomes folio_waitqueue().
#
# fs/cachefiles/rdwr.c is deliberately NOT converted, unlike upstream: the E404
# copy uses the generic wait_bit API and reads key->flags plus wait->private,
# never a page pointer out of the key.  add_page_wait_queue() is kept as a
# wrapper over folio_add_wait_queue() so that file still builds for anyone who
# enables CONFIG_CACHEFILES.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g2.3f.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G2.3f ausente" >&2; exit 1; }

bash "$SCRIPT_DIR/apply-g23e.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G2.3f ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

bash "$SCRIPT_DIR/verify-g23f.sh" "$KERNEL_DIR"

! grep -q 'CONFIG_MTHP' "$KERNEL_DIR/mm/Kconfig"

echo "Folio G2.3f integrado; wait_page_key/wait_page_queue em folios, add_page_wait_queue preservado."
