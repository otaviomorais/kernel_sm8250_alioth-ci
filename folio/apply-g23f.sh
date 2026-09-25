#!/usr/bin/env bash
# E404 folio G2.3f: Convert page wait queues to be folios (upstream patch 29/90).
#
# This is the first stage that changes an existing type rather than adding a
# parallel one: struct wait_page_key / struct wait_page_queue now hold a
# struct folio, and page_waitqueue() becomes folio_waitqueue().
#
# fs/cachefiles/rdwr.c is deliberately NOT converted, unlike upstream: the E404
# copy uses the generic wait_bit API and reads key->flags plus wait->private,
# never a page pointer out of the key.  add_page_wait_queue() is kept as a
# wrapper over folio_add_wait_queue() so that file still builds for anyone who
# enables CONFIG_CACHEFILES.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${1:-}"
PATCH="$SCRIPT_DIR/e404-folio-g2.3f.patch"

[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
[ -f "$KERNEL_DIR/Makefile" ] || { echo "FATAL: kernel invalido: $KERNEL_DIR" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "FATAL: patch folio G2.3f ausente" >&2; exit 1; }

bash "$SCRIPT_DIR/apply-g23e.sh" "$KERNEL_DIR"

if git -C "$KERNEL_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Folio G2.3f ja integrado."
else
    git -C "$KERNEL_DIR" apply --check "$PATCH"
    git -C "$KERNEL_DIR" apply "$PATCH"
fi

F="$KERNEL_DIR/mm/filemap.c"
H="$KERNEL_DIR/include/linux/pagemap.h"

# A fila de espera passa a ser indexada por folio.
[ "$(grep -c '^static wait_queue_head_t folio_wait_table' "$F")" = "1" ]
[ "$(grep -c '^static wait_queue_head_t \*folio_waitqueue(struct folio \*folio)' "$F")" = "1" ]
# Nenhuma definicao ou chamada da forma antiga; o nomevelo ainda aparece num
# comentario, entao a checagem e sobre a definicao e as chamadas.
[ "$(grep -c 'wait_queue_head_t \*page_waitqueue' "$F")" = "0" ]
[ "$(grep -c '= page_waitqueue(' "$F")" = "0" ]
[ "$(grep -c 'page_wait_table\[' "$F")" = "0" ]

# As duas estruturas carregam folio, e nenhum resto da forma antiga sobrou.
for st in wait_page_key wait_page_queue; do
    blk="$(sed -n "/^struct $st {/,/^};/p" "$F")"
    echo "$blk" | grep -q 'struct folio \*folio;'
    if echo "$blk" | grep -q 'struct page \*page;'; then
        echo "FATAL: $st ainda tem struct page" >&2; exit 1
    fi
done
[ "$(grep -c 'wait_page\.page\|wait_page->page\|key\.page =\|key->page ' "$F")" = "0" ]

# wake_page_function casa folio contra folio, inclusive no teste do bit.
grep -q 'if (wait_page->folio != key->folio)' "$F"
grep -q 'if (test_bit(key->bit_nr, &key->folio->flags))' "$F"

# Simetria: quem acorda e quem espera resolvem o mesmo folio.  Toda chamada a
# folio_waitqueue() com argumento struct page tem de passar por page_folio(),
# senao waiter e waker caem em buckets diferentes para o mesmo objeto.
[ "$(grep -c 'folio_waitqueue(&' "$F")" = "0" ]
[ "$(grep -n 'folio_waitqueue(' "$F" \
   | grep -v 'static wait_queue_head_t \*folio_waitqueue' \
   | grep -v '^ *[0-9]*: *\*' \
   | grep -v 'folio_waitqueue(folio)' \
   | grep -v 'folio_waitqueue(page_folio(page))' \
   | wc -l)" = "0" ]
[ "$(grep -c 'if (!folio_test_waiters(page_folio(page)))' "$F")" = "1" ]
grep -q 'folio_set_waiters(folio);' "$F"
grep -q 'folio_clear_waiters(folio);' "$F"

# A API nova existe e a antiga continua, como wrapper.
[ "$(grep -c '^void folio_add_wait_queue(struct folio \*folio, wait_queue_entry_t \*waiter)' "$F")" = "1" ]
grep -q 'EXPORT_SYMBOL_GPL(folio_add_wait_queue);' "$F"
[ "$(grep -c '^void add_page_wait_queue(struct page \*page, wait_queue_entry_t \*waiter)' "$F")" = "1" ]
grep -q 'EXPORT_SYMBOL_GPL(add_page_wait_queue);' "$F"
grep -q '^\tfolio_add_wait_queue(page_folio(page), waiter);' "$F"
grep -q '^void folio_add_wait_queue(struct folio \*folio, wait_queue_entry_t \*waiter);' "$H"
grep -q '^extern void add_page_wait_queue(struct page \*page, wait_queue_entry_t \*waiter);' "$H"

# O bit esperado e o put_page() do caminho DROP continuam em nivel de page:
# quem chama pediu uma page especifica e e dono daquela referencia.
[ "$(grep -c 'bit_is_set = test_bit(bit_nr, &page->flags);' "$F")" = "1" ]
[ "$(grep -c 'if (behavior == DROP)' "$F")" = "4" ]
grep -q 'put_page(page);' "$F"
grep -q 'folio_put(folio);' "$F"

# O page lock continua completo: este patch nao pode ter comido o caminho de
# pagina que o restante do kernel ainda usa.
for sym in wait_on_page_bit wait_on_page_bit_killable put_and_wait_on_page_locked \
           __lock_page __lock_page_killable unlock_page \
           end_page_writeback wake_up_page_bit wake_up_page; do
    grep -q "$sym" "$F" || { echo "FATAL: $sym de pagina sumiu" >&2; exit 1; }
done

# cachefiles nao foi tocado, e nao precisa ser: usa a API wait_bit generica.
if [ -f "$KERNEL_DIR/fs/cachefiles/rdwr.c" ]; then
    ! grep -q 'folio_add_wait_queue' "$KERNEL_DIR/fs/cachefiles/rdwr.c"
    [ "$(grep -c 'add_page_wait_queue(backpage, &monitor->monitor)' "$KERNEL_DIR/fs/cachefiles/rdwr.c")" = "3" ]
    grep -q 'key->flags' "$KERNEL_DIR/fs/cachefiles/rdwr.c"
fi

! grep -q 'CONFIG_MTHP' "$KERNEL_DIR/mm/Kconfig"

echo "Folio G2.3f integrado; wait_page_key/wait_page_queue em folios, add_page_wait_queue preservado."
