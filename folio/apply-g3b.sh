#!/usr/bin/env bash
# E404 folio G3b: geometria e page_mkclean por folio (52/90, 53/90 e 59/90).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g3b.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G3b ausente" >&2; exit 1; }

bash "$SCRIPT_DIR/apply-g3a.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G3b ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

bash "$SCRIPT_DIR/verify-g3b.sh" "$KERNEL_DIR"

# A serie e aditiva: nenhum arquivo novo em mm/, nenhum wrapper em
# mm/folio-compat.c, nenhum nome de simbolo trocado.
if [ -e "$KERNEL_DIR/mm/folio-compat.c" ]; then
    echo "FATAL: mm/folio-compat.c foi criado; esta arvore nao tem esse arquivo" >&2
    exit 1
fi

# page_mkclean tem um caller in-tree, em mm/page-writeback.c, e ele tem de
# continuar compilando pelo wrapper em rmap.h.  A forma do walker do E404
# tambem e invariante: trocar rmap_walk_control por rmap_walk_walk, como o
# upstream, nao compila no 4.19.
if ! grep -q 'struct rmap_walk_control rwc = {' "$KERNEL_DIR/mm/rmap.c"; then
    echo "FATAL: a forma do rmap_walk_control do E404 foi perdida" >&2
    exit 1
fi

echo "Folio G3b integrado; folio_raw_mapping() e flush_dcache_folio() novas, folio_mkclean() nova com page_mkclean() como wrapper."
