#!/usr/bin/env bash
# Verificacao do G2.5f (upstream patch 90/90: folio_write_one).
# Rodada separadamente do apply para que o log do CI aponte a assercao exata.
#
# O `|| true` em n()/nc()/ncd() e obrigatorio: com `set -o pipefail`, um grep
# sem casamento faz o pipeline inteiro devolver 1 e o script morre ali em vez
# de comparar a contagem com 0.
set -euo pipefail

KERNEL_DIR="${1:-}"
[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"

PW="$KERNEL_DIR/mm/page-writeback.c"
PM="$KERNEL_DIR/include/linux/pagemap.h"
MM="$KERNEL_DIR/include/linux/mm.h"
PF="$KERNEL_DIR/include/linux/page-flags.h"

for f in "$PW" "$PM" "$MM" "$PF"; do
    [ -f "$f" ] || { echo "FATAL: $f ausente" >&2; exit 1; }
done

n() { grep -c "$1" "$2" || true; }
nc() { grep -v '^[[:space:]]*\*' "$2" | grep -c "$1" || true; }
# ncd() = "nao comentario".  nc() so descarta a linha de CONTINUACAO de um
# comentario de bloco; a linha que abre e fecha o comentario na mesma linha
# passa por ela, porque comeca com '/'.  Comentar um EXPORT_SYMBOL com
# /* ... */ na propria linha enganava o nc().  ncd() descarta tambem qualquer
# linha que contenha /* ou */.
ncd() { grep -v -e '^[[:space:]]*\*' -e '/\*' -e '\*/' "$2" | grep -c "$1" || true; }
# fn() extrai o corpo de uma funcao, ate a chave de abertura no nivel 0.
# A assinatura passada tem de ser mais especifica que a linha do comentario
# kdoc, senao awk casa na documentacao e devolve o bloco errado.
fn() { awk -v sig="$2" 'index($0, sig) { inb=1 } inb { print } inb && /^[}]$/ { exit }' "$1"; }
ok() { if eval "$2"; then echo "  ok   $1"; else echo "  FALHA $1 -> $3" >&2; exit 1; fi; }

echo "Validando o G2.5f..."

FWO="$(fn "$PW" 'int folio_write_one(struct folio *folio)')"
WOP="$(fn "$PW" 'int __must_check write_one_page(struct page *page)')"
FCD="$(fn "$PW" 'int folio_clear_dirty_for_io(struct folio *folio)')"
CPD="$(fn "$PW" 'int clear_page_dirty_for_io(struct page *page)')"

ok "corpo de folio_write_one extraido" \
   "grep -q 'folio_clear_dirty_for_io(folio)' <<< \"\$FWO\"" "nao achei o corpo"
ok "corpo de write_one_page extraido" \
   "grep -q 'folio_write_one(page_folio(page));' <<< \"\$WOP\"" "nao achei o wrapper"
ok "corpo de folio_clear_dirty_for_io extraido" \
   "grep -q 'folio_test_clear_dirty(folio)' <<< \"\$FCD\"" "nao achei o corpo"
ok "corpo de clear_page_dirty_for_io extraido" \
   "grep -q 'folio_clear_dirty_for_io(page_folio(page));' <<< \"\$CPD\"" "o wrapper nao delega"

# --- folio_write_one: a funcao convertida -----------------------------
ok "folio_write_one devolve int" \
   "grep -q '^int folio_write_one(struct folio \*folio)\$' \"\$PW\"" "a assinatura mudou"
ok "folio_write_one esta exportada" \
   "[ \"\$(ncd 'EXPORT_SYMBOL(folio_write_one);' \"\$PW\")\" = 1 ]" "perdeu o export"
ok "o mapping vem do folio" \
   "grep -q 'struct address_space \*mapping = folio->mapping;' <<< \"\$FWO\"" \
   "ainda le o mapping da page"
ok "nr_to_write vira a contagem de paginas do folio" \
   "grep -q '\.nr_to_write = folio_nr_pages(folio),' <<< \"\$FWO\"" \
   "ainda escreve 1"
ok "o BUG_ON testa o lock do folio" \
   "grep -q 'BUG_ON(!folio_test_locked(folio));' <<< \"\$FWO\"" "ainda em PageLocked()"
ok "a espera antes de escrever usa o folio" \
   "[ \"\$(grep -c 'folio_wait_writeback(folio);' <<< \"\$FWO\")\" = 2 ]" \
   "sao duas esperas: antes do dirty e depois do writepage"
ok "o dirty e limpo no folio" \
   "grep -q 'if (folio_clear_dirty_for_io(folio)) {' <<< \"\$FWO\"" \
   "ainda em clear_page_dirty_for_io(page)"
ok "a referencia e pega e solta pelo folio" \
   "grep -q 'folio_get(folio);' <<< \"\$FWO\" && grep -q 'folio_put(folio);' <<< \"\$FWO\"" \
   "ainda em get_page()/put_page()"
ok "o writepage recebe a head page, como o E404 exige" \
   "grep -q 'ret = mapping->a_ops->writepage(&folio->page, &wbc);' <<< \"\$FWO\"" \
   "o ponteiro de funcao ainda toma struct page *; tem de ser &folio->page"
ok "o caminho sem dirty destrava o folio" \
   "grep -q 'folio_unlock(folio);' <<< \"\$FWO\"" "ainda em unlock_page()"
ok "os erros do mapping continuam sendo checados" \
   "grep -q 'ret = filemap_check_errors(mapping);' <<< \"\$FWO\"" "a checagem de erro sumiu"
ok "o corpo nao volta a compound_head" \
   "[ \"\$(grep -c 'compound_head' <<< \"\$FWO\")\" = 0 ]" "ainda resolve compound_head()"
ok "o corpo nao chama page_folio" \
   "[ \"\$(grep -c 'page_folio' <<< \"\$FWO\")\" = 0 ]" "a funcao ja tem o folio"

# --- o wrapper write_one_page, e por que ele fica --------------------
# Nove callers in-tree, um deles o driver block2mtd, e cinco deles nao incluem
# linux/pagemap.h.  Verificar isso por contagem e o que mantem a declaracao em
# mm.h; o patch do upstream move para pagemap.h e nao compilaria aqui.
ok "write_one_page continua sendo funcao real" \
   "grep -q '^int __must_check write_one_page(struct page \*page)\$' \"\$PW\"" \
   "virou static inline e os 9 callers in-tree quebram"
ok "write_one_page continua exportada" \
   "[ \"\$(ncd 'EXPORT_SYMBOL(write_one_page);' \"\$PW\")\" = 1 ]" \
   "o block2mtd e os filesystems chamam esse simbolo"
ok "o wrapper so delega" \
   "[ \"\$(grep -c 'return folio_write_one(page_folio(page));' <<< \"\$WOP\")\" = 1 ]" \
   "o wrapper faz mais que delegar"
ok "o wrapper nao tem corpo proprio" \
   "[ \"\$(grep -cE '^[[:space:]]+[a-zA-Z]' <<< \"\$WOP\")\" = 1 ]" \
   "so a linha do return pode ter codigo"
ok "a declaracao de write_one_page continua em mm.h" \
   "grep -q '^int __must_check write_one_page(struct page \*page);\$' \"\$MM\"" \
   "mover para pagemap.h quebraria fs/jfs, fs/minix, fs/ufs, fs/exofs e fs/ocfs2, que nao incluem pagemap.h"
ok "a declaracao nao foi parar em pagemap.h" \
   "[ \"\$(ncd 'write_one_page' \"\$PM\")\" = 0 ]" "a declaracao foi movida"
ok "task_dirty_inc continua declarada em mm.h" \
   "grep -q '^void task_dirty_inc(struct task_struct \*tsk);\$' \"\$MM\"" \
   "o upstream remove essa linha porque o patch 75/90 ja a tinha movido, e o 75/90 nao esta aqui"
ok "o comentario mm/page-writeback.c continua em mm.h" \
   "grep -q '^/\* mm/page-writeback.c \*/\$' \"\$MM\"" "o comentario perdeu o par"

# --- folio_wait_writeback --------------------------------------------
ok "folio_wait_writeback e um static inline" \
   "grep -q '^static inline __sched void folio_wait_writeback(struct folio \*folio)\$' \"\$PM\"" \
   "nao e um inline"
ok "folio_wait_writeback tem o pre-check de writeback" \
   "grep -A3 '^static inline __sched void folio_wait_writeback' \"\$PM\" | grep -q 'if (folio_test_writeback(folio))'" \
   "sem o pre-check todo caller pega o lock da waitqueue a toa"
ok "folio_wait_writeback espera pelo bit do folio" \
   "grep -A4 '^static inline __sched void folio_wait_writeback' \"\$PM\" | grep -q 'folio_wait_bit(folio, PG_writeback);'" \
   "a espera mudou"
ok "folio_wait_writeback fica ao lado de wait_on_page_writeback" \
   "[ \"\$(grep -n 'void folio_wait_writeback' \"\$PM\" | cut -d: -f1)\" \
      -lt \"\$(grep -n 'void wait_on_page_writeback' \"\$PM\" | head -1 | cut -d: -f1)\" ]" \
   "os dois helpers de espera de writeback ficam juntos"
ok "wait_on_page_writeback ficou intacto" \
   "grep -A3 '^static inline __sched void wait_on_page_writeback' \"\$PM\" | grep -q 'wait_on_page_bit(page, PG_writeback);'" \
   "o caminho de page mudou"
ok "folio_write_one foi declarada em pagemap.h" \
   "grep -q '^int __must_check folio_write_one(struct folio \*folio);\$' \"\$PM\"" \
   "falta a declaracao"
ok "folio_wait_bit do G2.3f segue declarado" \
   "grep -q '^void __sched folio_wait_bit(struct folio \*folio, int bit_nr);\$' \"\$PM\"" "sumiu"

# --- folio_clear_dirty_for_io: parte do patch 74/90 -------------------
ok "folio_clear_dirty_for_io devolve int" \
   "grep -q '^int folio_clear_dirty_for_io(struct folio \*folio)\$' \"\$PW\"" \
   "a assinatura mudou; E404 usa int, nao bool"
ok "folio_clear_dirty_for_io esta exportada" \
   "[ \"\$(ncd 'EXPORT_SYMBOL(folio_clear_dirty_for_io);' \"\$PW\")\" = 1 ]" "perdeu o export"
ok "o mapping vem do folio" \
   "grep -q 'struct address_space \*mapping = folio_mapping(folio);' <<< \"\$FCD\"" \
   "ainda em page_mapping(page)"
ok "o BUG_ON testa o lock do folio" \
   "grep -q 'BUG_ON(!folio_test_locked(folio));' <<< \"\$FCD\"" "ainda em PageLocked()"
ok "o teste de mapeco sujo usa o nome do E404" \
   "grep -q 'mapping_cap_account_dirty(mapping)' <<< \"\$FCD\"" \
   "veio mapping_can_writeback() do 5.16"
ok "o dirty e testado e limpo no folio" \
   "grep -q 'if (folio_test_clear_dirty(folio)) {' <<< \"\$FCD\"" \
   "ainda em TestClearPageDirty(page)"
ok "o retorno sem mapeco sujo e o do folio" \
   "grep -q 'return folio_test_clear_dirty(folio);' <<< \"\$FCD\"" \
   "o retorno final nao foi convertido"
ok "folio_test_clear_dirty vem do macro, nao foi escrito a mao" \
   "grep -q 'TESTSCFLAG(Dirty, dirty, PF_HEAD)' \"\$PF\"" \
   "o gerador do bit de dirty mudou"
ok "folio_mark_dirty nao foi usado" \
   "[ \"\$(grep -c 'folio_mark_dirty' <<< \"\$FCD\")\" = 0 ]" \
   "o 5.16 usa folio_mark_dirty(); em E404 ele nao existe"
ok "folio_set_dirty nao substituiu set_page_dirty" \
   "[ \"\$(grep -c 'folio_set_dirty' <<< \"\$FCD\")\" = 0 ]" \
   "folio_set_dirty() e um set_bit() cru e perderia os efeitos colaterais"
ok "set_page_dirty continua recebendo a head page" \
   "grep -q 'set_page_dirty(&folio->page);' <<< \"\$FCD\"" \
   "a funcao do E404 e que tem os efeitos colaterais que a chamada precisa"
ok "page_mkclean continua recebendo a head page" \
   "grep -q 'if (page_mkclean(&folio->page))' <<< \"\$FCD\"" "o page_mkclean sumiu"
ok "o accounting de lruvec usa o nome do E404" \
   "grep -q 'dec_lruvec_page_state(&folio->page, NR_FILE_DIRTY);' <<< \"\$FCD\"" \
   "dec_lruvec_page_state() e o nome do E404 e toma struct page *"
ok "dec_lruvec_state nao foi usada por engano" \
   "[ \"\$(grep -c 'dec_lruvec_state' <<< \"\$FCD\")\" = 0 ]" \
   "dec_lruvec_state() do E404 toma struct lruvec *, nao struct page *"
ok "o accounting de zona usa o nome do E404" \
   "grep -q 'dec_zone_page_state(&folio->page, NR_ZONE_WRITE_PENDING);' <<< \"\$FCD\"" \
   "dec_zone_folio_state() nao existe nesta arvore"
ok "o lock de writeback do wb foi mantido" \
   "grep -q 'unlocked_inode_to_wb_begin(inode, &cookie);' <<< \"\$FCD\" && \
    grep -q 'unlocked_inode_to_wb_end(inode, &cookie);' <<< \"\$FCD\"" \
   "o par de lock do wb mudou"
ok "a estatistica de writeback foi mantida" \
   "grep -q 'dec_wb_stat(wb, WB_RECLAIMABLE);' <<< \"\$FCD\"" "a estatistica sumiu"

# --- o wrapper clear_page_dirty_for_io -------------------------------
ok "clear_page_dirty_for_io continua sendo funcao real" \
   "grep -q '^int clear_page_dirty_for_io(struct page \*page)\$' \"\$PW\"" \
   "a assinatura mudou; E404 e o 5.16 nao concordam aqui"
ok "clear_page_dirty_for_io continua exportada" \
   "[ \"\$(ncd 'EXPORT_SYMBOL(clear_page_dirty_for_io);' \"\$PW\")\" = 1 ]" "perdeu o export"
ok "o wrapper so delega" \
   "[ \"\$(grep -c 'return folio_clear_dirty_for_io(page_folio(page));' <<< \"\$CPD\")\" = 1 ]" \
   "o wrapper faz mais que delegar"
ok "a declaracao de page ficou em mm.h" \
   "grep -q '^int clear_page_dirty_for_io(struct page \*page);\$' \"\$MM\"" "a declaracao antiga sumiu"
ok "a declaracao de folio ficou ao lado, em mm.h" \
   "grep -q '^int folio_clear_dirty_for_io(struct folio \*folio);\$' \"\$MM\"" \
   "falta a declaracao"
# As duas declaracoes foram inseridas lado a lado, com a do folio primeiro.
# A conta e folio == page - 1, nao page + 1.
ok "as duas declaracoes de mm.h sao vizinhas" \
   "[ \"\$(grep -n '^int folio_clear_dirty_for_io' \"\$MM\" | cut -d: -f1)\" \
      -eq \"\$((\$(grep -n '^int clear_page_dirty_for_io' \"\$MM\" | cut -d: -f1 | head -1) - 1))\" ]" \
   "as duas versoes ficam lado a lado"
ok "a declaracao nao foi parar em pagemap.h" \
   "[ \"\$(ncd 'clear_page_dirty_for_io' \"\$PM\")\" = 0 ]" "a declaracao foi movida"

# --- nada de 5.16 foi inventado aqui ---------------------------------
ok "mm/folio-compat.c nao foi criado" \
   "[ ! -e \"\$KERNEL_DIR/mm/folio-compat.c\" ]" \
   "a serie e aditiva; esse arquivo nao deve existir"
ok "mm/Makefile nao ganhou entrada nova" \
   "[ ! -e \"\$KERNEL_DIR/mm/Makefile\" ] || [ \"\$(ncd 'folio-compat' \"\$KERNEL_DIR/mm/Makefile\")\" = 0 ]" \
   "mm/Makefile foi mexido"
ok "nenhum helper de folio_account_redirty do 75/90 foi importado" \
   "[ \"\$(ncd 'folio_account_redirty' \"\$PW\")\" = 0 ]" \
   "o 75/90 nao faz parte deste backport"
ok "nenhum helper de vmstat do upstream foi importado" \
   "[ \"\$(ncd 'lruvec_stat_add_folio\|__fprop_add_percpu_max\|wb_stat_mod' \"\$PW\")\" = 0 ]" \
   "a familia de vmstat do 5.16 continua de fora"

# --- invariantes dos estagios anteriores -----------------------------
ok "FGP_STABLE do G2.5e segue inteiro" \
   "grep -q '^#define FGP_STABLE[[:space:]]*0x00000200\$' \"\$PM\"" "sumiu"
ok "grab_cache_page_write_begin do G2.5e segue usando pagecache_get_page" \
   "grep -q 'return pagecache_get_page(mapping, index, fgp_flags,' \"\$KERNEL_DIR/mm/filemap.c\"" "mudou"
ok "folio_wait_stable do G2.5e segue existindo" \
   "grep -q '^void folio_wait_stable(struct folio \*folio)\$' \"\$PW\"" "sumiu"
ok "folio_wait_stable nao passou a depender de folio_wait_writeback" \
   "[ \"\$(grep -A5 '^void folio_wait_stable' \"\$PW\" | grep -c 'folio_wait_writeback(folio);')\" = 0 ]" \
   "o G2.5e foi verificado com o pre-check escrito na mao; nao se mexe num estagio verde"
ok "folio_wait_stable continua com o pre-check escrito na mao" \
   "grep -A5 '^void folio_wait_stable' \"\$PW\" | grep -q 'folio_test_writeback(folio))'" \
   "o pre-check do G2.5e sumiu"
ok "__filemap_get_folio do G2.5d segue inteiro" \
   "grep -q '^struct folio \*__filemap_get_folio(struct address_space \*mapping, pgoff_t index,$' \"\$KERNEL_DIR/mm/filemap.c\"" "sumiu"
ok "folio_mark_accessed do G2.5d segue exportada" \
   "[ \"\$(ncd 'EXPORT_SYMBOL(folio_mark_accessed);' \"\$KERNEL_DIR/mm/swap.c\")\" = 1 ]" "sumiu"
ok "__folio_end_writeback do G2.4a segue inteiro" \
   "grep -q '^bool __folio_end_writeback(struct folio \*folio)\$' \"\$PW\"" "sumiu"
ok "o caminho de folio de end_writeback segue em filemap.c" \
   "grep -q 'if (!__folio_end_writeback(folio))' \"\$KERNEL_DIR/mm/filemap.c\"" "sumiu"
ok "end_page_writeback do G2.4a continua intacto" \
   "grep -q '__folio_end_writeback(page_folio(page))' \"\$KERNEL_DIR/mm/filemap.c\"" "mudou"
ok "filemap_add_folio do G2.5b segue inteiro" \
   "grep -q '^int filemap_add_folio(struct address_space \*mapping, struct folio \*folio,$' \"\$KERNEL_DIR/mm/filemap.c\"" "sumiu"
ok "folio_test_writeback vem do macro, nao foi escrito a mao" \
   "grep -q 'TESTPAGEFLAG(Writeback, writeback, PF_NO_TAIL)' \"\$PF\"" \
   "o gerador do bit de writeback mudou"

echo "G2.5f: todas as verificacoes passaram."
