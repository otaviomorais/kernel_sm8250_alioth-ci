#!/usr/bin/env bash
# verify-g4.sh - Verificacao estrita do estagio G4 (Final) de folios no E404
#
# Uso:
#   bash folio/verify-g4.sh [caminho-do-kernel]

set -euo pipefail

KDIR="${1:-.}"

if [ ! -d "$KDIR/mm" ] || [ ! -d "$KDIR/include/linux" ]; then
    echo "ERRO: '$KDIR' nao parece ser a raiz do kernel." >&2
    exit 1
fi

echo "Validando o G4 (Final)..."

# 1. __folio_start_writeback e wrappers em page-flags.h e mm/page-writeback.c
grep -q 'bool __folio_start_writeback(struct folio \*folio, bool keep_write);' "$KDIR/include/linux/page-flags.h"
echo "  ok   __folio_start_writeback declarado em page-flags.h"

grep -q '#define folio_start_writeback(folio)' "$KDIR/include/linux/page-flags.h"
echo "  ok   macro folio_start_writeback definido"

grep -q 'bool __folio_start_writeback(struct folio \*folio, bool keep_write)' "$KDIR/mm/page-writeback.c"
echo "  ok   corpo de __folio_start_writeback em mm/page-writeback.c"

grep -q 'EXPORT_SYMBOL(__folio_start_writeback);' "$KDIR/mm/page-writeback.c"
echo "  ok   __folio_start_writeback exportado"

grep -q 'EXPORT_SYMBOL(set_page_writeback);' "$KDIR/mm/page-writeback.c"
echo "  ok   set_page_writeback exportado"

grep -q 'EXPORT_SYMBOL(__test_set_page_writeback);' "$KDIR/mm/page-writeback.c"
echo "  ok   __test_set_page_writeback exportado"

# 2. folio_mark_dirty e dirtying helpers
grep -q 'bool folio_mark_dirty(struct folio \*folio);' "$KDIR/include/linux/mm.h"
echo "  ok   folio_mark_dirty declarado em mm.h"

grep -q 'bool folio_mark_dirty(struct folio \*folio)' "$KDIR/mm/page-writeback.c"
echo "  ok   corpo de folio_mark_dirty em mm/page-writeback.c"

grep -q 'EXPORT_SYMBOL(folio_mark_dirty);' "$KDIR/mm/page-writeback.c"
echo "  ok   folio_mark_dirty exportado"

grep -q 'EXPORT_SYMBOL(set_page_dirty);' "$KDIR/mm/page-writeback.c"
echo "  ok   set_page_dirty exportado"

grep -q 'bool filemap_dirty_folio(struct address_space \*mapping, struct folio \*folio);' "$KDIR/include/linux/writeback.h"
echo "  ok   filemap_dirty_folio declarado em writeback.h"

grep -q 'bool filemap_dirty_folio(struct address_space \*mapping, struct folio \*folio)' "$KDIR/mm/page-writeback.c"
echo "  ok   corpo de filemap_dirty_folio em mm/page-writeback.c"

grep -q 'EXPORT_SYMBOL(filemap_dirty_folio);' "$KDIR/mm/page-writeback.c"
echo "  ok   filemap_dirty_folio exportado"

grep -q 'EXPORT_SYMBOL(__set_page_dirty_nobuffers);' "$KDIR/mm/page-writeback.c"
echo "  ok   __set_page_dirty_nobuffers exportado"

# 3. Cleaned e Cancel dirty
grep -q 'void folio_account_cleaned(struct folio \*folio, struct address_space \*mapping,' "$KDIR/include/linux/mm.h"
echo "  ok   folio_account_cleaned declarado em mm.h"

grep -q 'void __folio_cancel_dirty(struct folio \*folio);' "$KDIR/include/linux/mm.h"
echo "  ok   __folio_cancel_dirty declarado em mm.h"

grep -q 'static inline void folio_cancel_dirty(struct folio \*folio)' "$KDIR/include/linux/mm.h"
echo "  ok   folio_cancel_dirty static inline em mm.h"

grep -q 'EXPORT_SYMBOL(__folio_cancel_dirty);' "$KDIR/mm/page-writeback.c"
echo "  ok   __folio_cancel_dirty exportado"

grep -q 'EXPORT_SYMBOL(__cancel_dirty_page);' "$KDIR/mm/page-writeback.c"
echo "  ok   __cancel_dirty_page exportado"

grep -q 'void folio_account_redirty(struct folio \*folio);' "$KDIR/include/linux/writeback.h"
echo "  ok   folio_account_redirty declarado em writeback.h"

grep -q 'void account_page_redirty(struct page \*page);' "$KDIR/include/linux/writeback.h"
echo "  ok   account_page_redirty declarado em writeback.h"

grep -q 'bool folio_redirty_for_writepage(struct writeback_control \*wbc, struct folio \*folio);' "$KDIR/include/linux/writeback.h"
echo "  ok   folio_redirty_for_writepage declarado em writeback.h"

grep -q 'int redirty_page_for_writepage(struct writeback_control \*wbc, struct page \*page);' "$KDIR/include/linux/writeback.h"
echo "  ok   redirty_page_for_writepage int compativel com mm.h"

grep -q 'EXPORT_SYMBOL(folio_account_redirty);' "$KDIR/mm/page-writeback.c"
echo "  ok   folio_account_redirty exportado"

grep -q 'EXPORT_SYMBOL(folio_redirty_for_writepage);' "$KDIR/mm/page-writeback.c"
echo "  ok   folio_redirty_for_writepage exportado"

# 5. Truncate e blocks per folio em pagemap.h
grep -q 'static inline ssize_t folio_mkwrite_check_truncate(struct folio \*folio,' "$KDIR/include/linux/pagemap.h"
echo "  ok   folio_mkwrite_check_truncate static inline em pagemap.h"

grep -q 'static inline int page_mkwrite_check_truncate(struct page \*page,' "$KDIR/include/linux/pagemap.h"
echo "  ok   page_mkwrite_check_truncate wrapper em pagemap.h"

grep -q 'unsigned int i_blocks_per_folio(struct inode \*inode, struct folio \*folio)' "$KDIR/include/linux/pagemap.h"
echo "  ok   i_blocks_per_folio static inline em pagemap.h"

grep -q 'unsigned int i_blocks_per_page(struct inode \*inode, struct page \*page)' "$KDIR/include/linux/pagemap.h"
echo "  ok   i_blocks_per_page wrapper em pagemap.h"

# 6. Memcg e lruvec helpers
grep -q 'static inline struct mem_cgroup \*folio_memcg(struct folio \*folio)' "$KDIR/include/linux/memcontrol.h"
echo "  ok   folio_memcg static inline em memcontrol.h"

grep -q 'static inline struct lruvec \*folio_lruvec(struct folio \*folio, struct pglist_data \*pgdat)' "$KDIR/include/linux/memcontrol.h"
echo "  ok   folio_lruvec static inline em memcontrol.h"

# 7. Migrate helpers
grep -q 'int folio_migrate_mapping(struct address_space \*mapping,' "$KDIR/include/linux/migrate.h"
echo "  ok   folio_migrate_mapping declarado em migrate.h"

grep -q 'void folio_migrate_flags(struct folio \*newfolio, struct folio \*folio);' "$KDIR/include/linux/migrate.h"
echo "  ok   folio_migrate_flags declarado em migrate.h"

grep -q 'void folio_migrate_copy(struct folio \*newfolio, struct folio \*folio);' "$KDIR/include/linux/migrate.h"
echo "  ok   folio_migrate_copy declarado em migrate.h"

grep -q 'EXPORT_SYMBOL(folio_migrate_mapping);' "$KDIR/mm/migrate.c"
echo "  ok   folio_migrate_mapping exportado em mm/migrate.c"

grep -q 'EXPORT_SYMBOL(folio_migrate_flags);' "$KDIR/mm/migrate.c"
echo "  ok   folio_migrate_flags exportado em mm/migrate.c"

grep -q 'EXPORT_SYMBOL(folio_migrate_copy);' "$KDIR/mm/migrate.c"
echo "  ok   folio_migrate_copy exportado em mm/migrate.c"

# 8. Invariante: mm/folio-compat.c nao deve existir
if [ -e "$KDIR/mm/folio-compat.c" ]; then
    echo "ERRO: mm/folio-compat.c foi criado!" >&2
    exit 1
fi
echo "  ok   mm/folio-compat.c nao foi criado"

# 9. Invariantes de estagios anteriores
grep -q 'folio_evictable' "$KDIR/include/linux/swap.h"
echo "  ok   folio_evictable do G3d segue em swap.h"

grep -q '__folio_lru_add_fn' "$KDIR/mm/swap.c"
echo "  ok   __folio_lru_add_fn do G3d segue em mm/swap.c"

grep -q 'folio_pgoff' "$KDIR/include/linux/pagemap.h"
echo "  ok   folio_pgoff do G3d segue em pagemap.h"

grep -q 'folio_estimated_sharers' "$KDIR/include/linux/mm.h"
echo "  ok   folio_estimated_sharers do G3d segue em mm.h"

echo "G4 (Final): todas as verificacoes passaram."
