# E404 folio backport

Este diretorio contem o backport de folios para o E404 4.19.404R usando
somente a serie upstream Linux `folio-5.16` (merge
`49f8275c7d9247cf1dd4440fc8162f784252c849`).

## G1

`e404-folio-g1.patch` introduz o shim layout-preserving:

- `struct folio` como wrapper transitional de `struct page`;
- `page_folio()` e `folio_page()`;
- `folio_order()`, `folio_nr_pages()`, `folio_size()` e helpers de zona;
- `compound_nr()` e `hpage_pincount_available()`.

## G2.1

`e404-folio-g2.1.patch` adiciona, sobre o G1:

- wrappers `folio_ref_*` preservando os tracepoints E404;
- `folio_get()`, `folio_put()` e `folio_try_get_rcu()`;
- macros `VM_BUG_ON_FOLIO` e `VM_WARN_ON_ONCE_FOLIO`.

## G2.2a

`e404-folio-g2.2a.patch` adiciona, sobre o G2.1, a camada de flags de folio
re-derivada do patch upstream 10/90 para o `page-flags.h` do E404:

- `folio_flags()` e politicas `FOLIO_PF_*`;
- geradores `folio_test_*`, `folio_set_*`, `folio_clear_*` e `__folio_*`;
- alias `PG_readahead = PG_reclaim` (sem consumir bit novo);
- `folio_test_swapcache()`, `folio_test_uptodate()`, `folio_mark_uptodate()`;
- `folio_test_anon()`, `folio_test_ksm()`, `folio_test_single/multi()`;
- `folio_test_hugetlb()` e `folio_test_transhuge()`;
- `folio_test_double_map()` usando `FOLIO_PF_SECOND` (bit no primeiro tail);
- `folio_has_private()`.

O G2.2a altera somente `include/linux/page-flags.h`. Ele nao converte page
cache, LRU classic, swap state, mappings nem habilita mTHP. As funcoes
`Page*` existentes continuam intactas, exceto `PageReadahead`, que passa a usar
o alias `PG_readahead` (mesmo bit de `PG_reclaim`).

Nenhum estagio converte callers ainda: as APIs `folio_*` existem e sao
validadas em tempo de compilacao, mas a conversao real acontece nos estagios
seguintes.

O workflow aplica G1, G2.1 e G2.2a somente quando `enable_folios_g22=true`;
`enable_folios_g2=true` valida apenas G1+G2.1 e `enable_folios_g1=true`
valida apenas G1.

## G2.4a

`e404-folio-g2.4a.patch` aplica, sobre o G2.3f, o patch upstream 66/90
(`mm/writeback: Add __folio_end_writeback()`).

`test_clear_page_writeback()` é uma função interna do mm que estava nomeada
como se fosse um ponto de entrada do page cache. Este estágio:

- move a declaração de `include/linux/page-flags.h` para `mm/internal.h`;
- renomeia para `__folio_end_writeback()`;
- passa a receber `struct folio *` e a devolver `bool`.

Os dois chamadores convergem: `end_page_writeback()` resolve
`page_folio(page)` e `folio_end_writeback()` passa o próprio folio. Esse é o
ponto do patch — `PG_writeback` é uma flag `PF_NO_TAIL`, então a operação agora
sempre cai na page head em vez de depender de cada chamador ter normalizado
antes.

### `folio_memcg_lock()` / `folio_memcg_unlock()` adicionados aqui

O upstream tira esses dois helpers do patch 45/90, que faz parte do
rework de `memcg_data`/`obj_cgroup`. O E404 4.19 guarda o ponteiro de memcg
diretamente em `page->mem_cgroup` e não tem `obj_cgroup` nem `MEMCG_DATA_*`,
então os wrappers finos sobre `lock_page_memcg()` / `unlock_page_memcg()` são
tudo o que a conversão precisa. Destravar relendo `page->mem_cgroup` é seguro
porque nada entre o lock e o unlock altera esse campo.

### A contagem por página fica como está, de propósito

O upstream conta `folio_nr_pages()` aqui e troca
`dec_wb_stat()` / `__wb_writeout_inc()` e os contadores de zona/nó/lruvec por
`wb_stat_mod()` / `__wb_writeout_add()` / `*_stat_mod_folio()`. Essa família vem
do rework de vmstat dos patches 50-56 do upstream, que esta árvore não tem.

Deixei a generalização adiada em vez de inventá-la. `__fprop_add_percpu_max()`
governa o *throttling* de bandwidth de writeback; errar ali produz stall ou
perda de throttling, e o ganho seria zero aqui: `CONFIG_TRANSPARENT_HUGEPAGE`
não está no config, então toda página é de ordem 0 e um folio é sempre
exatamente uma página. As contagens ficam idênticas às do E404.

### Forma do E404 preservada

Onde o E404 difere do 5.16, o E404 vence: `mem_cgroup_page_lruvec()` continua
recebendo a page e o pgdat, `bdi_cap_account_writeback()` no lugar do teste em
`BDI_CAP_WRITEBACK_ACCT`, e `sb_clear_inode_writeback()` no lugar de
`wb_inode_writeback_end()`.

## Patches upstream deliberadamente pulados: 38-48 (memcg)

O bloco de memcg do upstream (38 a 48) **não é portável** para o E404, e isso
não é detalhe de forma: os patches convertem código que não existe aqui.

| mecanismo | 5.16 (assumido pelos patches) | E404 4.19R |
|---|---|---|
| armazenamento do ponteiro | `page->memcg_data` | `page->mem_cgroup` (ponteiro direto) |
| flag kmemcg | `MEMCG_DATA_KMEM` na mesma palavra | `PG_kmemcg` (bit separado) |
| object cgroup | `obj_cgroup`, `__page_objcg()` | **não existe** (0 ocorrências) |
| `PageMemcgKmem()` | existe | **não existe** |
| `charge_memcg()` / `__mem_cgroup_charge()` | existem | **não existem** |
| `mem_cgroup_charge()` | existe | **não existe**; há `mem_cgroup_try_charge()` |
| `commit_charge()` | 2 argumentos | 3 argumentos, com `lrucare` |
| `uncharge_gather` | tem `nid` | tem `dummy_page` |

Todas as contagens acima foram medidas na árvore. Aplicar 38-43 "à mão"
exigiria primeiro portar o esquema `memcg_data`/`obj_cgroup` do 5.7-5.16, que é
um backport de subsystem e não de folio: altera `struct page`, mexe em dezenas
de patches e threaten a ABI de vendor. E 47/48 dependem de `folio_memcg()`, que
vem do 38. Então o caminho é 66 → 80 → 85-89.

## G2.3f

`e404-folio-g2.3f.patch` aplica, sobre o G2.3e, o patch upstream 29/90
(`mm/filemap: Convert page wait queues to be folios`).

Este é o **primeiro estágio que converte um tipo existente**, em vez de apenas
acrescentar uma API paralela. Tudo até aqui era aditivo: os estágios G1 a G2.3e
adicionavam símbolos `folio_*` sem tocar no caminho de `struct page`.

O que muda:

- `struct wait_page_key` e `struct wait_page_queue` passam a carregar
  `struct folio *folio` no lugar de `struct page *page`;
- `page_waitqueue(struct page *)` vira `folio_waitqueue(struct folio *)`, e
  `page_wait_table[]` vira `folio_wait_table[]`;
- `wake_page_function()` casa folio contra folio, inclusive no `test_bit()` que
  decide se interrompe a varredura da fila;
- `folio_add_wait_queue()` passa a ser a implementação, e
  `add_page_wait_queue()` **continua existindo** como wrapper fino que resolve
  `page_folio()` e delega.

### `fs/cachefiles/rdwr.c` deliberadamente não convertido

O upstream reescreve `fs/cachefiles/rdwr.c` para ler `key->folio`, mas a cópia
do E404 **não usa esse campo**. Ela usa a API `wait_bit` genérica:

```c
struct wait_bit_key *key = _key;
struct page *page = wait->private;
...
if (key->flags != &page->flags || key->bit_nr != PG_locked)
```

E o `struct wait_bit_key` do E404 (`include/linux/wait_bit.h`) tem layout
`{ void *flags; int bit_nr; unsigned long timeout; }`, que **não** é o mesmo do
`struct wait_page_key`. O comentário antigo em `mm/filemap.c` ("This has the same
layout as wait_bit_key - see fs/cachefiles/rdwr.c") já era falso no 4.19: a API
`wait_bit` genérica foi reescrita depois dessa versão. Esse comentário foi
corrigido neste estágio.

Como o cachefiles se ancora em `key->flags` + `wait->private` e chama
`add_page_wait_queue()` com uma `struct page`, **manter o wrapper é o que mantém
o arquivo correto sem modificação alguma**. Além disso `CONFIG_CACHEFILES` não
está no config final deste build, então o arquivo nem compila hoje; o wrapper
evita deixar uma quebra latente para quem ligar a opção.

### Simetria entre quem acorda e quem espera

Este patch converte a chave, então quem acorda e quem espera precisam resolver o
**mesmo** folio, senão os dois caem em buckets diferentes do hash para o mesmo
objeto. Por isso, nos dois lados:

- `wake_up_page_bit()` e `wait_on_page_bit()` resolvem `page_folio(page)`;
- o bit `PG_waiters` é lido e escrito pelo folio nos dois lados
  (`folio_test_waiters` / `folio_set_waiters` / `folio_clear_waiters`).

O que **permanece em nível de `struct page` de propósito**: o bit realmente
esperado (`test_bit(bit_nr, &page->flags)`) e o `put_page(page)` do caminho
`DROP`. O caller pediu uma página específica e é dono daquela referência; trocar
isso seria mexer na contabilidade de referências, não na conversão de tipo.

### Índice de bucket inalterado

`hash_ptr()` opera sobre o valor do ponteiro, e `page_folio(page)` devolve o
endereço da page head, que é exatamente o endereço que o código antigo hasheava
para uma página de ordem 0. Neste build **todas** as páginas do page cache são
de ordem 0, porque `CONFIG_TRANSPARENT_HUGEPAGE` não está no config. Portanto o
hash, e logo a distribuição pelas 256 filas, é o mesmo de antes.

### Hunk de `__folio_lock_async()` omitido

O upstream também ajusta `__folio_lock_async()`, que recebe um
`struct wait_page_queue *`. O E404 não tem `__folio_lock_async()` nem
`lock_page_async()`: eles foram adicionados no 5.8, junto com o suporte a page
lock assíncrono. Não há a quem aplicar o hunk.

## G2.3e

`e404-folio-g2.3e.patch` adiciona, sobre o G2.3d, o patch upstream 28/90:

- `folio_wake_bit()` (static) em `mm/filemap.c`.

`folio_wake()` e `folio_unlock()` (adicionados em G2.3b/G2.3c) passam a usar
`folio_wake_bit()`, como o upstream faz neste patch. Ambas ainda nao tem
callers, logo isso nao muda comportamento.

A chave de waitqueue (`struct wait_page_key`) continua com `struct page`;
isso e convertido pelo patch upstream 29/90, no estágio G2.3f acima.

### Patch upstream 30/90 omitido

O patch 30/90 converte `end_page_private_2()`, `wait_on_page_private_2()`,
`wait_on_page_private_2_killable()` e `include/linux/netfs.h`. Verifiquei a
arvore do E404: **nao existe** `include/linux/netfs.h`, nem `end_page_private_2()`,
nem `wait_on_page_private_2()` / `wait_on_page_private_2_killable()` em
`mm/filemap.c`. Nao ha maquinaria de pagina para derivar as variantes de folio.
Escrever essas funcoes seria codigo novo, nao um port, entao elas ficam de
fora. O bit `PG_private_2` continua acessivel pelos wrappers de folio do
G2.2a (`folio_test_private_2()`, `folio_set_private_2()`,
`folio_clear_private_2()`).

## G2.3d

`e404-folio-g2.3d.patch` adiciona, sobre o G2.3c, o patch upstream 27/90:

- `folio_wait_bit_common()` (static) em `mm/filemap.c`;
- `folio_wait_bit()` e `folio_wait_bit_killable()` em `mm/filemap.c`;
- prototipo em `include/linux/pagemap.h`.

Adaptação importante do E404: o upstream 5.16 reescreveu
`wait_on_page_bit_common()` com `trylock_page_bit_common()` e um `repeat:`
label. O E404 4.19 tem a versao mais simples (loop `for (;;)` com
`__add_wait_queue_entry_tail()` + `SetPageWaiters()`). Aqui a variante de folio
e uma **traducao direta da versao do E404**, e nao uma traducao do 5.16, para
que o caminho de folio herde exatamente o mesmo comportamento de wakeup,
delayacct e PSI que o caminho de pagina que ele substitui. Importar o
algoritmo do 5.16 teria trocado a semantica de espera sem nenhum erro de
compilacao.

Como efeito colateral, `__folio_lock()` e `__folio_lock_killable()` (adicionados
no G2.3b) passam a usar `folio_wait_bit_common()`, que e o que o upstream faz
neste patch. Ambas as funcoes ainda nao tem callers, logo isso nao muda
comportamento.

`wait_on_page_bit()`, `wait_on_page_bit_killable()` e
`wait_on_page_bit_common()` ficam **intactos**.

## G2.3c

`e404-folio-g2.3c.patch` adiciona, sobre o G2.3b, os patches upstream 23/90 e
24/90:

- `folio_rotate_reclaimable()` em `mm/swap.c` (e prototipo em
  `include/linux/swap.h`);
- `folio_wake()` (static) e `folio_end_writeback()` em `mm/filemap.c`
  (e prototipo em `include/linux/pagemap.h`).

Adaptação específica do E404, e o ponto mais importante deste estágio: o
upstream 5.16 reescreve o corpo de `rotate_reclaimable_page()` para usar
`pagevec_add_and_need_flush()`. O E404 nao tem essa funcao; a versao dele e

```c
if (!pagevec_add(pvec, page) || PageCompound(page))
	pagevec_move_tail(pvec);
```

ou seja, o check de pagina composta e explicito e tem de ser preservado. Na
variante de folio ele vira `folio_test_multi(folio)`, que para a cabeca do
folio e exatamente equivalente a `PageCompound(&folio->page)`. Traduzir
literalmente o upstream teria **perdido esse flush de cauda para THP**,
alterando a contabilidade de reclaim sem nenhum erro de compilacao.

`rotate_reclaimable_page()` e `end_page_writeback()` ficam **intactos**.

## G2.3b

`e404-folio-g2.3b.patch` adiciona, sobre o G2.3a, a API de lock de folio
re-derivada dos patches upstream 17/90 a 22/90:

- em `mm/filemap.c`: `folio_unlock()`, `__folio_lock()`,
  `__folio_lock_killable()`, `__folio_lock_or_retry()`;
- em `include/linux/pagemap.h`: os prototipos correspondentes e os helpers
  inline `folio_trylock()`, `folio_lock()`, `folio_lock_killable()`,
  `folio_lock_or_retry()`, `folio_wait_locked()` e
  `folio_wait_locked_killable()`.

Adaptações ao E404, de novo aditivas:

- `__lock_page()`, `__lock_page_killable()`, `__lock_page_or_retry()` e
  `unlock_page()` ficam **intactos** em `mm/filemap.c`; as variantes `folio_*`
  sao funções novas ao lado delas;
- `mm/folio-compat.c` continua não sendo criado, então `mm/Makefile` fica
  intocado;
- o patch upstream 20/90 (`__folio_lock_async()`) é **omitido**: o E404 4.19
  nao possui `__lock_page_async()` nem `lock_page_async()` em
  `include/linux/pagemap.h`, portanto nao ha maquinery de lock assincrono
  para derivar a variante de folio.

Nenhum caller e convertido. Esta e a ultima camada puramente aditiva antes da
conversao real de `mm/filemap.c`.

## G2.3a

`e404-folio-g2.3a.patch` adiciona, sobre o G2.2b, a API de page cache
re-derivada dos patches upstream 13/90 a 16/90:

- `folio_index()`, `folio_next_index()`, `folio_file_page()`, `folio_contains()`;
- `folio_pos()`, `folio_file_pos()`;
- `folio_file_mapping()` e o prototipo de `folio_mapping()`;
- `folio_swap_entry()` em `include/linux/swap.h`;
- `folio_mapping()` em `mm/util.c`;
- `swapcache_mapping()` em `mm/swapfile.c`.

Adaptações ao E404, deliberadamente aditivas:

- `page_mapping()` continua em `mm/util.c` com o corpo original, e suas
  declarações duplicadas em `include/linux/mm.h` **não são tocadas**;
- `page_mapping_file()` (variante LA, que vive em `mm/util.c` e não em
  `pagemap.h`) fica intacta;
- `__page_file_mapping()` continua existindo em `mm/swapfile.c`; o
  `swapcache_mapping()` é adicionado **ao lado**, sem renomear nada;
- `mm/folio-compat.c` **não é criado**: ele existe no upstream apenas para
  mover o corpo de `page_mapping()` para fora do header. Como aqui nada e
  movido, o arquivo seria desnecessario, e `mm/Makefile` fica intocado;
- `page_file_mapping()` em `include/linux/mm.h` fica como esta.

Nenhum caller e convertido. As funcoes `folio_*` existem e sao validadas em
tempo de compilacao; a conversao de `filemap.c` vem no estagio seguinte.

## G2.2b

`e404-folio-g2.2b.patch` adiciona, sobre o G2.2a, dois blocos do upstream
(patches 11/90 e 12/90), de forma **aditiva**:

- `folio_is_file_lru()` e `folio_lru_list()`;
- `lruvec_add_folio()`, `lruvec_add_folio_tail()`, `lruvec_del_folio()`;
- `__folio_clear_lru_flags()`;
- `folio_get_private()`;
- `folio_attach_private()`, `folio_detach_private()`.

Carve-out importante: `attach_page_private()` / `detach_page_private()`
**nao** sao adicionados ao `pagemap.h` neste estagio. O E404 nao tem versoes
genericas nelem, e `fs/f2fs/f2fs.h` define copias proprias com as mesmas
assinaturas — adicionar as genericas causaria erro de redefinition. As
variantes `folio_*` acima sao a API nova deste estagio. Promover os wrappers
de pagina para o `pagemap.h` (e remover as copias do f2fs) pertence a um
estagio posterior, junto com a conversao dos callers do f2fs.

Adaptações específicas do E404:

- `update_lru_size()` / `__update_lru_size()` / `mem_cgroup_update_lru_size()`
  passam de `int` para `long` em `nr_pages`, para aceitar `folio_nr_pages()`;
- os helpers `lruvec_*` **mantêm o argumento `enum lru_list lru` explícito** do
  E404, em vez de recalcular a lista a partir do folio. Isso é necessário para o
  caminho de split de THP em `lru_add_page_tail()`, que opera em `page_tail` e
  precisa de um caminho de página explícito;
- `page_is_file_cache()`, `page_lru_base_type()`, `page_off_lru()`,
  `page_lru()` e as variantes `*_page_*` de LRU ficam **intocadas**;
- `include/trace/events/pagemap.h` **não é alterado**: o tracepoint
  `mm_lru_insertion` do E404 recebe o LRU já calculado como argumento;
- `mmzone.h` não é alterado e nenhum campo de MGLRU/`lru_gen` é adicionado.

Nenhum caller é convertido neste estágio.

O workflow aplica G1 -> G2.1 -> G2.2a -> G2.2a quando
`enable_folios_g22b=true`.

A base exata do patch e o commit E404
`ca410e68b6aa31efca73bbec288ef1ed671701f6`.
