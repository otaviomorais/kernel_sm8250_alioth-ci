#!/usr/bin/env bash
# Verificacao do G3d (upstream 30/90, 36/90, 81/90 e 82/90).
# Rodada separadamente do apply para que o log do CI aponte a assercao exata.
set -euo pipefail

KERNEL_DIR="${1:-}"
[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"

MH="$KERNEL_DIR/include/linux/mm.h"
MT="$KERNEL_DIR/include/linux/mm_types.h"
PM="$KERNEL_DIR/include/linux/pagemap.h"
SH="$KERNEL_DIR/include/linux/swap.h"
SC="$KERNEL_DIR/mm/swap.c"
VC="$KERNEL_DIR/mm/vmscan.c"
UC="$KERNEL_DIR/mm/util.c"

for f in "$MH" "$MT" "$PM" "$SH" "$SC" "$VC" "$UC"; do
    [ -f "$f" ] || { echo "FATAL: $f ausente" >&2; exit 1; }
done

n() { grep -c "$1" "$2" || true; }
nc() { grep -v '^[[:space:]]*\*' "$2" | grep -c "$1" || true; }
ncd() { grep -v -e '^[[:space:]]*\*' -e '/\*' -e '\*/' "$2" | grep -c "$1" || true; }
fn() { awk -v sig="$2" 'index($0, sig) { inb=1 } inb { print } inb && /^[}]$/ { exit }' "$1"; }
ok() { if eval "$2"; then echo "  ok   $1"; else echo "  FALHA $1 -> $3" >&2; exit 1; fi; }

echo "Validando o G3d..."

# --- 81/90: folio_evictable() -----------------------------------------
ok "folio_evictable declarado em swap.h" \
   "grep -q '^bool folio_evictable(struct folio \*folio);\$' \"\$SH\"" \
   "declaracao de folio_evictable ausente em swap.h"
ok "page_evictable e inline wrapper em swap.h" \
   "grep -A3 '^static inline bool page_evictable(struct page \*page)\$' \"\$SH\" | grep -q 'return folio_evictable(page_folio(page));'" \
   "page_evictable nao delega para folio_evictable"
ok "corpo de folio_evictable em vmscan.c" \
   "grep -q '^bool folio_evictable(struct folio \*folio)\$' \"\$VC\"" \
   "corpo de folio_evictable ausente em vmscan.c"
ok "folio_evictable checa folio_mapping" \
   "grep -A10 '^bool folio_evictable' \"\$VC\" | grep -q 'mapping_unevictable(folio_mapping(folio))'" \
   "nao checou mapping_unevictable com folio_mapping"
ok "folio_evictable checa folio_test_mlocked" \
   "grep -A10 '^bool folio_evictable' \"\$VC\" | grep -q '!folio_test_mlocked(folio)'" \
   "nao checou folio_test_mlocked"
ok "page_evictable nao tem definicao de funcao em vmscan.c" \
   "[ \"\$(ncd '^int page_evictable' \"\$VC\")\" = 0 ]" \
   "antiga definicao de page_evictable ainda existe em vmscan.c"

# --- 82/90: __folio_lru_add_fn() --------------------------------------
ok "corpo de __folio_lru_add_fn em swap.c" \
   "grep -q '^static void __folio_lru_add_fn(struct folio \*folio, struct lruvec \*lruvec)\$' \"\$SC\"" \
   "__folio_lru_add_fn ausente em swap.c"
ok "__folio_lru_add_fn checa folio_evictable" \
   "grep -A60 '^static void __folio_lru_add_fn' \"\$SC\" | grep -q 'if (folio_evictable(folio))'" \
   "nao usou folio_evictable"
ok "__folio_lru_add_fn usa folio_lru_list" \
   "grep -A60 '^static void __folio_lru_add_fn' \"\$SC\" | grep -q 'lru = folio_lru_list(folio);'" \
   "nao usou folio_lru_list"
ok "__folio_lru_add_fn adiciona com add_page_to_lru_list" \
   "grep -A60 '^static void __folio_lru_add_fn' \"\$SC\" | grep -q 'add_page_to_lru_list(&folio->page, lruvec, lru);'" \
   "nao adicionou &folio->page ao LRU"
ok "__folio_lru_add_fn preserva trace_mm_lru_insertion" \
   "grep -A60 '^static void __folio_lru_add_fn' \"\$SC\" | grep -q 'trace_mm_lru_insertion(&folio->page, lru);'" \
   "trace_mm_lru_insertion ausente"
ok "__pagevec_lru_add_fn e wrapper delegando a __folio_lru_add_fn" \
   "grep -A4 '^static void __pagevec_lru_add_fn' \"\$SC\" | grep -q '__folio_lru_add_fn(page_folio(page), lruvec);'" \
   "__pagevec_lru_add_fn nao delega para __folio_lru_add_fn"

# --- 30/90: folio_pgoff() ---------------------------------------------
ok "folio_pgoff e static inline em pagemap.h" \
   "grep -q '^static inline pgoff_t folio_pgoff(struct folio \*folio)\$' \"\$PM\"" \
   "folio_pgoff ausente em pagemap.h"
ok "folio_pgoff trata hugetlb" \
   "grep -A4 '^static inline pgoff_t folio_pgoff' \"\$PM\" | grep -q 'return hugetlb_basepage_index(&folio->page);'" \
   "folio_pgoff nao tratou hugetlb"
ok "folio_pgoff devolve folio->index" \
   "grep -A5 '^static inline pgoff_t folio_pgoff' \"\$PM\" | grep -q 'return folio->index;'" \
   "folio_pgoff nao devolveu folio->index"

# --- 36/90: folio_estimated_sharers() ---------------------------------
ok "folio_estimated_sharers e static inline em mm.h" \
   "grep -q '^static inline int folio_estimated_sharers(struct folio \*folio)\$' \"\$MH\"" \
   "folio_estimated_sharers ausente em mm.h"
ok "folio_estimated_sharers usa page_mapcount" \
   "grep -A3 '^static inline int folio_estimated_sharers' \"\$MH\" | grep -q 'return page_mapcount(&folio->page);'" \
   "folio_estimated_sharers nao usou page_mapcount(&folio->page)"

# --- O que nao podia ter vindo ---------------------------------------
ok "mm/folio-compat.c nao foi criado" \
   "[ ! -e \"\$KERNEL_DIR/mm/folio-compat.c\" ]" \
   "mm/folio-compat.c nao deve existir"

# --- Invariantes dos estagios anteriores ------------------------------
ok "folio_mapped do G3c segue em mm/util.c" \
   "grep -q '^bool folio_mapped(struct folio \*folio)\$' \"\$UC\"" "sumiu"
ok "folio_activate do G3c segue em mm/swap.c" \
   "grep -q '^void folio_activate(struct folio \*folio)\$' \"\$SC\"" "sumiu"
ok "folio_nid do G3c segue em mm.h" \
   "grep -q '^static inline int folio_nid(const struct folio \*folio)\$' \"\$MH\"" "sumiu"

echo "G3d: todas as verificacoes passaram."
