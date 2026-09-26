#!/usr/bin/env bash
# E404 folio G2.5d: filemap_get_folio() (upstream patch 88/90).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g2.5d.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G2.5d ausente" >&2; exit 1; }

bash "$SCRIPT_DIR/apply-g25c.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G2.5d ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

bash "$SCRIPT_DIR/verify-g25d.sh" "$KERNEL_DIR"

# pagecache_get_page precisa continuar sendo simbolo exportado: ele esta na
# lista de ABI do vendor, android/abi_gki_aarch64_qcom.  O 5.16 move a funcao
# para mm/folio-compat.c, que esta arvore nao tem, e a transformaria em
# wrapper estatico; aqui ela fica como funcao real justamente por causa disso.
if ! grep -q 'EXPORT_SYMBOL(pagecache_get_page);' "$KERNEL_DIR/mm/filemap.c"; then
    echo "FATAL: pagecache_get_page perdeu o EXPORT_SYMBOL; a ABI do vendor exige o simbolo" >&2
    exit 1
fi

echo "Folio G2.5d integrado; __filemap_get_folio() e filemap_get_folio() novos, pagecache_get_page() e mark_page_accessed() preservados como wrappers."
