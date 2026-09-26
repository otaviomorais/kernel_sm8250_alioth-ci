#!/usr/bin/env bash
# Verificacao do G3b (upstream 52/90, 53/90 e 59/90).
# Rodada separadamente do apply para que o log do CI aponte a assercao exata.
set -euo pipefail

KERNEL_DIR="${1:-}"
[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"

UC="$KERNEL_DIR/mm/util.c"
RC="$KERNEL_DIR/mm/rmap.c"
RH="$KERNEL_DIR/include/linux/rmap.h"
CF="$KERNEL_DIR/include/asm-generic/cacheflush.h"
PF="$KERNEL_DIR/include/linux/page-flags.h"
PW="$KERNEL_DIR/mm/page-writeback.c"

for f in "$UC" "$RC" "$RH" "$CF" "$PF" "$PW"; do
    [ -f "$f" ] || { echo "FATAL: $f ausente" >&2; exit 1; }
done

n() { grep -c "$1" "$2" || true; }
nc() { grep -v '^[[:space:]]*\*' "$2" | grep -c "$1" || true; }
ncd() { grep -v -e '^[[:space:]]*\*' -e '/\*' -e '\*/' "$2" | grep -c "$1" || true; }
fn() { awk -v sig="$2" 'index($0, sig) { inb=1 } inb { print } inb && /^[}]$/ { exit }' "$1"; }
ok() { if eval "$2"; then echo "  ok   $1"; else echo "  FALHA $1 -> $3" >&2; exit 1; fi; }

echo "Validando o G3b..."

# --- 52/90: folio_raw_mapping() ---------------------------------------
# O upstream poe em mm/internal.h; aqui vai em mm/util.c porque
# PAGE_MAPPING_FLAGS nao e visivel em mm/internal.h.
ok "folio_raw_mapping e um static inline" \
   "grep -q '^static inline void \*folio_raw_mapping(struct folio \*folio)\$' \"\$UC\"" \
   "nao existe em mm/util.c"
ok "folio_raw_mapping mascara PAGE_MAPPING_FLAGS" \
   "grep -A4 '^static inline void \*folio_raw_mapping' \"\$UC\" | grep -q 'mapping & ~PAGE_MAPPING_FLAGS'" \
   "o corpo mudou"
ok "folio_raw_mapping le o mapping do folio" \
   "grep -A4 '^static inline void \*folio_raw_mapping' \"\$UC\" | grep -q 'folio->mapping'" \
   "leu a page em vez do folio"
ok "folio_raw_mapping nao foi para mm/internal.h" \
   "[ \"\$(ncd 'folio_raw_mapping' \"\$KERNEL_DIR/mm/internal.h\")\" = 0 ]" \
   "la PAGE_MAPPING_FLAGS nao e visivel; o upstream nao compila aqui"
ok "__page_rmapping continua onde estava" \
   "grep -q '^static inline void \*__page_rmapping(struct page \*page)\$' \"\$UC\"" \
   "o helper do E404 foi removido em vez de preservado"
ok "page_rmapping passou a usar o folio" \
   "grep -A3 '^void \*page_rmapping(struct page \*page)' \"\$UC\" | grep -q 'return folio_raw_mapping(page_folio(page));'" \
   "ainda faz compound_head() e chama __page_rmapping"
ok "page_anon_vma passou a usar o folio" \
   "grep -A5 '^struct anon_vma \*page_anon_vma' \"\$UC\" | grep -q 'struct folio \*folio = page_folio(page);'" \
   "ainda resolve compound_head()"
ok "page_anon_vma devolve o ponteiro sem a flag ANON" \
   "grep -A7 '^struct anon_vma \*page_anon_vma' \"\$UC\" | grep -q 'return (void \*)(mapping - PAGE_MAPPING_ANON);'" \
   "o upstream subtrai a flag; aqui tem que subtrair"
ok "page_mapping do E404 nao foi convertida" \
   "grep -q '^struct address_space \*page_mapping(struct page \*page)\$' \"\$UC\"" \
   "o G2.3a a deixou como page de proposito"

# --- 53/90: flush_dcache_folio() --------------------------------------
# No arm64 do E404 flush_dcache_page e no-op, entao o folio tambem e.
ok "ARCH_IMPLEMENTS_FLUSH_DCACHE_FOLIO foi declarado" \
   "grep -q '^#define ARCH_IMPLEMENTS_FLUSH_DCACHE_FOLIO 1\$' \"\$CF\"" \
   "a arquitetura nao declarou que implementa"
ok "flush_dcache_folio e um no-op" \
   "grep -q '^static inline void flush_dcache_folio(struct folio \*folio) { }\$' \"\$CF\"" \
   "o arm40 nao precisa de flush de cache, entao o inline tem de ser vazio"
ok "flush_dcache_page continua no-op" \
   "grep -q '^#define flush_dcache_page(page)' \"\$CF\"" "flush_dcache_page foi mexido"
ok "ARCH_IMPLEMENTS_FLUSH_DCACHE_PAGE continua 0" \
   "grep -q '^#define ARCH_IMPLEMENTS_FLUSH_DCACHE_PAGE 0\$' \"\$CF\"" "o valor mudou"
ok "mm/util.c nao ganhou a implementacao com laco" \
   "[ \"\$(ncd 'EXPORT_SYMBOL(flush_dcache_folio)' \"\$UC\")\" = 0 ]" \
   "um laco chamando no-op N vezes seria trabalho inutil"
ok "o resto do cacheflush do E404 ficou intacto" \
   "grep -q '^#define flush_icache_page(vma,pg)' \"\$CF\" && \
    grep -q '^#define flush_cache_vmap(start, end)' \"\$CF\"" "o arquivo foi reescrito"

# --- 59/90: folio_mkclean() ------------------------------------------
FMC="$(fn "$RC" 'int folio_mkclean(struct folio *folio)')"
ok "corpo de folio_mkclean extraido" \
   "grep -q 'rmap_walk(&folio->page, &rwc);' <<< \"\$FMC\"" "nao achei o corpo"
ok "folio_mkclean devolve int" \
   "grep -q '^int folio_mkclean(struct folio \*folio)\$' \"\$RC\"" "a assinatura mudou"
ok "folio_mkclean esta exportada" \
   "[ \"\$(ncd 'EXPORT_SYMBOL_GPL(folio_mkclean);' \"\$RC\")\" = 1 ]" "perdeu o export"
ok "page_mkclean nao e mais exportada" \
   "[ \"\$(ncd 'EXPORT_SYMBOL_GPL(page_mkclean);' \"\$RC\")\" = 0 ]" "o nome antigo ainda e exportado"
ok "o BUG_ON testa o lock do folio" \
   "grep -q 'BUG_ON(!folio_test_locked(folio));' <<< \"\$FMC\"" "ainda em PageLocked()"
ok "o mapeamento vem do folio" \
   "grep -q 'mapping = folio_mapping(folio);' <<< \"\$FMC\"" "ainda em page_mapping()"
ok "o rmap_walk recebe a head page" \
   "grep -q 'rmap_walk(&folio->page, &rwc);' <<< \"\$FMC\"" "passou o folio inteiro"
ok "a forma do E404 foi preservada: rmap_walk_control" \
   "grep -q 'struct rmap_walk_control rwc = {' <<< \"\$FMC\"" \
   "o upstream usa rmap_walk_walk porque o 5.16 unificou os walkers; no 4.19 sao dois tipos"
ok "o inicializador .arg foi preservado" \
   "grep -q '\.arg = (void \*)&cleaned,' <<< \"\$FMC\"" \
   "sem .arg o walker nao sabe onde gravar quantas PTEs limpou"
ok "o inicializador .rmap_one foi preservado" \
   "grep -q '\.rmap_one = page_mkclean_one,' <<< \"\$FMC\"" \
   "sem .rmap_one o walker nao limpa nada"
ok "o inicializador .invalid_vma foi preservado" \
   "grep -q '\.invalid_vma = invalid_mkclean_vma,' <<< \"\$FMC\"" "perdeu o tratamento de vma invalida"
ok "usa page_mapped e nao folio_mapped, que o E404 nao tem" \
   "grep -q 'if (!page_mapped(&folio->page))' <<< \"\$FMC\"" \
   "o E404 nao tem folio_mapped; o G2.3a criou folio_mapping, que e outra coisa"
ok "folio_mapped nao foi inventado" \
   "[ \"\$(ncd 'folio_mapped' \"\$RC\")\" = 0 ]" "introduziu um simbolo que nao existe"
ok "o corpo nao volta a compound_head" \
   "[ \"\$(grep -c 'compound_head' <<< \"\$FMC\")\" = 0 ]" "ainda resolve compound_head()"
ok "o wrapper page_mkclean foi criado em rmap.h" \
   "grep -q '^static inline int page_mkclean(struct page \*page)\$' \"\$RH\"" "o wrapper nao existe"
ok "o wrapper delega para o folio" \
   "grep -A3 '^static inline int page_mkclean' \"\$RH\" | grep -q 'return folio_mkclean(page_folio(page));'" \
   "o wrapper nao delega"
ok "folio_mkclean foi declarado em rmap.h" \
   "grep -q '^int folio_mkclean(struct folio \*);\$' \"\$RH\"" \
   "falta a declaracao; o E404 escreve o prototipo sem nomear o parametro, como no page_mkclean original"
ok "o stub sem MMU tambem e do folio" \
   "grep -q '^static inline int folio_mkclean(struct folio \*folio)\$' \"\$RH\"" \
   "sem isso a build sem MMU referencia um folio_mkclean que nao existe"
ok "o wrapper fica fora do #endif do CONFIG_MMU" \
   "[ \"\$(grep -n 'static inline int page_mkclean' \"\$RH\" | cut -d: -f1)\" \
      -gt \"\$(grep -n '#endif.\{0,2\}/\* CONFIG_MMU \*/' \"\$RH\" | cut -d: -f1)\" ]" \
   "dentro do ramo ele some na build sem MMU; e o upstream 59/90 tira ele de la"
ok "o wrapper e o unico page_mkclean definido" \
   "[ \"\$(ncd 'static inline int page_mkclean' \"\$RH\")\" = 1 ]" "duas definicoes no mesmo ramo"
ok "page_mkclean nao e mais declarado duas vezes" \
   "[ \"\$(ncd '^int page_mkclean' \"\$RH\")\" = 0 ]" "a declaracao antiga sobrou ao lado do wrapper"
ok "o caller em page-writeback.c continua usando o wrapper" \
   "[ \"\$(ncd 'page_mkclean' \"\$PW\")\" = 1 ]" "esperava 1; o wrapper tem que cobrir o caller"
# folio_test_locked e gerado pelo macro, nao escrito a mao: um grep pelo nome
# literal volta zero e leva a concluir que o simbolo nao existe.  No E404 quem
# gera e __PAGEFLAG, nao PAGEFLAG.
ok "folio_test_locked vem do macro" \
   "grep -q '__PAGEFLAG(Locked, locked, PF_NO_TAIL)' \"\$PF\"" "o gerador do bit de lock mudou"

# --- o que nao podia ter vindo ---------------------------------------
ok "readahead_control nao foi inventado" \
   "[ \"\$(ncd 'struct readahead_control' \"\$UC\" \"\$RC\" \"\$RH\")\" = 0 ]" \
   "o E404 usa struct file_ra_state; o 79/90 nao e portavel"
ok "nenhum walker do 5.16 foi importado" \
   "[ \"\$(ncd 'rmap_walk_walk' \"\$RC\")\" = 0 ]" "o 4.19 tem dois walkers, nao um"
ok "nenhum folio_account_redirty do 75/90 foi importado" \
   "[ \"\$(ncd 'folio_account_redirty' \"\$PW\")\" = 0 ]" "o 75/90 e de outro estagio"
ok "nenhum i_blocks_per_folio do 77/90 foi importado" \
   "[ \"\$(ncd 'i_blocks_per_folio' \"\$RH\")\" = 0 ]" "o 77/90 medido como nao portavel"

# --- invariantes dos estagios anteriores -----------------------------
ok "folio_pfn do G3a segue inteiro" \
   "grep -q '^static inline unsigned long folio_pfn(struct folio \*folio)\$' \"\$KERNEL_DIR/include/linux/mm.h\"" "sumiu"
ok "wb_stat_mod do G3a segue inteiro" \
   "grep -q '^static inline void wb_stat_mod(struct bdi_writeback \*wb,' \"\$KERNEL_DIR/include/linux/backing-dev.h\"" "sumiu"
ok "folio_mapping do G2.3a segue disponivel" \
   "grep -q 'folio_mapping' \"\$UC\"" "sumiu"
ok "page_mapped do E404 segue intacto" \
   "grep -q '^bool page_mapped(struct page \*page)\$' \"\$UC\"" "sumiu"
ok "rmap_walk do E404 segue disponivel" \
   "grep -q 'rmap_walk' \"\$RH\"" "sumiu"

echo "G3b: todas as verificacoes passaram."
