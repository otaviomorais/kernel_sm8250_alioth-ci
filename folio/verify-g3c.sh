#!/usr/bin/env bash
# Verificacao do G3c (upstream 32/90, 33/90, 56/90 e 57/90).
# Rodada separadamente do apply para que o log do CI aponte a assercao exata.
set -euo pipefail

KERNEL_DIR="${1:-}"
[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"

MH="$KERNEL_DIR/include/linux/mm.h"
MT="$KERNEL_DIR/include/linux/mm_types.h"
PI="$KERNEL_DIR/include/linux/page_idle.h"
SH="$KERNEL_DIR/include/linux/swap.h"
SC="$KERNEL_DIR/mm/swap.c"
UC="$KERNEL_DIR/mm/util.c"
RC="$KERNEL_DIR/mm/rmap.c"
CF="$KERNEL_DIR/include/asm-generic/cacheflush.h"

for f in "$MH" "$MT" "$PI" "$SH" "$SC" "$UC" "$RC" "$CF"; do
    [ -f "$f" ] || { echo "FATAL: $f ausente" >&2; exit 1; }
done

n() { grep -c "$1" "$2" || true; }
nc() { grep -v '^[[:space:]]*\*' "$2" | grep -c "$1" || true; }
ncd() { grep -v -e '^[[:space:]]*\*' -e '/\*' -e '\*/' "$2" | grep -c "$1" || true; }
fn() { awk -v sig="$2" 'index($0, sig) { inb=1 } inb { print } inb && /^[}]$/ { exit }' "$1"; }
ok() { if eval "$2"; then echo "  ok   $1"; else echo "  FALHA $1 -> $3" >&2; exit 1; fi; }

echo "Validando o G3c..."

# --- 32/90: folio_mapped() --------------------------------------------
ok "folio_mapcount_ptr e um static inline" \
   "grep -q '^static inline atomic_t \*folio_mapcount_ptr(struct folio \*folio)\$' \"\$MT\"" \
   "nao existe em mm_types.h"
ok "folio_mapcount_ptr acessa compound_mapcount da subpagina tail" \
   "grep -A4 '^static inline atomic_t \*folio_mapcount_ptr' \"\$MT\" | grep -q 'return &tail->compound_mapcount;'" \
   "o corpo de folio_mapcount_ptr mudou"
ok "folio_mapped declarado em mm.h" \
   "grep -q '^bool folio_mapped(struct folio \*folio);\$' \"\$MH\"" \
   "falta a declaracao em mm.h"
ok "folio_mapped vizinho de page_mapped em mm.h" \
   "grep -A1 '^bool page_mapped(struct page \*page);\$' \"\$MH\" | grep -q 'bool folio_mapped(struct folio \*folio);'" \
   "declarado longe de page_mapped"
ok "corpo de folio_mapped em mm/util.c" \
   "grep -q '^bool folio_mapped(struct folio \*folio)\$' \"\$UC\"" \
   "falta o corpo em mm/util.c"
ok "folio_mapped trata folio_test_single" \
   "grep -A4 '^bool folio_mapped' \"\$UC\" | grep -q 'if (folio_test_single(folio))'" \
   "nao checou folio_test_single"
ok "folio_mapped checa folio_mapcount_ptr" \
   "grep -A7 '^bool folio_mapped' \"\$UC\" | grep -q 'if (atomic_read(folio_mapcount_ptr(folio)) >= 0)'" \
   "nao checou compound_mapcount"
ok "folio_mapped checa folio_test_hugetlb" \
   "grep -A10 '^bool folio_mapped' \"\$UC\" | grep -q 'if (folio_test_hugetlb(folio))'" \
   "nao checou hugetlb"
ok "folio_mapped itera com folio_nr_pages e folio_page" \
   "grep -A16 '^bool folio_mapped' \"\$UC\" | grep -q 'folio_page(folio, i)->_mapcount'" \
   "nao iterou subpaginas com folio_page"
ok "folio_mapped esta exportado" \
   "[ \"\$(ncd 'EXPORT_SYMBOL(folio_mapped);' \"\$UC\")\" = 1 ]" \
   "perdeu o EXPORT_SYMBOL de folio_mapped"
ok "page_mapped e wrapper chamando folio_mapped" \
   "grep -A4 '^bool page_mapped(struct page \*page)\$' \"\$UC\" | grep -q 'return folio_mapped(page_folio(page));'" \
   "page_mapped nao delega para folio_mapped"
ok "page_mapped continua exportado" \
   "[ \"\$(ncd 'EXPORT_SYMBOL(page_mapped);' \"\$UC\")\" = 1 ]" \
   "perdeu o EXPORT_SYMBOL de page_mapped"

# --- 33/90: folio_nid() -----------------------------------------------
ok "folio_nid e static inline em mm.h" \
   "grep -q '^static inline int folio_nid(const struct folio \*folio)\$' \"\$MH\"" \
   "folio_nid nao declarado em mm.h"
ok "folio_nid delega para page_to_nid" \
   "grep -A3 '^static inline int folio_nid' \"\$MH\" | grep -q 'return page_to_nid(&folio->page);'" \
   "o corpo de folio_nid mudou"

# --- 56/90: folio_young e folio_idle ----------------------------------
ok "folio_test_young definido em page_idle.h" \
   "grep -q 'static inline bool folio_test_young(struct folio \*folio)' \"\$PI\"" \
   "folio_test_young ausente"
ok "folio_set_young definido em page_idle.h" \
   "grep -q 'static inline void folio_set_young(struct folio \*folio)' \"\$PI\"" \
   "folio_set_young ausente"
ok "folio_test_clear_young definido em page_idle.h" \
   "grep -q 'static inline bool folio_test_clear_young(struct folio \*folio)' \"\$PI\"" \
   "folio_test_clear_young ausente"
ok "folio_test_idle definido em page_idle.h" \
   "grep -q 'static inline bool folio_test_idle(struct folio \*folio)' \"\$PI\"" \
   "folio_test_idle ausente"
ok "folio_set_idle definido em page_idle.h" \
   "grep -q 'static inline void folio_set_idle(struct folio \*folio)' \"\$PI\"" \
   "folio_set_idle ausente"
ok "folio_clear_idle definido em page_idle.h" \
   "grep -q 'static inline void folio_clear_idle(struct folio \*folio)' \"\$PI\"" \
   "folio_clear_idle ausente"
ok "page_is_young e wrapper chamando folio_test_young" \
   "grep -A3 '^static inline bool page_is_young(struct page \*page)\$' \"\$PI\" | grep -q 'return folio_test_young(page_folio(page));'" \
   "page_is_young nao delega para folio_test_young"
ok "set_page_young e wrapper chamando folio_set_young" \
   "grep -A3 '^static inline void set_page_young(struct page \*page)\$' \"\$PI\" | grep -q 'folio_set_young(page_folio(page));'" \
   "set_page_young nao delega"
ok "test_and_clear_page_young e wrapper chamando folio_test_clear_young" \
   "grep -A3 '^static inline bool test_and_clear_page_young(struct page \*page)\$' \"\$PI\" | grep -q 'return folio_test_clear_young(page_folio(page));'" \
   "test_and_clear_page_young nao delega"
ok "page_is_idle e wrapper chamando folio_test_idle" \
   "grep -A3 '^static inline bool page_is_idle(struct page \*page)\$' \"\$PI\" | grep -q 'return folio_test_idle(page_folio(page));'" \
   "page_is_idle nao delega para folio_test_idle"
ok "set_page_idle e wrapper chamando folio_set_idle" \
   "grep -A3 '^static inline void set_page_idle(struct page \*page)\$' \"\$PI\" | grep -q 'folio_set_idle(page_folio(page));'" \
   "set_page_idle nao delega"
ok "clear_page_idle e wrapper chamando folio_clear_idle" \
   "grep -A3 '^static inline void clear_page_idle(struct page \*page)\$' \"\$PI\" | grep -q 'folio_clear_idle(page_folio(page));'" \
   "clear_page_idle nao delega"
ok "CONFIG_IDLE_PAGE_TRACKING preservado" \
   "grep -q '#ifdef CONFIG_IDLE_PAGE_TRACKING' \"\$PI\" && [ \"\$(ncd 'CONFIG_PAGE_IDLE_FLAG' \"\$PI\")\" = 0 ]" \
   "macro CONFIG_IDLE_PAGE_TRACKING alterada ou CONFIG_PAGE_IDLE_FLAG introduzida"

# --- 57/90: folio_activate() ------------------------------------------
ok "folio_activate declarado em swap.h" \
   "grep -q '^void folio_activate(struct folio \*);\$' \"\$SH\"" \
   "declaracao de folio_activate ausente em swap.h"
ok "__folio_activate implementado em mm/swap.c" \
   "grep -q '^static void __folio_activate(struct folio \*folio, struct lruvec \*lruvec)\$' \"\$SC\"" \
   "__folio_activate ausente em mm/swap.c"
ok "__folio_activate atualiza reclaim_stat" \
   "grep -A16 '^static void __folio_activate' \"\$SC\" | grep -q 'update_page_reclaim_stat(lruvec, file, 1);'" \
   "reclaim_stat nao atualizado em __folio_activate"
ok "__activate_page delega para __folio_activate" \
   "grep -A4 '^static void __activate_page' \"\$SC\" | grep -q '__folio_activate(page_folio(page), lruvec);'" \
   "__activate_page nao delega para __folio_activate"
ok "folio_activate implementado para SMP em mm/swap.c" \
   "grep -q '^void folio_activate(struct folio \*folio)\$' \"\$SC\"" \
   "folio_activate ausente em mm/swap.c"
ok "folio_activate exportado" \
   "[ \"\$(ncd 'EXPORT_SYMBOL(folio_activate);' \"\$SC\")\" = 2 ]" \
   "esperava 2 exports de folio_activate (SMP e !SMP)"
ok "activate_page e wrapper chamando folio_activate" \
   "grep -A4 '^void activate_page(struct page \*page)\$' \"\$SC\" | grep -q 'folio_activate(page_folio(page));'" \
   "activate_page nao delega para folio_activate"
ok "activate_page exportado" \
   "[ \"\$(ncd 'EXPORT_SYMBOL(activate_page);' \"\$SC\")\" = 2 ]" \
   "esperava 2 exports de activate_page (SMP e !SMP)"

# --- O que nao podia ter vindo ---------------------------------------
ok "mm/folio-compat.c nao foi criado" \
   "[ ! -e \"\$KERNEL_DIR/mm/folio-compat.c\" ]" \
   "mm/folio-compat.c nao deve existir"

# --- Invariantes dos estagios anteriores ------------------------------
ok "folio_raw_mapping do G3b segue intacto em mm/util.c" \
   "grep -q '^static inline void \*folio_raw_mapping(struct folio \*folio)\$' \"\$UC\"" "sumiu"
ok "flush_dcache_folio do G3b segue no-op em cacheflush.h" \
   "grep -q '^static inline void flush_dcache_folio(struct folio \*folio) { }\$' \"\$CF\"" "sumiu"
ok "folio_mkclean do G3b segue exportado em rmap.c" \
   "grep -q '^int folio_mkclean(struct folio \*folio)\$' \"\$RC\"" "sumiu"
ok "folio_pfn do G3a segue em mm.h" \
   "grep -q '^static inline unsigned long folio_pfn(struct folio \*folio)\$' \"\$MH\"" "sumiu"
ok "folio_mark_accessed do G2.5d segue em mm/swap.c" \
   "grep -q 'void folio_mark_accessed(struct folio \*folio)' \"\$SC\"" "sumiu"

echo "G3c: todas as verificacoes passaram."
