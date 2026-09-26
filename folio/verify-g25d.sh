#!/usr/bin/env bash
# Verificacao do G2.5d (upstream patch 88/90: filemap_get_folio).
# Rodada separadamente do apply para que o log do CI aponte a assercao exata.
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

n() { grep -c "$1" "$2" || true; }
nc() { grep -v '^[[:space:]]*\*' "$2" | grep -c "$1" || true; }
# fn() extrai o corpo de uma funcao, ate a chave de abertura no nivel 0.
# A assinatura passada tem de ser mais especifica que a linha do comentario
# kdoc, senao awk casa na documentacao e devolve o bloco errado.
fn() { awk -v sig="$2" 'index($0, sig) { inb=1 } inb { print } inb && /^[}]$/ { exit }' "$1"; }
ok() { if eval "$2"; then echo "  ok   $1"; else echo "  FALHA $1 -> $3" >&2; exit 1; fi; }

echo "Validando o G2.5d..."

GET="$(fn "$FL" 'struct folio *__filemap_get_folio(struct address_space *mapping')"
WRAP="$(fn "$FL" 'struct page *pagecache_get_page(struct address_space *mapping')"
MA="$(fn "$SW" 'void folio_mark_accessed(struct folio *folio)')"
MPA="$(fn "$SW" 'void mark_page_accessed(struct page *page)')"

ok "corpo de __filemap_get_folio extraido" \
   "grep -q 'folio = mapping_get_entry(mapping, index);' <<< \"\$GET\"" "nao achei o corpo"
ok "corpo de pagecache_get_page extraido" \
   "grep -q '__filemap_get_folio(mapping, offset' <<< \"\$WRAP\"" "nao achei o wrapper"
ok "corpo de folio_mark_accessed extraido" \
   "grep -q 'struct page \*page = &folio->page;' <<< \"\$MA\"" "nao achei a implementacao"
ok "corpo de mark_page_accessed extraido" \
   "grep -q 'folio_mark_accessed(page_folio(page));' <<< \"\$MPA\"" "o wrapper nao delega"

# --- __filemap_get_folio: a funcao convertida ------------------------
ok "__filemap_get_folio devolve struct folio *" \
   "grep -q '^struct folio \*__filemap_get_folio(struct address_space \*mapping, pgoff_t index,$' \"\$FL\"" \
   "a assinatura nao foi convertida"
ok "__filemap_get_folio esta exportada" \
   "grep -q 'EXPORT_SYMBOL(__filemap_get_folio);' \"\$FL\"" "perdeu o export"
ok "a funcao carrega a entrada como folio" \
   "grep -q 'struct folio \*folio;' <<< \"\$GET\"" "ainda declara struct page *"
ok "a entrada vem do mapping_get_entry do G2.5c" \
   "grep -q 'folio = mapping_get_entry(mapping, index);' <<< \"\$GET\"" \
   "ainda usa find_get_entry()"
ok "a entrada de shadow/swap continua virando NULL" \
   "grep -q 'if (xa_is_value(folio))' <<< \"\$GET\"" "a checagem de xa_is_value mudou"
ok "a espera do lock e feita no folio" \
   "grep -q 'folio_lock(folio);' <<< \"\$GET\"" "ainda em lock_page()"
ok "o trylock e feito no folio" \
   "grep -q 'folio_trylock(folio)' <<< \"\$GET\"" "ainda em trylock_page()"
ok "o unlock de retry e feito no folio" \
   "grep -q 'folio_unlock(folio);' <<< \"\$GET\"" "ainda em unlock_page()"
ok "a referencia e solta pelo folio" \
   "grep -q 'folio_put(folio);' <<< \"\$GET\"" "ainda em put_page()"
ok "a invariante do E404 virou VM_BUG_ON_FOLIO" \
   "grep -q 'VM_BUG_ON_FOLIO(folio->index != index, folio);' <<< \"\$GET\"" \
   "esperava folio->index == index"
ok "FGP_ACCESSED marca o folio" \
   "grep -q 'folio_mark_accessed(folio);' <<< \"\$GET\"" "ainda em mark_page_accessed()"
ok "FGP_CREAT aloca com filemap_alloc_folio" \
   "grep -q 'folio = filemap_alloc_folio(gfp, 0);' <<< \"\$GET\"" "ainda em __page_cache_alloc()"
ok "FGP_CREAT inicializa o bit referenced no folio" \
   "grep -q '__folio_set_referenced(folio);' <<< \"\$GET\"" "ainda em __SetPageReferenced()"
ok "FGP_CREAT insere com filemap_add_folio" \
   "grep -q 'err = filemap_add_folio(mapping, folio, index, gfp);' <<< \"\$GET\"" \
   "ainda em add_to_page_cache_lru()"
ok "o mapeamento sujo segue com o nome do E404" \
   "grep -q 'mapping_cap_account_dirty(mapping)' <<< \"\$GET\"" \
   "veio mapping_can_writeback() do 5.16"

# --- nada de 5.16 foi inventado aqui --------------------------------
# E404 nao tem FGP_HEAD nem find_subpage porque o xarray so guarda head pages;
# nao tem FGP_ENTRY porque a funcao sempre converte value em NULL; e nao tem
# thp_contains.  Reproduzir qualquer um deles seria importar de 5.16 algo que
# aqui nao tem contraparte.
ok "nenhum FGP_HEAD foi inventado" \
   "[ \"\$(nc 'FGP_HEAD' \"\$FL\")\" = 0 ]" "FGP_HEAD nao existe no E404"
ok "nenhum find_subpage foi chamado" \
   "[ \"\$(grep -c 'find_subpage' <<< \"\$GET\")\" = 0 ]" "achou find_subpage()"
ok "nenhum thp_contains foi chamado" \
   "[ \"\$(grep -c 'thp_contains' <<< \"\$GET\")\" = 0 ]" "achou thp_contains()"
ok "nenhum FGP_ENTRY foi inventado" \
   "[ \"\$(nc 'FGP_ENTRY' \"\$FL\")\" = 0 ]" "FGP_ENTRY nao existe no E404"
FLH=$(( $(nc 'find_lock_head' "$FL") + $(nc 'find_lock_head' "$PM") ))
ok "nenhum find_lock_head foi criado" \
   "[ \"\$FLH\" = 0 ]" "achou find_lock_head()"
ok "o xarray nao ganhou entrada multi-page" \
   "[ \"\$(nc 'thp_nr_pages' \"\$FL\")\" = 0 ]" "o xarray foi convertido para THP"

# --- o wrapper pagecache_get_page ------------------------------------
# Ele fica como funcao real, e nao static inline, porque pagecache_get_page
# esta na lista de ABI do vendor (android/abi_gki_aarch64_qcom) e o simbolo
# precisa continuar existindo.  E404 nao tem FGP_HEAD, entao a head page e
# sempre a resposta certa e nao ha fallback para folio_file_page().
ok "pagecache_get_page continua sendo funcao real" \
   "grep -q '^struct page \*pagecache_get_page(struct address_space \*mapping, pgoff_t offset,$' \"\$FL\"" \
   "virou static inline e o simbolo do vendor desapareceu"
ok "pagecache_get_page continua exportada" \
   "grep -q 'EXPORT_SYMBOL(pagecache_get_page);' \"\$FL\"" \
   "o vendor promete o simbolo em abi_gki_aarch64_qcom"
ok "o wrapper delega para __filemap_get_folio" \
   "grep -q 'struct folio \*folio = __filemap_get_folio(mapping, offset, fgp_flags,' <<< \"\$WRAP\"" \
   "o wrapper nao delega"
ok "o wrapper repassa as duas flags" \
   "grep -q 'cache_gfp_mask);' <<< \"\$WRAP\"" "o wrapper perde a gfp"
ok "o wrapper tira a head page" \
   "grep -q 'return folio ? &folio->page : NULL;' <<< \"\$WRAP\"" "nao tira a head page"
ok "o wrapper trata NULL antes de dereferenciar" \
   "[ \"\$(grep -c '&folio->page' <<< \"\$WRAP\")\" = 1 ]" "pode dereferenciar NULL"
ok "o wrapper nao tem fallback para folio_file_page" \
   "[ \"\$(grep -c 'folio_file_page' <<< \"\$WRAP\")\" = 0 ]" \
   "nao ha entrada multi-page no E404, logo nao ha o que escolher"
ok "a declaracao de __filemap_get_folio entrou no header" \
   "grep -q '^struct folio \*__filemap_get_folio(struct address_space \*mapping, pgoff_t index,$' \"\$PM\"" \
   "falta a declaracao"
ok "a declaracao de pagecache_get_page nao mudou" \
   "grep -q '^struct page \*pagecache_get_page(struct address_space \*mapping, pgoff_t offset,$' \"\$PM\"" \
   "a declaracao mudou"
ok "filemap_get_folio e um inline novo" \
   "grep -q '^static inline struct folio \*filemap_get_folio(struct address_space \*mapping,$' \"\$PM\"" \
   "o inline nao existe"
ok "filemap_get_folio delega sem flags" \
   "grep -q 'return __filemap_get_folio(mapping, index, 0, 0);' \"\$PM\"" "o inline nao delega"
ok "filemap_get_folio nao exporta nada" \
   "[ \"\$(nc 'EXPORT_SYMBOL' \"\$PM\")\" = 0 ]" "o header passou a exportar simbolo"

# --- a lista de ABI do vendor ---------------------------------------
# O arquivo e um ini: "[abi_symbol_list]" no topo e dois espacos de indentacao
# em cada simbolo.  Por isso o padrão de busca comeca em [[:space:]]* em vez
# de ancorar na coluna 0.
# A arvore de trabalho local tem so fs/include/kernel/mm, entao o arquivo
# pode nao existir.  No CI a arvore esta completa e a checagem roda de verdade.
ABI="$KERNEL_DIR/android/abi_gki_aarch64_qcom"
if [ -f "$ABI" ]; then
    ok "pagecache_get_page e um simbolo prometido pelo vendor" \
       "grep -qE '^[[:space:]]*pagecache_get_page[[:space:]]*\$' \"\$ABI\"" \
       "a lista de ABI mudou: reavaliar se o wrapper ainda e necessario"
    ok "__filemap_get_folio nao foi para a lista de ABI" \
       "[ \"\$(grep -cE '^[[:space:]]*__filemap_get_folio[[:space:]]*\$' \"\$ABI\" || true)\" = 0 ]" \
       "a lista de ABI nao deveria ter ganhado simbolo novo"
else
    echo "  --   lista de ABI do vendor ausente na arvore; checagem pulada"
fi

# --- folio_mark_accessed ---------------------------------------------
# Corpo do E404, nao o do 5.16: o E404 nao retorna cedo em folio unevictable e
# limpa o bit idle no fim.  Trocar qualquer um dos dois mudaria comportamento,
# e nao so o tipo.  O que de fato sai e o compound_head(), porque um folio ja
# e o head.
ok "folio_mark_accessed pega a head page do folio" \
   "grep -q 'struct page \*page = &folio->page;' <<< \"\$MA\"" "nao pega a head page"
ok "o compound_head saiu do caminho do folio" \
   "[ \"\$(grep -c 'compound_head' <<< \"\$MA\")\" = 0 ]" "ainda resolve compound_head()"
ok "o MGLRU continua contando refs pela page" \
   "grep -q 'page_inc_refs(page);' <<< \"\$MA\"" "o ramo do MGLRU mudou"
ok "a ativacao continua indo para o pagevec" \
   "grep -q '__lru_cache_activate_page(page);' <<< \"\$MA\"" "a ativacao mudou"
ok "o accounting de workingset continua igual" \
   "grep -q 'workingset_activation(page);' <<< \"\$MA\"" "o accounting mudou"
ok "o bit idle continua sendo limpo (E404, nao 5.16)" \
   "grep -q 'clear_page_idle(page);' <<< \"\$MA\"" "a limpeza de idle do E404 sumiu"
ok "nao ha retorno cedo em unevictable (E404, nao 5.16)" \
   "[ \"\$(grep -c 'folio_test_unevictable' <<< \"\$MA\")\" = 0 ]" \
   "veio o corpo do 5.16, que retorna cedo"
ok "folio_mark_accessed esta exportada" \
   "grep -q 'EXPORT_SYMBOL(folio_mark_accessed);' \"\$SW\"" "perdeu o export"
ok "mark_page_accessed virou wrapper" \
   "[ \"\$(grep -c 'compound_head' <<< \"\$MPA\")\" = 0 ]" "o wrapper ainda e a implementacao"
ok "mark_page_accessed continua exportada" \
   "grep -q 'EXPORT_SYMBOL(mark_page_accessed);' \"\$SW\"" "perdeu o export"

# --- declaracoes: uma so, e no lugar certo ---------------------------
ok "folio_mark_accessed e declarada uma vez" \
   "[ \"\$(nc 'extern void folio_mark_accessed' \"\$SH\")\" = 1 ]" \
   "declaracao faltando ou duplicada"
ok "a declaracao de folio_mark_accessed usa struct folio *" \
   "grep -q '^extern void folio_mark_accessed(struct folio \*folio);\$' \"\$SH\"" \
   "a declaracao nao bate com a definicao"
ok "mark_page_accessed e declarada uma vez" \
   "[ \"\$(nc 'mark_page_accessed' \"\$SH\")\" = 1 ]" \
   "declaracao duplicada; o GCC aceita mas o kernelpatchci nao"
ok "a declaracao de mark_page_accessed nao mudou" \
   "grep -q '^extern void mark_page_accessed(struct page \*);\$' \"\$SH\"" \
   "a declaracao antiga foi sobrescrita"
ok "folio_mark_accessed nao e declarada duas vezes em swap.c" \
   "[ \"\$(grep -c '^extern void folio_mark_accessed' \"\$SH\" || true)\" = 1 ]" "duplicada"

# --- os callers antigos seguem compilando sem mudanca ----------------
# Os cinco wrappers de pagemap.h chamam pagecache_get_page e continuam
# intactos: o G2.5d nao converte nenhum deles, so adiciona o filemap_get_folio.
# find_get_page, find_get_page_flags, find_lock_page, find_or_create_page e
# grab_cache_page_nowait: cinco wrappers, nenhum convertido por este patch.
ok "os 5 wrappers de pagemap.h seguem usando pagecache_get_page" \
   "[ \"\$(nc 'return pagecache_get_page(mapping' \"\$PM\")\" = 5 ]" "esperava 5"
ok "find_get_page segue intacto" \
   "grep -q '^static inline struct page \*find_get_page(struct address_space \*mapping,$' \"\$PM\"" \
   "find_get_page mudou"
ok "find_lock_page segue intacto" \
   "grep -q '^static inline struct page \*find_lock_page(struct address_space \*mapping,$' \"\$PM\"" \
   "find_lock_page mudou"
ok "o caller interno de filemap.c segue usando pagecache_get_page" \
   "[ \"\$(nc '= pagecache_get_page(mapping' \"\$FL\")\" = 2 ]" "esperava 2"

# --- o wrapper find_get_entry do G2.5c continua de pe -----------------
# O 88/90 converte so pagecache_get_page.  find_lock_entry e
# mm/memcontrol.c ainda chamam find_get_entry, entao o wrapper do G2.5c nao
# pode ser removido aqui; o 5.16 so o drops num patch posterior.
ok "find_get_entry do G2.5c continua exportado" \
   "grep -q 'EXPORT_SYMBOL(find_get_entry);' \"\$FL\"" "perdeu o export"
ok "find_get_entry continua devolvendo struct page *" \
   "grep -q '^struct page \*find_get_entry(struct address_space \*mapping, pgoff_t offset)$' \"\$FL\"" \
   "a assinatura mudou"
ok "so find_lock_entry ainda usa find_get_entry" \
   "[ \"\$(nc '= find_get_entry(mapping, offset);' \"\$FL\")\" = 1 ]" \
   "esperava 1: pagecache_get_page era o segundo e migrou para mapping_get_entry"

# --- invariantes dos estagios anteriores -----------------------------
ok "filemap_alloc_folio do G2.5a segue inteiro" \
   "grep -q '^struct folio \*filemap_alloc_folio(gfp_t gfp, unsigned int order)$' \"\$FL\"" "sumiu"
ok "filemap_add_folio do G2.5b segue inteiro" \
   "grep -q '^int filemap_add_folio(struct address_space \*mapping, struct folio \*folio,$' \"\$FL\"" "sumiu"
ok "mapping_get_entry do G2.5c segue inteiro" \
   "grep -q '^static void \*mapping_get_entry(struct address_space \*mapping, pgoff_t index)$' \"\$FL\"" "sumiu"
ok "folio_waitqueue do G2.3f segue inteiro" \
   "grep -q 'folio_waitqueue' \"\$FL\"" "a waitqueue sumiu"
ok "__folio_end_writeback do G2.4a segue inteiro" \
   "grep -q '__folio_end_writeback(folio)' \"\$FL\"" "sumiu"

echo "G2.5d: todas as verificacoes passaram."
