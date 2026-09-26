#!/usr/bin/env bash
# Verificacao do G2.4b (workingset_refault por folio, upstream patch 80/90).
# Rodada separadamente do apply para que o log do CI aponte a assercao exata.
#
# O `|| true` em n()/nc() e obrigatorio: com `set -o pipefail`, um grep sem
# casamento faz o pipeline inteiro devolver 1 e o script morre ali em vez de
# comparar a contagem com 0.
set -euo pipefail

KERNEL_DIR="${1:-}"
[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"

F="$KERNEL_DIR/mm/filemap.c"
WS="$KERNEL_DIR/mm/workingset.c"
SH="$KERNEL_DIR/include/linux/swap.h"

for f in "$F" "$WS" "$SH"; do
    [ -f "$f" ] || { echo "FATAL: $f ausente" >&2; exit 1; }
done

# n() conta linhas que casam, como grep -c.
n() { grep -c "$1" "$2" || true; }
# nc() e o mesmo, ignorando linhas de comentario de bloco (" * ...").
nc() { grep -v '^[[:space:]]*\*' "$2" | grep -c "$1" || true; }
# fn() extrai o corpo de uma funcao, ate a chave de abertura no nivel 0.
fn() { awk -v sig="$2" 'index($0, sig) { inb=1 } inb { print } inb && /^[}]$/ { exit }' "$1"; }
ok() { if eval "$2"; then echo "  ok   $1"; else echo "  FALHA $1 -> $3" >&2; exit 1; fi; }

echo "Validando o G2.4b..."

# A assinatura usada na busca precisa ser substring da linha real, que tem
# dois parametros: "void workingset_refault(struct folio *folio, void *shadow)".
BODY="$(fn "$WS" 'void workingset_refault(struct folio *folio,')"
ok "corpo de workingset_refault extraido" \
   "grep -q 'WORKINGSET_REFAULT' <<< \"\$BODY\"" \
   "nao achei o corpo da funcao"

# --- a funcao passou a operar sobre o folio ----------------------------
ok "assinatura por folio, uma vez" \
   "[ \"\$(n '^void workingset_refault(struct folio \*folio, void \*shadow)$' \"\$WS\")\" = 1 ]" \
   "esperava 1 definicao com struct folio *"
ok "a assinatura antiga sumiu" \
   "[ \"\$(n 'workingset_refault(struct page' \"\$WS\")\" = 0 ]" \
   "ainda declara struct page *"
ok "declarada por folio em swap.h" \
   "grep -q '^void workingset_refault(struct folio \*folio, void \*shadow);' \"\$SH\"" \
   "declaracao ausente ou ainda em struct page *"
# A variavel page nao pode sobrar.  O &folio->page da passagem para o MGLRU e
# intencional, e os comentarios citam "page" em ingles; por isso o teste
# ignora comentarios e exige que "page" nao esteja colado a um . ou ->.
ok "a funcao nao usa mais a variavel page" \
   "! grep -v '^[[:space:]]*\*' <<< \"\$BODY\" | grep -qE '(^|[^>._[:alnum:]])page([^_[:alnum:]]|$)'" \
   "ainda referencia a variavel page"

# --- as duas flags de page foram convertidas --------------------------
ok "PG_active e setada pelo folio" \
   "grep -q 'folio_set_active(folio);' <<< \"\$BODY\"" \
   "ainda usa SetPageActive(page)"
ok "PG_workingset e setada pelo folio" \
   "grep -q 'folio_set_workingset(folio);' <<< \"\$BODY\"" \
   "ainda usa SetPageWorkingset(page)"
ok "nenhum SetPageActive sobrou na funcao" \
   "! grep -q 'SetPageActive' <<< \"\$BODY\"" \
   "ainda usa SetPageActive(page)"
ok "nenhum SetPageWorkingset sobrou na funcao" \
   "! grep -q 'SetPageWorkingset' <<< \"\$BODY\"" \
   "ainda usa SetPageWorkingset(page)"
# A unica ocorrencia de SetPageWorkingset que sobra no arquivo e a da
# lru_gen_refault(), que e do MGLRU e nao e convertida.
ok "a unica SetPageWorkingset que resta e a do MGLRU" \
   "[ \"\$(nc 'SetPageWorkingset' \"\$WS\")\" = 1 ]" \
   "esperava exatamente 1, dentro de lru_gen_refault()"
ok "a geometria vem do folio" \
   "grep -q 'nr = folio_nr_pages(folio);' <<< \"\$BODY\"" \
   "ainda assume uma pagina"

# --- o caminho do MGLRU continua sendo de page, de proposito -----------
ok "lru_gen_refault ainda recebe a page head" \
   "grep -q 'lru_gen_refault(&folio->page, shadow);' <<< \"\$BODY\"" \
   "MGLRU foi reescrito, e nao devia"
ok "a guarda do MGLRU vem antes do nr" \
   "grep -n 'lru_gen_refault(&folio->page, shadow);' <<< \"\$BODY\" | cut -d: -f1 | head -1 \
    | awk -v b=\"\$(grep -n 'nr = folio_nr_pages(folio);' <<< \"\$BODY\" | cut -d: -f1 | head -1)\" \
    'END { exit !(b > 0 && \$1 < b) }'" \
   "o early return do MGLRU ficou depois do calculo de nr"
ok "o early return do MGLRU foi preservado" \
   "grep -q 'if (lru_gen_enabled()) {' <<< \"\$BODY\"" \
   "a guarda lru_gen_enabled() sumiu"

# --- os tres contadores: forma delta, sem o split por file/anon -------
ok "refault e carregado em forma delta" \
   "grep -q 'mod_lruvec_state(lruvec, WORKINGSET_REFAULT, nr);' <<< \"\$BODY\"" \
   "continua em inc_lruvec_state()"
ok "activate e carregado em forma delta" \
   "grep -q 'mod_lruvec_state(lruvec, WORKINGSET_ACTIVATE, nr);' <<< \"\$BODY\"" \
   "continua em inc_lruvec_state()"
ok "restore e carregado em forma delta" \
   "grep -q 'mod_lruvec_state(lruvec, WORKINGSET_RESTORE, nr);' <<< \"\$BODY\"" \
   "continua em inc_lruvec_state()"
ok "nenhum inc_lruvec_state sobrou na funcao" \
   "! grep -q 'inc_lruvec_state' <<< \"\$BODY\"" \
   "ainda em inc_lruvec_state()"
ok "o split por file/anon do upstream nao foi inventado" \
   "[ \"\$(nc 'WORKINGSET_REFAULT_BASE' \"\$WS\")\" = 0 ]" \
   "introduziu um enum que o E404 nao tem"
ok "o split por file/anon nao foi inventado" \
   "[ \"\$(nc 'WORKINGSET_ACTIVATE_BASE' \"\$WS\")\" = 0 ]" \
   "introduziu um enum que o E404 nao tem"

# --- o que o E404 nao tem continua nao tendo --------------------------
ok "workingset_age_nonresident nao foi inventado" \
   "[ \"\$(nc 'workingset_age_nonresident' \"\$WS\")\" = 0 ]" \
   "introduziu uma funcao ausente no E404"
ok "lru_note_cost nao foi inventado" \
   "[ \"\$(nc 'lru_note_cost' \"\$WS\")\" = 0 ]" \
   "introduziu a maquinaria de custo de writeback do 5.16"
ok "o lru_note_cost original continua ausente" \
   "[ \"\$(n 'lru_note_cost' \"\$WS\")\" = 0 ]" \
   "esperado: nao existe no E404"

# --- o chamador converte ----------------------------------------------
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
ok "o unico chamador passa um folio" \
   "grep -q 'workingset_refault(\(folio\|page_folio(page)\), shadow);' \"\$F\"" \
   "filemap.c parou de passar um folio; no G2.4b era page_folio(page), e o G2.5d deixou de precisar do page_folio"
ok "nenhum chamador passa struct page" \
   "[ \"\$(nc 'workingset_refault(page,' \"\$F\")\" = 0 ]" \
   "sobrou chamada com struct page"
ok "workingset_eviction ficou intacto" \
   "grep -q 'void \*workingset_eviction(struct address_space \*mapping, struct page \*page)' \"\$WS\"" \
   "workingset_eviction mudou de assinatura"
ok "workingset_activation ficou intacto" \
   "grep -q '^void workingset_activation(struct page \*page)' \"\$WS\"" \
   "workingset_activation mudou de assinatura"

# --- invariantes dos estagios anteriores -----------------------------
ok "end_page_writeback intacto" \
   "grep -q '^void end_page_writeback' \"\$F\"" "sumiu"
ok "folio_end_writeback intacto" \
   "grep -q '^void folio_end_writeback' \"\$F\"" "sumiu"
ok "__folio_end_writeback do G2.4a intacto" \
   "grep -q '__folio_end_writeback(folio)' \"\$F\" && grep -q '^bool __folio_end_writeback' \"\$KERNEL_DIR/mm/page-writeback.c\"" \
   "a conversao do G2.4a foi atropelada"
ok "page lock do G2.3f intacto" \
   "grep -q 'folio_waitqueue' \"\$F\"" "a conversao da waitqueue sumiu"

echo "G2.4b: todas as verificacoes passaram."
