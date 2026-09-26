#!/usr/bin/env bash
# Verificacao do G2.3f, rodada separadamente do apply para que o log do CI
# aponte a assercao exata que falhou.
#
# O `|| true` em n() e obrigatorio: com `set -o pipefail`, um grep sem
# casamento faz o pipeline inteiro devolver 1 e o script morre ali em vez
# de comparar a contagem com 0.
set -euo pipefail

KERNEL_DIR="${1:-}"
[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"

F="$KERNEL_DIR/mm/filemap.c"
H="$KERNEL_DIR/include/linux/pagemap.h"
RD="$KERNEL_DIR/fs/cachefiles/rdwr.c"

[ -f "$F" ] || { echo "FATAL: mm/filemap.c ausente" >&2; exit 1; }
[ -f "$H" ] || { echo "FATAL: include/linux/pagemap.h ausente" >&2; exit 1; }

n() { grep -c "$1" "$2" || true; }
# ncd() = "nao comentario", para as contagens que precisam valer.
#
# nc() so descarta a linha de CONTINUACAO de um comentario de bloco.  A linha
# que abre e fecha o comentario na mesma linha passa direto por ela, porque
# comeca com '/' e nao com '*'.  Comentar um EXPORT_SYMBOL com /* ... */ na
# propria linha fazia nc() continuar contando a linha, e a asercao passava
# numa arvore que ja nao tinha o simbolo.  ncd() descarta tambem qualquer linha
# que contenha /* ou */.
ncd() { grep -v -e '^[[:space:]]*\*' -e '/\*' -e '\*/' "$2" | grep -c "$1" || true; }

ok() { if eval "$2"; then echo "  ok   $1"; else echo "  FALHA $1 -> $3" >&2; exit 1; fi; }

echo "Validando o G2.3f..."

# --- a fila de espera passa a ser indexada por folio --------------------
ok "folio_wait_table definido" \
   "[ \"\$(n '^static wait_queue_head_t folio_wait_table' \"\$F\")\" = 1 ]" \
   "esperava 1 definicao"
ok "folio_waitqueue(struct folio *) definido" \
   "[ \"\$(n '^static wait_queue_head_t \*folio_waitqueue(struct folio \*folio)' \"\$F\")\" = 1 ]" \
   "esperava 1 definicao"
# O nome antigo sobrevive num comentario, entao a checagem e sobre a
# definicao e as chamadas, nao sobre o texto.
ok "sem definicao page_waitqueue" \
   "[ \"\$(n 'wait_queue_head_t \*page_waitqueue' \"\$F\")\" = 0 ]" \
   "page_waitqueue() ainda definido"
ok "sem chamada page_waitqueue" \
   "[ \"\$(n '= page_waitqueue(' \"\$F\")\" = 0 ]" \
   "ainda chamando page_waitqueue()"
ok "sem page_wait_table[" \
   "[ \"\$(n 'page_wait_table\[' \"\$F\")\" = 0 ]" \
   "ainda indexando page_wait_table"

# --- as duas estruturas carregam folio --------------------------------
for st in wait_page_key wait_page_queue; do
    blk="$(sed -n "/^struct $st {/,/^};/p" "$F")"
    ok "$st tem struct folio *folio" \
       "echo \"\$blk\" | grep -q 'struct folio \*folio;'" \
       "campo folio ausente"
    ok "$st sem struct page *page" \
       "! echo \"\$blk\" | grep -q 'struct page \*page;'" \
       "$st ainda declara struct page *page"
done
ok "nenhum resto da forma antiga" \
   "[ \"\$(n 'wait_page\.page\|wait_page->page\|key\.page =\|key->page ' \"\$F\")\" = 0 ]" \
   "sobrou wait_page.page / key.page"

# --- wake_page_function casa folio contra folio ------------------------
ok "wake_page_function compara folio" \
   "grep -q 'if (wait_page->folio != key->folio)' \"\$F\"" \
   "comparacao por struct page"
ok "wake_page_function testa o bit no folio" \
   "grep -q 'if (test_bit(key->bit_nr, &key->folio->flags))' \"\$F\"" \
   "test_bit ainda em key->page"

# --- simetria: quem acorda e quem espera resolvem o mesmo folio ---------
# Toda chamada a folio_waitqueue() cujo argumento e uma struct page tem de
# passar por page_folio(), senao waiter e waker caem em buckets diferentes
# do hash para o mesmo objeto.
ok "nenhuma chamada folio_waitqueue(&...)" \
   "[ \"\$(n 'folio_waitqueue(&' \"\$F\")\" = 0 ]" \
   "ainda passando &folio->page"
bad=0
while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
        *"static wait_queue_head_t *folio_waitqueue"*) continue ;;
    esac
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in
        '*'*|'//'*|'/*'*)                        continue ;;
        *"folio_waitqueue(folio)"*)           continue ;;
        *"folio_waitqueue(page_folio(page))"*) continue ;;
        *) bad=$((bad + 1)); echo "    nao normalizada: $line" >&2 ;;
    esac
done < <(grep 'folio_waitqueue(' "$F" || true)
ok "toda chamada de folio_waitqueue e normalizada" \
   "[ \"$bad\" = 0 ]" "$bad chamada(s) sem page_folio()"

ok "wake_up_page testa waiters via folio" \
   "[ \"\$(n 'if (!folio_test_waiters(page_folio(page)))' \"\$F\")\" = 1 ]" \
   "fast path ainda em PageWaiters(page)"
ok "folio_set_waiters presente" \
   "grep -q 'folio_set_waiters(folio);' \"\$F\"" "PG_waiters nao setado pelo folio"
ok "folio_clear_waiters presente" \
   "grep -q 'folio_clear_waiters(folio);' \"\$F\"" "PG_waiters nao limpo pelo folio"

# --- API nova existe, antiga continua como wrapper --------------------
ok "folio_add_wait_queue definido" \
   "[ \"\$(n '^void folio_add_wait_queue(struct folio \*folio, wait_queue_entry_t \*waiter)' \"\$F\")\" = 1 ]" \
   "esperava 1 definicao"
ok "folio_add_wait_queue exportado" \
   "[ \"\$(ncd 'EXPORT_SYMBOL_GPL(folio_add_wait_queue);' \"\$F\")\" = 1 ]" "sem EXPORT_SYMBOL_GPL"
ok "add_page_wait_queue definido" \
   "[ \"\$(n '^void add_page_wait_queue(struct page \*page, wait_queue_entry_t \*waiter)' \"\$F\")\" = 1 ]" \
   "esperava 1 definicao"
ok "add_page_wait_queue exportado" \
   "[ \"\$(ncd 'EXPORT_SYMBOL_GPL(add_page_wait_queue);' \"\$F\")\" = 1 ]" "sem EXPORT_SYMBOL_GPL"
ok "wrapper delega para o folio" \
   "grep -q 'folio_add_wait_queue(page_folio(page), waiter);' \"\$F\"" "wrapper nao delega"
ok "header declara folio_add_wait_queue" \
   "grep -q '^void folio_add_wait_queue(struct folio \*folio, wait_queue_entry_t \*waiter);' \"\$H\"" \
   "declaracao ausente"
ok "header preserva add_page_wait_queue" \
   "grep -q '^extern void add_page_wait_queue(struct page \*page, wait_queue_entry_t \*waiter);' \"\$H\"" \
   "declaracao ausente"

# --- o bit esperado e a referencia do DROP seguem em nivel de page -----
ok "bit esperado lido da page" \
   "[ \"\$(n 'bit_is_set = test_bit(bit_nr, &page->flags);' \"\$F\")\" = 1 ]" \
   "bit_is_set nao vem de &page->flags"
ok "os dois caminhos DROP intactos" \
   "[ \"\$(n 'if (behavior == DROP)' \"\$F\")\" = 4 ]" "esperava 4 ocorrencias"
ok "put_page(page) presente" \
   "grep -q 'put_page(page);' \"\$F\"" "put_page(page) sumiu"
ok "folio_put(folio) presente" \
   "grep -q 'folio_put(folio);' \"\$F\"" "folio_put(folio) sumiu"

# --- o page lock continua completo ------------------------------------
for sym in wait_on_page_bit wait_on_page_bit_killable put_and_wait_on_page_locked \
           __lock_page __lock_page_killable unlock_page \
           end_page_writeback wake_up_page_bit wake_up_page; do
    ok "$sym de pagina intacto" "grep -q '$sym' \"\$F\"" "simbolo ausente"
done

# --- cachefiles nao foi tocado, e nao precisa ser ---------------------
if [ -f "$RD" ]; then
    ok "cachefiles sem folio_add_wait_queue" \
       "! grep -q 'folio_add_wait_queue' \"\$RD\"" "cachefiles foi convertido"
    ok "cachefiles com os 3 add_page_wait_queue" \
       "[ \"\$(n 'add_page_wait_queue(backpage, &monitor->monitor)' \"\$RD\")\" = 3 ]" \
       "esperava 3 chamadas"
    ok "cachefiles ainda usa key->flags" \
       "grep -q 'key->flags' \"\$RD\"" "cachefiles nao usa mais a API wait_bit"
fi

echo "G2.3f: todas as verificacoes passaram."
