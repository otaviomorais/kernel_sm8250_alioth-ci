#!/usr/bin/env bash
# E404 folio G3a: folio_pfn() e wb_stat_mod() (upstream 51/90 e 63/90).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g3a.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G3a ausente" >&2; exit 1; }

bash "$SCRIPT_DIR/apply-g25f.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G3a ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

bash "$SCRIPT_DIR/verify-g3a.sh" "$KERNEL_DIR"

# A serie e aditiva: nenhum arquivo novo em mm/, nenhum wrapper em
# mm/folio-compat.c, nenhum nome de simbolo trocado.
if [ -e "$KERNEL_DIR/mm/folio-compat.c" ]; then
    echo "FATAL: mm/folio-compat.c foi criado; esta arvore nao tem esse arquivo" >&2
    exit 1
fi

echo "Folio G3a integrado; folio_pfn() nova e __add_wb_stat() renomeada para wb_stat_mod()."
