#!/usr/bin/env bash
# Verificacao do G2.5c (upstream patch 87/90: mapping_get_entry por folio).
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
PM="$KERNEL_DIR/include/linux/pagemap.h"
PR="$KERNEL_DIR/include/linux/page_ref.h"
MMH="$KERNEL_DIR/include/linux/mm.h"
MC="$KERNEL_DIR/mm/memcontrol.c"

for f in "$FL" "$PM" "$PR" "$MC" "$MMH"; do
    [ -f "$f" ] || { echo "FATAL: $f ausente" >&2; exit 1; }
done

n() { grep -c "$1" "$2" || true; }
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

echo "Validando o G2.5c..."

BODY="$(fn "$FL" 'static void *mapping_get_entry(struct address_space *mapping, pgoff_t index)')"
WRAP="$(fn "$FL" 'struct page *find_get_entry(struct address_space *mapping, pgoff_t offset)')"
ok "corpo de mapping_get_entry extraido" \
   "grep -q 'folio_try_get_rcu' <<< \"\$BODY\"" "nao achei o corpo"
ok "corpo de find_get_entry extraido" \
   "grep -q 'mapping_get_entry(mapping, offset)' <<< \"\$WRAP\"" "nao achei o wrapper"

# --- a funcao convertida ---------------------------------------------
ok "mapping_get_entry e static e devolve void *" \
   "grep -q '^static void \*mapping_get_entry(struct address_space \*mapping, pgoff_t index)$' \"\$FL\"" \
   "esperava 1 definicao estatica retornando void *"
ok "mapping_get_entry carrega a entrada como folio" \
   "grep -q 'struct folio \*folio;' <<< \"\$BODY\"" "ainda declara struct page *"
ok "a entrada vai para a variavel folio" \
   "grep -q 'folio = xas_load(&xas);' <<< \"\$BODY\"" "ainda em page = xas_load()"
ok "o retry compara com o folio" \
   "grep -q 'if (xas_retry(&xas, folio))' <<< \"\$BODY\"" "ainda comparando com page"
ok "a entrada vazia e testada com xa_is_value" \
   "grep -q 'if (!folio || xa_is_value(folio))' <<< \"\$BODY\"" "teste de entrada vazia mudou"
ok "a referencia e pega pelo folio" \
   "grep -q 'if (!folio_try_get_rcu(folio))' <<< \"\$BODY\"" "ainda em page_cache_get_speculative()"
ok "a referencia e solta pelo folio" \
   "grep -q 'folio_put(folio);' <<< \"\$BODY\"" "ainda em put_page()"
ok "a unica checagem e o reload do xarray" \
   "grep -q 'if (unlikely(folio != xas_reload(&xas))) {' <<< \"\$BODY\"" "a checagem mudou"
ok "a funcao devolve o folio" \
   "grep -q 'return folio;' <<< \"\$BODY\"" "nao devolve o folio"

# --- o que o E404 usava e que nao deve sobrar -----------------------
ok "nenhum compound_head no corpo" \
   "[ \"\$(grep -c 'compound_head' <<< \"\$BODY\")\" = 0 ]" \
   "ainda resolve compound_head()"
ok "a checagem de split foi removida" \
   "[ \"\$(grep -c 'split under us' <<< \"\$BODY\")\" = 0 ]" \
   "a checagem de split continua"
ok "page_cache_get_speculative saiu daqui" \
   "[ \"\$(grep -c 'page_cache_get_speculative' <<< \"\$BODY\")\" = 0 ]" \
   "ainda especula pela page"
ok "folio_try_get_rcu e o que faz a especulacao" \
   "[ \"\$(grep -c 'folio_try_get_rcu(folio)' <<< \"\$BODY\")\" = 1 ]" \
   "esperava exatamente 1"

# --- o wrapper preserva os callers -----------------------------------
ok "find_get_entry continua devolvendo struct page *" \
   "grep -q '^struct page \*find_get_entry(struct address_space \*mapping, pgoff_t offset)$' \"\$FL\"" \
   "a assinatura mudou"
ok "find_get_entry continua exportado" \
   "[ \"\$(ncd 'EXPORT_SYMBOL(find_get_entry);' \"\$FL\")\" = 1 ]" "perdeu o export"
ok "o wrapper delega para mapping_get_entry" \
   "grep -q 'void \*entry = mapping_get_entry(mapping, offset);' <<< \"\$WRAP\"" \
   "o wrapper nao delega"
ok "o wrapper trata NULL antes de dereferenciar" \
   "grep -q 'if (!entry || xa_is_value(entry))' <<< \"\$WRAP\"" \
   "pode dereferenciar NULL"
ok "o wrapper devolve a entrada de shadow/swap intacta" \
   "grep -q 'return (struct page \*)entry;' <<< \"\$WRAP\"" \
   "converte shadow/swap em page"
ok "o wrapper tira o head page do folio" \
   "grep -q 'return &page_folio((struct page \*)entry)->page;' <<< \"\$WRAP\"" \
   "nao tira a head page"
ok "o wrapper faz cast explicito antes de page_folio" \
   "grep -q 'page_folio((struct page \*)entry)' <<< \"\$WRAP\"" \
   "page_folio e _Generic e nao aceita void *"
ok "a declaracao em pagemap.h nao mudou" \
   "grep -q '^struct page \*find_get_entry(struct address_space \*mapping, pgoff_t offset);\$' \"\$PM\"" \
   "a declaracao mudou"
ok "mapping_get_entry nao foi declarado no header" \
   "[ \"\$(nc 'mapping_get_entry' \"\$PM\")\" = 0 ]" \
   "a funcao estatica nao deve ser declarada"

# --- os tres callers seguem compilando sem mudanca -------------------
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
ok "os callers de filemap.c seguem usando find_get_entry" \
   "[ \"\$(nc '= find_get_entry(mapping, offset);' \"\$FL\")\" -le 2 ]" \
   "o teto e 2: nenhum caller novo pode aparecer usando a API de page"
ok "o caller de memcontrol.c segue usando find_get_entry" \
   "[ \"\$(nc 'find_get_entry(mapping, pgoff);' \"\$MC\")\" = 1 ]" "esperava 1"
ok "pagecache_get_page nao foi convertido ainda" \
   "grep -q '^struct page \*pagecache_get_page(struct address_space \*mapping, pgoff_t offset,$' \"\$FL\"" \
   "foi convertido de volta no patch errado"
ok "find_lock_entry segue intacto" \
   "grep -q '^struct page \*find_lock_entry(struct address_space \*mapping, pgoff_t offset)$' \"\$FL\"" \
   "find_lock_entry mudou de assinatura"

# --- a semantica da referencia e a mesma ---------------------------
# Sem CONFIG_TINY_RCU, folio_try_get_rcu() reduz a page_ref_add_unless() com
# nr = 1, e page_cache_get_speculative() reduz a get_page_unless_zero(), que
# e a mesma coisa.  Conferir os dois corpos e mais forte do que ler o .config
# e funciona antes de o .config existir.  A checagem de que TINY_RCU esta
# desligado vive num step do CI que roda depois da geracao do .config.
ok "folio_try_get_rcu usa a mesma primitiva do E404" \
   "grep -q 'return folio_ref_try_add_rcu(folio, 1);' \"\$PR\"" \
   "folio_try_get_rcu mudou"
ok "a primitiva sem TINY_RCU e um add-if-not-zero" \
   "grep -q 'if (unlikely(!folio_ref_add_unless(folio, count, 0)))' \"\$PR\"" \
   "o caminho sem TINY_RCU mudou"
ok "as duas primitivas convergem no mesmo helper" \
   "grep -q 'return page_ref_add_unless(&folio->page, nr, u);' \"\$PR\"" \
   "folio_ref_add_unless nao delega para o helper de page"
ok "get_page_unless_zero usa esse mesmo helper" \
   "grep -q 'return page_ref_add_unless(page, 1, 0);' \"\$MMH\"" \
   "o lado de page nao usa o mesmo helper"
ok "a diferenca de TINY_RCU continua declarada" \
   "grep -q '#ifdef CONFIG_TINY_RCU' \"\$PR\"" \
   "o ramo de TINY_RCU desapareceu"

# --- invariantes dos estagios anteriores -----------------------------
ok "filemap_alloc_folio do G2.5a segue inteiro" \
   "grep -q '^struct folio \*filemap_alloc_folio(gfp_t gfp, unsigned int order)$' \"\$FL\"" \
   "sumiu"
ok "__filemap_add_folio do G2.5b segue inteiro" \
   "grep -q '^static int __filemap_add_folio(struct address_space \*mapping,$' \"\$FL\"" \
   "sumiu"
ok "filemap_add_folio do G2.5b segue inteiro" \
   "grep -q '^int filemap_add_folio(struct address_space \*mapping, struct folio \*folio,$' \"\$FL\"" \
   "sumiu"
ok "o page lock do G2.3f segue inteiro" \
   "grep -q 'folio_waitqueue' \"\$FL\"" "a waitqueue sumiu"
ok "__folio_end_writeback do G2.4a segue inteiro" \
   "grep -q '__folio_end_writeback(folio)' \"\$FL\"" "sumiu"

echo "G2.5c: todas as verificacoes passaram."
