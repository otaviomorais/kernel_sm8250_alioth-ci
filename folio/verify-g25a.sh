#!/usr/bin/env bash
# Verificacao do G2.5a (patches 84/90 + 85/90: folio_alloc e
# filemap_alloc_folio).  Rodada separadamente do apply para que o log do CI
# aponte a assercao exata.
#
# O `|| true` em n()/nc() e obrigatorio: com `set -o pipefail`, um grep sem
# casamento faz o pipeline inteiro devolver 1 e o script morre ali em vez de
# comparar a contagem com 0.
set -euo pipefail

KERNEL_DIR="${1:-}"
[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"

GFP="$KERNEL_DIR/include/linux/gfp.h"
PM="$KERNEL_DIR/include/linux/pagemap.h"
FL="$KERNEL_DIR/mm/filemap.c"
MP="$KERNEL_DIR/mm/mempolicy.c"
PA="$KERNEL_DIR/mm/page_alloc.c"

for f in "$GFP" "$PM" "$FL" "$MP" "$PA"; do
    [ -f "$f" ] || { echo "FATAL: $f ausente" >&2; exit 1; }
done

# n() conta linhas que casam, como grep -c.
n() { grep -c "$1" "$2" || true; }
# nc() e o mesmo, ignorando linhas de comentario de bloco (" * ...").
nc() { grep -v '^[[:space:]]*\*' "$2" | grep -c "$1" || true; }
# fn() extrai o corpo de uma funcao, ate a chave de abertura no nivel 0.
fn() { awk -v sig="$2" 'index($0, sig) { inb=1 } inb { print } inb && /^[}]$/ { exit }' "$1"; }
ok() { if eval "$2"; then echo "  ok   $1"; else echo "  FALHA $1 -> $3" >&2; exit 1; fi; }

echo "Validando o G2.5a..."

# --- os quatro pontos de entrada de alocacao em folio ------------------
ok "__folio_alloc definido em page_alloc.c" \
   "[ \"\$(n '^struct folio \*__folio_alloc(gfp_t gfp, unsigned int order, int preferred_nid,$' \"\$PA\")\" = 1 ]" \
   "esperava 1 definicao com o nodemask"
ok "__folio_alloc exportado" \
   "grep -q 'EXPORT_SYMBOL(__folio_alloc);' \"\$PA\"" "sem EXPORT_SYMBOL"
ok "__folio_alloc delega para __alloc_pages_nodemask" \
   "grep -q '__alloc_pages_nodemask(gfp | __GFP_COMP, order,' \"\$PA\"" \
   "nao usa o caminho com nodemask"
ok "__folio_alloc usa a head page como folio" \
   "grep -q 'return (struct folio \*)page;' \"\$PA\"" \
   "nao devolve a head page como struct folio"
ok "__folio_alloc declara __folio_alloc em gfp.h" \
   "grep -q '^struct folio \*__folio_alloc(gfp_t gfp, unsigned int order, int preferred_nid,$' \"\$GFP\"" \
   "declaracao ausente"

ok "__folio_alloc_node definido em gfp.h" \
   "grep -q '^struct folio \*__folio_alloc_node(gfp_t gfp, unsigned int order, int nid)$' \"\$GFP\"" \
   "esperava 1 definicao"
ok "__folio_alloc_node valida o node" \
   "grep -q 'VM_BUG_ON(nid < 0 || nid >= MAX_NUMNODES);' \"\$GFP\"" \
   "perdeu a validacao de node"
ok "__folio_alloc_node passa NULL como nodemask" \
   "grep -q 'return __folio_alloc(gfp, order, nid, NULL);' \"\$GFP\"" \
   "nao delega para __folio_alloc"

ok "folio_alloc definido em mempolicy.c" \
   "grep -q '^struct folio \*folio_alloc(gfp_t gfp, unsigned int order)$' \"\$MP\"" \
   "esperava 1 definicao"
ok "folio_alloc exportado" \
   "grep -q 'EXPORT_SYMBOL(folio_alloc);' \"\$MP\"" "sem EXPORT_SYMBOL"
ok "folio_alloc usa alloc_pages_current" \
   "grep -q 'alloc_pages_current(gfp | __GFP_COMP, order)' \"\$MP\"" \
   "nao usa o caminho de NUMA do E404"
ok "folio_alloc declarado no ramo CONFIG_NUMA de gfp.h" \
   "grep -q '^struct folio \*folio_alloc(gfp_t gfp, unsigned int order);$' \"\$GFP\"" \
   "declaracao ausente"
ok "folio_alloc tem versao inline fora do NUMA" \
   "grep -q 'static inline struct folio \*folio_alloc(gfp_t gfp, unsigned int order)' \"\$GFP\"" \
   "falta a versao sem CONFIG_NUMA"

# --- filemap_alloc_folio ----------------------------------------------
ok "filemap_alloc_folio definido em filemap.c" \
   "grep -q '^struct folio \*filemap_alloc_folio(gfp_t gfp, unsigned int order)$' \"\$FL\"" \
   "esperava 1 definicao"
ok "filemap_alloc_folio exportado" \
   "grep -q 'EXPORT_SYMBOL(filemap_alloc_folio);' \"\$FL\"" "sem EXPORT_SYMBOL"
ok "filemap_alloc_folio usa __folio_alloc_node no cpuset" \
   "grep -q 'folio = __folio_alloc_node(gfp, order, n);' \"\$FL\"" \
   "ainda usa __alloc_pages_node()"
ok "filemap_alloc_folio usa folio_alloc no caminho comum" \
   "grep -q 'return folio_alloc(gfp, order);' \"\$FL\"" \
   "ainda usa alloc_pages()"
ok "filemap_alloc_folio respeita a ordem pedida" \
   "! grep -q 'filemap_alloc_folio(gfp_t gfp)' \"\$FL\"" \
   "a ordem foi fixada em 0"
ok "filemap_alloc_folio declarado no ramo CONFIG_NUMA de pagemap.h" \
   "grep -q '^struct folio \*filemap_alloc_folio(gfp_t gfp, unsigned int order);$' \"\$PM\"" \
   "declaracao ausente"
ok "filemap_alloc_folio tem versao inline fora do NUMA" \
   "grep -q 'static inline struct folio \*filemap_alloc_folio(gfp_t gfp, unsigned int order)' \"\$PM\"" \
   "falta a versao sem CONFIG_NUMA"

# --- __page_cache_alloc virou wrapper, e os callers continuam ----------
ok "__page_cache_alloc virou wrapper estatico" \
   "grep -q 'static inline struct page \*__page_cache_alloc(gfp_t gfp)' \"\$PM\"" \
   "ainda e um simbolo externo"
ok "o wrapper chama filemap_alloc_folio com ordem 0" \
   "grep -q 'return &filemap_alloc_folio(gfp, 0)->page;' \"\$PM\"" \
   "nao delega para filemap_alloc_folio"
ok "o wrapper tira o head, que e a page" \
   "grep -q 'static inline struct page \*__page_cache_alloc' \"\$PM\"" \
   "assinatura mudou"
ok "o simbolo antigo nao e mais exportado" \
   "[ \"\$(nc 'EXPORT_SYMBOL(__page_cache_alloc)' \"\$FL\")\" = 0 ]" \
   "ainda exporta o nome antigo"
ok "page_cache_alloc continua usando o wrapper" \
   "grep -q 'return __page_cache_alloc(mapping_gfp_mask(x));' \"\$PM\"" \
   "page_cache_alloc mudou"
ok "os dois callers de filemap.c seguem compilando" \
   "[ \"\$(nc '__page_cache_alloc(' \"\$FL\")\" = 2 ]" \
   "esperava os 2 usos em filemap.c"
if [ -f "$KERNEL_DIR/fs/cachefiles/rdwr.c" ]; then
    ok "os 2 callers de cachefiles seguem compilando" \
       "[ \"\$(nc '__page_cache_alloc(' \"\$KERNEL_DIR/fs/cachefiles/rdwr.c\")\" = 2 ]" \
       "esperava os 2 usos em cachefiles"
fi

# --- a mascara nova nao muda a alocacao de ordem 0 --------------------
ok "o page allocator so prepara composto com order != 0" \
   "grep -q 'if (order && (gfp_flags & __GFP_COMP))' \"\$PA\"" \
   "a guarda de ordem mudou; conferir se __GFP_COMP virou ativo em ordem 0"
ok "___GFP_COMP nao colide com bit de zona" \
   "grep -q '#define ___GFP_COMP[[:space:]]*0x4000u' \"\$GFP\"" \
   "___GFP_COMP mudou de valor"
ok "___GFP_DMA segue em 0x01" \
   "grep -q '#define ___GFP_DMA[[:space:]]*0x01u' \"\$GFP\"" "bit de zona mudou"
ok "___GFP_HIGHMEM segue em 0x02" \
   "grep -q '#define ___GFP_HIGHMEM[[:space:]]*0x02u' \"\$GFP\"" "bit de zona mudou"
ok "___GFP_DMA32 segue em 0x04" \
   "grep -q '#define ___GFP_DMA32[[:space:]]*0x04u' \"\$GFP\"" "bit de zona mudou"
ok "___GFP_MOVABLE segue em 0x08" \
   "grep -q '#define ___GFP_MOVABLE[[:space:]]*0x08u' \"\$GFP\"" "bit de zona mudou"
ok "nenhum alocador de folio novo foi inventado" \
   "[ \"\$(nc 'alloc_pages_compound' \"\$PA\")\" = 0 ]" \
   "introduziu uma via de alocacao que o E404 nao tem"

# --- invariantes dos estagios anteriores -----------------------------
ok "o page lock do G2.3f segue inteiro" \
   "grep -q 'folio_waitqueue' \"\$FL\"" "a waitqueue sumiu"
ok "end_page_writeback do G2.4a segue inteiro" \
   "grep -q '^void end_page_writeback' \"\$FL\"" "sumiu"
ok "__folio_end_writeback do G2.4a segue inteiro" \
   "grep -q '__folio_end_writeback(folio)' \"\$FL\"" "sumiu"
ok "workingset_refault do G2.4b segue por folio" \
   "grep -q 'workingset_refault(page_folio(page), shadow);' \"\$FL\"" "voltou a passar struct page *"
ok "o alocador de page continua intacto" \
   "grep -q '^__alloc_pages(gfp_t gfp_mask, unsigned int order, int preferred_nid)$' \"\$GFP\"" \
   "__alloc_pages() foi mexido"

echo "G2.5a: todas as verificacoes passaram."
