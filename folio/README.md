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
