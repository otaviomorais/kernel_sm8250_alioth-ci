#!/usr/bin/env bash
# Verificacao do G2.5b (patches 83/90 + 86/90: folio_add_lru e
# filemap_add_folio).  Rodada separadamente do apply para que o log do CI
# aponte a assercao exata.
#
# O `|| true` em n()/nc() e obrigatorio: com `set -o pipefail`, um grep sem
# casamento faz o pipeline inteiro devolver 1 e o script morre ali em vez de
# comparar a contagem com 0.
set -euo pipefail

KERNEL_DIR="${1:-}"
[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"

FL="$KERNEL_DIR/mm/filemap.c"
SW="$KERNEL_DIR/mm/swap.c"
PM="$KERNEL_DIR/include/linux/pagemap.h"
SH="$KERNEL_DIR/include/linux/swap.h"

for f in "$FL" "$SW" "$PM" "$SH"; do
    [ -f "$f" ] || { echo "FATAL: $f ausente" >&2; exit 1; }
done

# n() conta linhas que casam, como grep -c.
n() { grep -c "$1" "$2" || true; }
# nc() e o mesmo, ignorando linhas de comentario de bloco (" * ...").
nc() { grep -v '^[[:space:]]*\*' "$2" | grep -c "$1" || true; }
# ncd() = "nao comentario", para as contagens que precisam valer.
#
# nc() so descarta a linha de CONTINUACAO de um comentario de bloco.  A linha
# que abre e fecha o comentario na mesma linha passa direto por ela, porque
# comeca com '/' e nao com '*'.  Comentar um EXPORT_SYMBOL com /* ... */ na
# propria linha fazia nc() continuar contando a linha, e a asercao passava
# numa arvore que ja nao tinha o simbolo.  ncd() descarta tambem qualquer linha
# que contenha /* ou */.
ncd() { grep -v -e '^[[:space:]]*\*' -e '/\*' -e '\*/' "$2" | grep -c "$1" || true; }

# fn() extrai o corpo de uma funcao, ate a chave de abertura no nivel 0.
fn() { awk -v sig="$2" 'index($0, sig) { inb=1 } inb { print } inb && /^[}]$/ { exit }' "$1"; }
ok() { if eval "$2"; then echo "  ok   $1"; else echo "  FALHA $1 -> $3" >&2; exit 1; fi; }

echo "Validando o G2.5b..."

# --- patch 83: folio_add_lru -----------------------------------------
ok "folio_add_lru definido em mm/swap.c" \
   "grep -q '^void folio_add_lru(struct folio \*folio)$' \"\$SW\"" "esperava 1 definicao"
ok "folio_add_lru exportado" \
   "[ \"\$(ncd 'EXPORT_SYMBOL(folio_add_lru);' \"\$SW\")\" = 1 ]" "sem EXPORT_SYMBOL"
ok "folio_add_lru usa o corpo do MGLRU" \
   "grep -q '__lru_cache_add(&folio->page);' \"\$SW\"" \
   "nao reaproveita __lru_cache_add()"
ok "folio_add_lru usa as VM_BUG_ON de folio" \
   "grep -q 'VM_BUG_ON_FOLIO(folio_test_lru(folio), folio);' \"\$SW\"" \
   "ainda em VM_BUG_ON_PAGE"
ok "lru_cache_add virou wrapper" \
   "grep -q 'folio_add_lru(page_folio(page));' \"\$SW\"" "wrapper nao delega"
ok "lru_cache_add nao foi inventado" \
   "[ \"\$(nc 'pagevec_add_and_need_flush' \"\$SW\")\" = 0 ]" \
   "introduziu uma API que o E404 nao tem"
ok "folio_add_lru declarado em swap.h" \
   "grep -q '^extern void folio_add_lru(struct folio \*folio);$' \"\$SH\"" \
   "declaracao ausente"
ok "lru_cache_add continua declarado em swap.h" \
   "grep -q '^extern void lru_cache_add(struct page \*);$' \"\$SH\"" \
   "declaracao removida"

# --- patch 86: __filemap_add_folio -----------------------------------
ok "__filemap_add_folio definido uma vez" \
   "[ \"\$(n '^static int __filemap_add_folio(struct address_space \*mapping,$' \"\$FL\")\" = 1 ]" \
   "esperava 1 definicao"
ok "o nome antigo sumiu" \
   "[ \"\$(nc '__add_to_page_cache_locked' \"\$FL\")\" = 0 ]" \
   "ainda em __add_to_page_cache_locked"
ok "__filemap_add_folio continua static" \
   "! grep -qE '^(noinline )?int __filemap_add_folio' \"\$FL\"" \
   "foi promovido a simbolo global sem necessidade"
ok "nao ha ALLOW_ERROR_INJECTION nesta arvore" \
   "[ \"\$(nc 'ALLOW_ERROR_INJECTION(__filemap_add_folio' \"\$FL\")\" = 0 ]" \
   "introduziu error injection que o E404 nao tem"
ok "o teste de lock usa o folio" \
   "grep -q 'VM_BUG_ON_FOLIO(!folio_test_locked(folio), folio);' \"\$FL\"" \
   "ainda em VM_BUG_ON_PAGE"
ok "o teste de swapbacked usa o folio" \
   "grep -q 'VM_BUG_ON_FOLIO(folio_test_swapbacked(folio), folio);' \"\$FL\"" \
   "ainda em PageSwapBacked"
ok "hugetlb e testado no folio" \
   "grep -q 'int huge = folio_test_hugetlb(folio);' \"\$FL\"" \
   "ainda em PageHuge"
ok "a referencia e solta pelo folio" \
   "grep -q 'folio_put(folio);' \"\$FL\"" "ainda em put_page"
ok "o xarray guarda a page head" \
   "grep -q 'xas_store(&xas, &folio->page);' \"\$FL\"" \
   "guarda o ponteiro de folio num xarray de pages"
ok "a assert de alinhamento natural esta la" \
   "grep -q 'VM_BUG_ON_FOLIO(index & (folio_nr_pages(folio) - 1), folio);' \"\$FL\"" \
   "falta a assert de alinhamento do upstream"

# --- o protocolo de charge do E404 foi preservado ---------------------
ok "o charge continua em tres fases" \
   "grep -q 'mem_cgroup_try_charge(&folio->page, current->mm,' \"\$FL\"" \
   "o charge virou mem_cgroup_charge()"
ok "o commit de charge continua separado" \
   "grep -q 'mem_cgroup_commit_charge(&folio->page, memcg, false, false);' \"\$FL\"" \
   "o commit foi fundido"
ok "o cancel de charge continua separado" \
   "grep -q 'mem_cgroup_cancel_charge(&folio->page, memcg, false);' \"\$FL\"" \
   "o cancel foi fundido"
ok "mem_cgroup_charge do upstream nao foi inventado" \
   "[ \"\$(nc 'mem_cgroup_charge(' \"\$FL\")\" = 0 ]" \
   "introduziu uma funcao que o E404 nao tem"
ok "a contagem de NR_FILE_PAGES continua por node" \
   "grep -q '__inc_node_page_state(&folio->page, NR_FILE_PAGES);' \"\$FL\"" \
   "virou __lruvec_stat_add_folio()"
ok "nenhum stat helper de folio foi inventado" \
   "[ \"\$(nc 'stat_add_folio' \"\$FL\")\" = 0 ]" \
   "introduziu helper da familia de vmstat do upstream"
ok "nenhum helper de xarray multipage foi inventado" \
   "[ \"\$(nc 'xas_split' \"\$FL\")\" = 0 ]" \
   "introduziu xas_split() que o E404 nao tem"

# --- filemap_add_folio e os wrappers ---------------------------------
ok "filemap_add_folio definido" \
   "grep -q '^int filemap_add_folio(struct address_space \*mapping, struct folio \*folio,$' \"\$FL\"" \
   "esperava 1 definicao"
ok "filemap_add_folio exportado" \
   "[ \"\$(ncd 'EXPORT_SYMBOL_GPL(filemap_add_folio);' \"\$FL\")\" = 1 ]" "sem EXPORT_SYMBOL_GPL"
ok "filemap_add_folio tranca o folio" \
   "grep -q '__folio_set_locked(folio);' \"\$FL\"" "ainda em __SetPageLocked"
ok "filemap_add_folio destranca o folio" \
   "grep -q '__folio_clear_locked(folio);' \"\$FL\"" "ainda em __ClearPageLocked"
ok "filemap_add_folio checa active pelo folio" \
   "grep -q 'WARN_ON_ONCE(folio_test_active(folio));' \"\$FL\"" "ainda em PageActive"
ok "filemap_add_folio passa o folio ao workingset" \
   "grep -q 'workingset_refault(folio, shadow);' \"\$FL\"" \
   "ainda resolve page_folio() por dentro"
ok "filemap_add_folio joga na LRU pelo folio" \
   "grep -q 'folio_add_lru(folio);' \"\$FL\"" "ainda em lru_cache_add"
ok "filemap_add_folio declarado em pagemap.h" \
   "grep -q '^int filemap_add_folio(struct address_space \*mapping, struct folio \*folio,$' \"\$PM\"" \
   "declaracao ausente"
ok "add_to_page_cache_lru virou wrapper estatico" \
   "grep -q 'static inline int add_to_page_cache_lru(struct page \*page,' \"\$PM\"" \
   "ainda e um simbolo externo"
ok "o wrapper delega para filemap_add_folio" \
   "grep -q 'return filemap_add_folio(mapping, page_folio(page), index, gfp_mask);' \"\$PM\"" \
   "wrapper nao delega"
ok "add_to_page_cache_locked delega" \
   "grep -q 'return __filemap_add_folio(mapping, page_folio(page), offset,' \"\$FL\"" \
   "ainda chamando o nome antigo"
ok "o simbolo antigo nao e mais exportado" \
   "[ \"\$(ncd 'EXPORT_SYMBOL_GPL(add_to_page_cache_lru)' \"\$FL\")\" = 0 ]" \
   "ainda exporta o nome antigo"

# --- os callers in-tree continuam compilando -------------------------
# --- por que estas contagens sao teto, e nao igualdade ---------------------
#
# Estas contagens medem quantos callers AINDA usam a API de page.  Como cada
# estagio converte mais um deles, a contagem so pode BAIXAR de estagio para
# estagio: o G2.5c tirou um caller de __page_cache_alloc, o G2.5d outro de
# add_to_page_cache_lru e de find_get_entry, o G2.5e outro de
# pagecache_get_page.  Exigir = N fazia a verificacao de um estagio falhar
# assim que um estagio posterior era ligado, que e o uso normal.
#
# O que precisa valer e o TETO: nenhum caller novo pode aparecer usando a API
# de page.  Um estagio posterior pode converter mais, o que so reduz a
# contagem.  Daqui para frente e -le.
#
# As contagens em arquivos que nenhum estagio de folio toca -- mm/memcontrol.c
# e fs/cachefiles/rdwr.c -- continuam exatas de proposito: ali a igualdade e
# justamente a prova de que o estagio nao saiu de mm/filemap.c.
ok "os callers de filemap.c seguem usando o wrapper" \
   "[ \"\$(nc 'add_to_page_cache_lru(' \"\$FL\")\" -le 3 ]" \
   "o teto e 3: nenhum caller novo pode aparecer usando a API de page"
if [ -f "$KERNEL_DIR/fs/cachefiles/rdwr.c" ]; then
    ok "os 4 callers de cachefiles seguem usando o wrapper" \
       "[ \"\$(nc 'add_to_page_cache_lru(' \"\$KERNEL_DIR/fs/cachefiles/rdwr.c\")\" = 4 ]" \
       "esperava 4"
fi
ok "add_to_page_cache segue intacto" \
   "grep -q 'error = add_to_page_cache_locked(page, mapping, offset, gfp_mask);' \"\$PM\"" \
   "add_to_page_cache mudou"

# --- invariantes dos estagios anteriores -----------------------------
ok "o page lock do G2.3f segue inteiro" \
   "grep -q 'folio_waitqueue' \"\$FL\"" "a waitqueue sumiu"
ok "end_page_writeback do G2.4a segue inteiro" \
   "grep -q '^void end_page_writeback' \"\$FL\"" "sumiu"
ok "__folio_end_writeback do G2.4a segue inteiro" \
   "grep -q '__folio_end_writeback(folio)' \"\$FL\"" "sumiu"
ok "filemap_alloc_folio do G2.5a segue inteiro" \
   "grep -q '^struct folio \*filemap_alloc_folio(gfp_t gfp, unsigned int order)$' \"\$FL\"" \
   "sumiu"
ok "__page_cache_alloc do G2.5a segue como wrapper" \
   "grep -q 'static inline struct page \*__page_cache_alloc(gfp_t gfp)' \"\$PM\"" \
   "voltou a simbolo externo"

echo "G2.5b: todas as verificacoes passaram."
