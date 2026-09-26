#!/usr/bin/env bash
# E404 folio G2.5e: FGP_STABLE (upstream patch 89/90).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g2.5e.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G2.5e ausente" >&2; exit 1; }

bash "$SCRIPT_DIR/apply-g25d.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G2.5e ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

bash "$SCRIPT_DIR/verify-g25e.sh" "$KERNEL_DIR"

# A serie de folios e aditiva: os wrappers de compatibilidade ficam no proprio
# codigo ou em headers que ja existiam, entao nenhum arquivo novo aparece em
# mm/ e o Makefile nao ganha entrada.
if [ -e "$KERNEL_DIR/mm/folio-compat.c" ]; then
    echo "FATAL: mm/folio-compat.c foi criado; esta arvore nao tem esse arquivo" >&2
    exit 1
fi

# grab_cache_page_write_begin() nao esta na lista de ABI do vendor, mas e um
# simbolo exportado vivo: os filesystems do vendor desta arvore (f2fs, ubifs)
# chamam ele.  O 5.16 o move para mm/folio-compat.c; aqui ele fica como funcao
# real, entao o export precisa continuar.
if ! grep -q 'EXPORT_SYMBOL(grab_cache_page_write_begin);' "$KERNEL_DIR/mm/filemap.c"; then
    echo "FATAL: grab_cache_page_write_begin perdeu o EXPORT_SYMBOL" >&2
    exit 1
fi

echo "Folio G2.5e integrado; FGP_STABLE e folio_wait_stable novos, wait_for_stable_page e grab_cache_page_write_begin preservados."
