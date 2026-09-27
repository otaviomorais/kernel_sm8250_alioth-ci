#!/usr/bin/env bash
# E404 folio G3c: mapeamento, nid, idle e ativacao por folio (upstream 32/90, 33/90, 56/90 e 57/90).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g3c.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G3c ausente" >&2; exit 1; }

bash "$SCRIPT_DIR/apply-g3b.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G3c ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

bash "$SCRIPT_DIR/verify-g3c.sh" "$KERNEL_DIR"

if [ -e "$KERNEL_DIR/mm/folio-compat.c" ]; then
    echo "FATAL: mm/folio-compat.c foi criado; esta arvore nao tem esse arquivo" >&2
    exit 1
fi

echo "Folio G3c integrado: folio_mapped(), folio_nid(), folio_test_young/idle e folio_activate() novos com wrappers transparentes para page."
