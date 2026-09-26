#!/usr/bin/env bash
# Verificacao do G2.4a (__folio_end_writeback, upstream patch 66/90).
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
PB="$KERNEL_DIR/mm/page-writeback.c"
INT="$KERNEL_DIR/mm/internal.h"
PF="$KERNEL_DIR/include/linux/page-flags.h"
MC="$KERNEL_DIR/include/linux/memcontrol.h"

for f in "$F" "$PB" "$INT" "$PF" "$MC"; do
    [ -f "$f" ] || { echo "FATAL: $f ausente" >&2; exit 1; }
done

# n() conta linhas que casam, como grep -c.
n() { grep -c "$1" "$2" || true; }
# nc() e o mesmo, ignorando linhas de comentario de bloco (" * ...").  Necessario
# porque os comentarios deste patch citam os simbolos que ele nao introduz.
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

echo "Validando o G2.4a..."

# O corpo da funcao e o que as assercoes de forma realmente medem.
BODY="$(fn "$PB" 'bool __folio_end_writeback(struct folio *folio)')"
ok "corpo de __folio_end_writeback extraido" \
   "grep -q 'folio_test_clear_writeback' <<< \"\$BODY\"" \
   "nao achei o corpo da funcao"

# --- a funcao foi movida, renomeada e retipada -------------------------
ok "__folio_end_writeback definida uma vez" \
   "[ \"\$(n '^bool __folio_end_writeback(struct folio \*folio)\$' \"\$PB\")\" = 1 ]" \
   "esperava 1 definicao com assinatura (struct folio *) -> bool"
ok "__folio_end_writeback usa folio_mapping" \
   "grep -q 'struct address_space \*mapping = folio_mapping(folio);' <<< \"\$BODY\"" \
   "ainda deriva o mapping da page"
ok "o retorno e bool" \
   "grep -q 'bool ret;' <<< \"\$BODY\"" \
   "declara int ret"
ok "a funcao nao declara mais int ret" \
   "! grep -q 'int ret;' <<< \"\$BODY\"" \
   "ainda ha int ret no corpo"
ok "o bit de writeback e testado no folio, nos dois ramos" \
   "[ \"\$(grep -c 'folio_test_clear_writeback(folio)' <<< \"\$BODY\")\" = 2 ]" \
   "esperava 2 usos (ramo com tags e ramo sem tags)"
ok "nenhum TestClearPageWriteback sobrou na funcao" \
   "! grep -q 'TestClearPageWriteback' <<< \"\$BODY\"" \
   "ainda usa o teste de page"
ok "a marca do xarray usa folio_index" \
   "grep -q '__xa_clear_mark(&mapping->i_pages, folio_index(folio)' <<< \"\$BODY\"" \
   "ainda usa page_index()"
ok "nenhum page_index sobrou na funcao" \
   "! grep -q 'page_index(' <<< \"\$BODY\"" \
   "page_index sobrou no corpo"
ok "a funcao nao chama page_mapping" \
   "! grep -q 'page_mapping(' <<< \"\$BODY\"" \
   "ainda usa page_mapping()"
ok "a funcao nao chama lock_page_memcg direto" \
   "! grep -q 'lock_page_memcg' <<< \"\$BODY\"" \
   "ainda trava o memcg pela page"

# --- a declaracao foi movida para mm/internal.h -----------------------
ok "declarada em mm/internal.h" \
   "grep -q '^bool __folio_end_writeback(struct folio \*folio);' \"\$INT\"" \
   "declaracao ausente em mm/internal.h"
ok "page-flags.h nao declara mais" \
   "[ \"\$(nc 'test_clear_page_writeback' \"\$PF\")\" = 0 ]" \
   "ainda declarada em include/linux/page-flags.h"
ok "nenhum caller do nome antigo" \
   "[ \"\$(nc 'test_clear_page_writeback(' \"\$F\")\" = 0 ]" \
   "filemap.c ainda chama o nome antigo"
ok "end_page_writeback resolve o folio" \
   "grep -q '__folio_end_writeback(page_folio(page))' \"\$F\"" \
   "o caminho de page nao normaliza"
ok "folio_end_writeback passa o folio direto" \
   "grep -q 'if (!__folio_end_writeback(folio))' \"\$F\"" \
   "o caminho de folio nao usa o proprio folio"
ok "os dois caminhos de fim de writeback seguem de pe" \
   "[ \"\$(n '^void end_page_writeback' \"\$F\")\" = 1 ]" \
   "end_page_writeback sumiu"
ok "EXPORT_SYMBOL de end_page_writeback mantido" \
   "[ \"\$(ncd 'EXPORT_SYMBOL(end_page_writeback);' \"\$F\")\" = 1 ]" \
   "simbolo exportado sumiu"

# --- helpers de folio memcg, nos dois ramos do Kconfig -----------------
# O ^ e obrigario: "unlock_page_memcg(&folio->page);" contem
# "lock_page_memcg(&folio->page);" como substring.
ok "folio_memcg_lock delega para lock_page_memcg" \
   "[ \"\$(n '^[[:space:]]*lock_page_memcg(&folio->page);\$' \"\$MC\")\" = 1 ]" \
   "wrapper nao delega"
ok "folio_memcg_unlock delega para unlock_page_memcg" \
   "[ \"\$(n '^[[:space:]]*unlock_page_memcg(&folio->page);\$' \"\$MC\")\" = 1 ]" \
   "wrapper nao delega"
ok "os dois helpers existem nos dois ramos do Kconfig" \
   "[ \"\$(n 'static inline void folio_memcg_lock' \"\$MC\")\" = 2 ]" \
   "falta o ramo sem CONFIG_MEMCG"
ok "os dois helpers de unlock existem nos dois ramos" \
   "[ \"\$(n 'static inline void folio_memcg_unlock' \"\$MC\")\" = 2 ]" \
   "falta o ramo sem CONFIG_MEMCG"
ok "a funcao trava o memcg pelo folio" \
   "grep -q 'folio_memcg_lock(folio);' <<< \"\$BODY\"" \
   "nao trava pelo folio"
ok "a funcao destrava pelo folio" \
   "grep -q 'folio_memcg_unlock(folio);' <<< \"\$BODY\"" \
   "nao destrava pelo folio"

# --- a forma do E404 foi preservada ------------------------------------
ok "lruvec continua derivado da page, com pgdat" \
   "grep -q 'mem_cgroup_page_lruvec(&folio->page, page_pgdat(&folio->page));' <<< \"\$BODY\"" \
   "a chamada de lruvec mudou de forma"
ok "teste de capacidade de writeback do E404 mantido" \
   "grep -q 'bdi_cap_account_writeback(bdi)' <<< \"\$BODY\"" \
   "substituido por BDI_CAP_WRITEBACK_ACCT"
ok "sb_clear_inode_writeback mantido" \
   "grep -q 'sb_clear_inode_writeback(mapping->host);' <<< \"\$BODY\"" \
   "substituido por wb_inode_writeback_end()"
ok "contagem de writeback por pagina mantida" \
   "grep -q 'dec_wb_stat(wb, WB_WRITEBACK);' <<< \"\$BODY\"" \
   "contagem virou wb_stat_mod()"
ok "as tres contagens de vmstat seguem por pagina" \
   "grep -q 'dec_lruvec_state(lruvec, NR_WRITEBACK);' <<< \"\$BODY\"" \
   "virou lruvec_stat_mod_folio()"
ok "__wb_writeout_inc segue em uso" \
   "grep -q '__wb_writeout_inc(wb);' <<< \"\$BODY\"" \
   "virou __wb_writeout_add()"

# --- a generalizacao por nr_pages ficou adiada, de proposito ----------
# nc() ignora os comentarios do proprio patch, que citam esses nomes para
# explicar por que eles nao foram introduzidos.
ok "wb_stat_mod nao foi inventado" \
   "[ \"\$(nc 'wb_stat_mod' \"\$PB\")\" = 0 ]" \
   "introduziu stat_mod sem a familia de vmstat do upstream"
ok "__wb_writeout_add nao foi inventado" \
   "[ \"\$(nc '__wb_writeout_add' \"\$PB\")\" = 0 ]" \
   "generalizou a contagem sem __fprop_add_percpu_max()"
ok "nenhum stat_mod_folio foi inventado" \
   "[ \"\$(nc 'stat_mod_folio' \"\$PB\")\" = 0 ]" \
   "introduziu sem a familia de vmstat do upstream"

# --- invariante do G2.3f: o page lock continua completo ---------------
for sym in wait_on_page_bit wait_on_page_bit_killable put_and_wait_on_page_locked \
           __lock_page __lock_page_killable unlock_page \
           end_page_writeback wake_up_page_bit wake_up_page \
           folio_add_wait_queue folio_waitqueue; do
    ok "$sym intacto" "grep -q '$sym' \"\$F\"" "simbolo ausente"
done

echo "G2.4a: todas as verificacoes passaram."
