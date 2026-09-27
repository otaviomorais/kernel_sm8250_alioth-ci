#!/usr/bin/env bash
# E404 folio G4 (Final): ciclo completo de dirtying, writeback, truncate, memcg e migracao
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g4.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G4 ausente" >&2; exit 1; }

bash "$SCRIPT_DIR/apply-g3d.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G4 ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

bash "$SCRIPT_DIR/verify-g4.sh" "$KERNEL_DIR"

if [ -e "$KERNEL_DIR/mm/folio-compat.c" ]; then
    echo "FATAL: mm/folio-compat.c foi criado; esta arvore nao tem esse arquivo" >&2
    exit 1
fi

echo "Folio G4 (Final) integrado: backport folio-5.16 100% concluido."
