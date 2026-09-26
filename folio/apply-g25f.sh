#!/usr/bin/env bash
# E404 folio G2.5f: folio_write_one() (upstream patch 90/90).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g2.5f.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G2.5f ausente" >&2; exit 1; }

bash "$SCRIPT_DIR/apply-g25e.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G2.5f ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

bash "$SCRIPT_DIR/verify-g25f.sh" "$KERNEL_DIR"

# A serie de folios e aditiva: nenhum arquivo novo em mm/, nenhum wrapper em
# mm/folio-compat.c, nenhum nome de simbolo trocado.
if [ -e "$KERNEL_DIR/mm/folio-compat.c" ]; then
    echo "FATAL: mm/folio-compat.c foi criado; esta arvore nao tem esse arquivo" >&2
    exit 1
fi

# write_one_page() tem nove callers in-tree, um deles o driver block2mtd, e a
# declaracao continua em include/linux/mm.h porque cinco desses callers nao
# incluem linux/pagemap.h.  Nem o simbolo nem a declaracao podem ter sumido.
if ! grep -q 'EXPORT_SYMBOL(write_one_page);' "$KERNEL_DIR/mm/page-writeback.c"; then
    echo "FATAL: write_one_page perdeu o EXPORT_SYMBOL; 9 callers in-tree dependem dele" >&2
    exit 1
fi
if ! grep -q 'int __must_check write_one_page(struct page \*page);' "$KERNEL_DIR/include/linux/mm.h"; then
    echo "FATAL: a declaracao de write_one_page saiu de mm.h; fs/jfs, fs/minix, fs/ufs, fs/exofs e fs/ocfs2 nao incluem pagemap.h" >&2
    exit 1
fi

echo "Folio G2.5f integrado; folio_write_one() e folio_clear_dirty_for_io() novos, write_one_page() e clear_page_dirty_for_io() preservados como wrappers."
