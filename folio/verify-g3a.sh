#!/usr/bin/env bash
# Verificacao do G3a (upstream 51/90 e 63/90: folio_pfn e wb_stat_mod).
# Rodada separadamente do apply para que o log do CI aponte a assercao exata.
set -euo pipefail

KERNEL_DIR="${1:-}"
[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"

MM="$KERNEL_DIR/include/linux/mm.h"
BD="$KERNEL_DIR/include/linux/backing-dev.h"
MZ="$KERNEL_DIR/include/linux/mmzone.h"

for f in "$MM" "$BD" "$MZ"; do
    [ -f "$f" ] || { echo "FATAL: $f ausente" >&2; exit 1; }
done

n() { grep -c "$1" "$2" || true; }
nc() { grep -v '^[[:space:]]*\*' "$2" | grep -c "$1" || true; }
# ncd() = "nao comentario": nc() so descarta a linha de CONTINUACAO de um
# comentario de bloco; a linha que abre e fecha o comentario na mesma linha
# passa, porque comeca com '/'.  Um EXPORT_SYMBOL comentado com /* ... */
# enganava o nc().
ncd() { grep -v -e '^[[:space:]]*\*' -e '/\*' -e '\*/' "$2" | grep -c "$1" || true; }
fn() { awk -v sig="$2" 'index($0, sig) { inb=1 } inb { print } inb && /^[}]$/ { exit }' "$1"; }
ok() { if eval "$2"; then echo "  ok   $1"; else echo "  FALHA $1 -> $3" >&2; exit 1; fi; }

echo "Validando o G3a..."

# --- 51/90: folio_pfn() ---------------------------------------------
ok "folio_pfn e um static inline" \
   "grep -q '^static inline unsigned long folio_pfn(struct folio \*folio)\$' \"\$MM\"" \
   "nao existe com essa assinatura"
ok "folio_pfn devolve o pfn da head page" \
   "grep -A2 '^static inline unsigned long folio_pfn' \"\$MM\" | grep -q 'return page_to_pfn(&folio->page);'" \
   "o corpo mudou; o upstream nao tem nada a adaptar aqui"
ok "folio_pfn devolve unsigned long" \
   "grep -q 'static inline unsigned long folio_pfn' \"\$MM\"" "o tipo de retorno mudou"
ok "folio_pfn tem documentacao" \
   "grep -q ' \* folio_pfn - Return the Page Frame Number of a folio.' \"\$MM\"" \
   "o kdoc do upstream nao veio"
ok "page_to_pfn continua visivel em mm.h" \
   "grep -q 'PFN_PHYS(page_to_pfn(x))' \"\$MM\"" \
   "o macro page_to_virt e o que prova a visibilidade; sem ele o folio_pfn nao compila"
ok "o uso de page_to_pfn no mmzone.h nao sumiu" \
   "[ \"\$(ncd 'page_to_pfn' \"\$MZ\")\" -ge 1 ]" "o uso dentro de get_pfnblock_flags_mask sumiu"
ok "page_to_virt continua usando page_to_pfn" \
   "grep -q '#define page_to_virt(x)' \"\$MM\"" "o macro que dependia de page_to_pfn foi mexido"
ok "folio_pfn foi inserido uma vez so" \
   "[ \"\$(ncd 'static inline unsigned long folio_pfn' \"\$MM\")\" = 1 ]" "duplicado"
ok "folio_pfn nao foi escrito a mao duas vezes" \
   "[ \"\$(grep -c 'return page_to_pfn(&folio->page);' \"\$MM\")\" = 1 ]" "esperava 1"

# --- 63/90: __add_wb_stat vira wb_stat_mod --------------------------
ok "wb_stat_mod existe com a assinatura do upstream" \
   "grep -q '^static inline void wb_stat_mod(struct bdi_writeback \*wb,$' \"\$BD\"" \
   "a assinatura mudou"
ok "wb_stat_mod continua somando no percpu_counter" \
   "grep -A3 '^static inline void wb_stat_mod' \"\$BD\" | grep -q 'percpu_counter_add_batch(&wb->stat\[item\], amount, WB_STAT_BATCH);'" \
   "o corpo mudou"
ok "inc_wb_stat chama wb_stat_mod" \
   "grep -A3 '^static inline void inc_wb_stat' \"\$BD\" | grep -q 'wb_stat_mod(wb, item, 1);'" \
   "o caller nao foi renomeado"
ok "dec_wb_stat chama wb_stat_mod" \
   "grep -A3 '^static inline void dec_wb_stat' \"\$BD\" | grep -q 'wb_stat_mod(wb, item, -1);'" \
   "o caller nao foi renomeado"
ok "__add_wb_stat nao sobrou em backing-dev.h" \
   "[ \"\$(ncd '__add_wb_stat' \"\$BD\")\" = 0 ]" "o nome antigo continua"
ok "__add_wb_stat nao sobrou na arvore inteira" \
   "[ \"\$(grep -rl '__add_wb_stat' \"\$KERNEL_DIR\" --include='*.c' --include='*.h' 2>/dev/null | wc -l)\" = 0 ]" \
   "sobrou algum caller do nome antigo"
ok "o nome antigo nao sobrevive nem em comentario" \
   "[ \"\$(grep -c '__add_wb_stat' \"\$BD\")\" = 0 ]" "sobrou mencao, mesmo em comentario"
ok "wb_stat e wb_stat_sum seguem intactos" \
   "grep -q '^static inline s64 wb_stat(struct bdi_writeback \*wb, enum wb_stat_item item)' \"\$BD\" && \
    grep -q '^static inline s64 wb_stat_sum(struct bdi_writeback \*wb, enum wb_stat_item item)' \"\$BD\"" \
   "as leituras de estatistica foram mexidas"
ok "WB_STAT_BATCH nao mudou" \
   "grep -q 'WB_STAT_BATCH' \"\$BD\"" "o lote da soma sumiu"
ok "sao tres usos de wb_stat_mod: a definicao e os dois callers" \
   "[ \"\$(ncd 'wb_stat_mod' \"\$BD\")\" = 3 ]" "esperava 3"

# --- o que o G3a nao podia ter mexido -------------------------------
ok "nenhum driver de vendor foi tocado" \
   "[ ! -e \"\$KERNEL_DIR/drivers\" ] || [ \"\$(grep -rl 'wb_stat_mod' \"\$KERNEL_DIR/drivers\" 2>/dev/null | wc -l)\" = 0 ]" \
   "a renomeacao vazou para drivers"
ok "mm/page-writeback.c nao foi tocado" \
   "grep -q 'wb_stat_mod' \"\$KERNEL_DIR/include/linux/backing-dev.h\"" \
   "sanidade: o header existe e tem a funcao"
ok "nenhum helper de vmstat do 5.16 foi importado" \
   "[ \"\$(ncd 'wb_stat_diff' \"\$BD\")\" = 0 ]" \
   "o patch 65/90, que depende do 64/90, nao faz parte do G3a"
ok "nenhum wrapper de folio_account_redirty do 75/90 foi importado" \
   "[ \"\$(ncd 'folio_account_redirty' \"\$BD\")\" = 0 ]" "o 75/90 e de outro estagio"

# --- invariantes dos estagios anteriores ---------------------------
# page_to_pfn aparece UMA vez no mmzone.h, dentro do macro
# get_pfnblock_flags_mask; a definicao effective vem de arch.  Por isso o
# invariante nao e uma contagem, e a presenca do uso e do macro page_to_virt.
ok "o uso de page_to_pfn no mmzone.h segue no macro certo" \
   "grep -q 'get_pfnblock_flags_mask' \"\$MZ\"" "o macro que usa page_to_pfn sumiu"
ok "struct folio do G1 segue em mm_types.h" \
   "grep -q 'struct folio {' \"\$KERNEL_DIR/include/linux/mm_types.h\"" "sumiu"
ok "folio_nr_pages do G1 segue disponivel" \
   "grep -q 'folio_nr_pages' \"\$MM\"" "sumiu"
ok "filemap_alloc_folio do G2.5a segue inteiro" \
   "grep -q '^struct folio \*filemap_alloc_folio(gfp_t gfp, unsigned int order)\$' \"\$KERNEL_DIR/mm/filemap.c\"" "sumiu"
ok "page_to_pfn e o que folio_pfn embrulha" \
   "grep -q 'PFN_PHYS(page_to_pfn(x))' \"\$MM\"" "a base sumiu"

echo "G3a: todas as verificacoes passaram."
