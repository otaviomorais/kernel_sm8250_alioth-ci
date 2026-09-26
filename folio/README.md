# E404 folio backport

Este diretorio contem o backport de folios para o E404 4.19.404R usando
somente a serie upstream Linux `folio-5.16` (merge
`49f8275c7d9247cf1dd4440fc8162f784252c849`).

## Estado de validacao

Os builds sao cumulativos: o release do G2.5f contem G1 ate G2.5f. Entao um
unico boot bem-sucedido do build mais novo valida a cadeia inteira, nao so o
ultimo patch.

| estagio | build | validacao |
| --- | --- | --- |
| G1 | `folio-g1` | aparelho |
| G2.1 | `folio-g2` | aparelho |
| G2.2a | `folio-g22` | aparelho |
| G2.2b | `folio-g22b` | aparelho |
| G2.3a–G2.3e | `folio-g23a` … `folio-g23e` | aparelho |
| G2.3f | `folio-g23f` | aparelho |
| G2.4a | `folio-g24a` | aparelho |
| G2.4b | `folio-g24b` | aparelho |
| G2.5a | `folio-g25a` | aparelho |
| G2.5b | `folio-g25b` | aparelho (via G2.5f) |
| G2.5c | `folio-g25c` | aparelho (via G2.5f) |
| G2.5d | `folio-g25d` | aparelho (via G2.5f) |
| G2.5e | `folio-g25e` | aparelho (via G2.5f) |
| G2.5f | `folio-g25f` | aparelho |

O que um boot prova e o que nao prova: o boot cobre o caminho de alocacao, page
cache e LRU, porque o sistema inteiro depende deles para subir. Ele **nao** cobre
o caminho de writeback, que e onde o G2.5f mexeu, nem o de readahead. Esses
precisam de exercicio dirigido, nao so de bootar.

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

### Como escolher o estágio no CI

O workflow tem um único input de folio, `folio_stage`, com os valores `off`,
`g1`, `g2`, `g22` … `g25f`. Cada valor é cumulativo: `folio_stage: g25f` aplica
G1 até G2.5f, e `folio_stage: g22` aplica G1, G2.1 e G2.2a. O padrão é `off`,
então um build sem escolher nada não integra folios.

Isso substitui os 18 booleanos `enable_folios_*` que existiam antes. Ver a
seção "O teto de inputs do GitHub" para o motivo.

## Endurecimento da suite de verificacao

Duas correcoes na suite vieram de um teste negativo do G2.5e, que quebra a
arvore de proposito para ver se a verificacao percepto. As duas valiam
assercoes que passavam numa arvore quebrada.

### `ncd()` conta linha de codigo, nao linha comentada

O `nc()` so descartava a linha de **continuacao** de um comentario de bloco, ou
seja, as que comecam com `*`. A linha que abre e fecha o comentario na mesma
linha passava direto, porque comeca com `/`. Comentar um `EXPORT_SYMBOL` com
`/* ... */` na propria linha deixava `nc()` contando a linha, e a verificacao
"o simbolo continua exportado" passava numa arvore que ja nao o tinha.

O `ncd()` e o mesmo filtro, mais `-e '/\*' -e '\*/'`, entao descarta qualquer
linha que contenha abertura ou fechamento de comentario. As dezessete
verificacoes de `EXPORT_SYMBOL` dos sete scripts anteriores foram trocadas para
ele.

### As contagens de caller em `mm/filemap.c` sao teto, e nao igualdade

Estas contagens medem quantos callers ainda usam a API de page. Como cada estagio
converte mais um deles, a contagem so pode **baixar** de estagio para estagio: o
G2.5c tirou um caller de `__page_cache_alloc`, o G2.5d outro de
`add_to_page_cache_lru` e de `find_get_entry`, o G2.5e outro de
`pagecache_get_page`. Exigir `= N` fazia a verificacao de um estagio falhar
assim que um estagio posterior era ligado, que e o uso normal.

O que precisa valer e o **teto**: nenhum caller novo pode aparecer usando a API
de page. Um estagio posterior pode converter mais, o que so reduz a contagem.
Entao sao `-le N`.

As contagens em arquivos que nenhum estagio de folio toca — `mm/memcontrol.c` e
`fs/cachefiles/rdwr.c` — continuam exatas de proposito: ali a igualdade e
justamente a prova de que o estagio nao saiu de `mm/filemap.c`.

Pelo mesmo motivo, duas verificacoes que exigiam a forma `page_folio(page)` do
chamada a `workingset_refault()` passaram a aceitar `folio` tambem. O G2.5d
deixou o `page_folio()` de fora porque o caller ja tem o folio na mao. A
invariante que importa continua verificada a parte: nenhum caller passa
`struct page *`.

### O teto de inputs do GitHub

`workflow_dispatch` aceita no máximo 25 inputs. Com os 18 booleanos de folio mais
os 8 de MGLRU, KSU/SUSFS, DroidSpaces e `force_build`, o workflow chegou a 26 e o
dispatch do G2.5f respondeu `HTTP 422` antes de começar. Duas coisas resolveram:

1. O input `custom_boot_url` saiu. O `boot.img` base passa a vir sempre do Alioth
   AOSP; o outro workflow do repositório, `build-kernel.yml`, ainda tem o input.

2. Os 18 booleanos viraram um único `folio_stage` de escolha, com valores `off`,
   `g1`, `g2`, `g22` … `g25f`. Os estágios são cumulativos, então "até o estágio
   N" é a única escolha que significa alguma coisa, e 18 booleanos estavam
   expressando a mesma coisa 18 vezes.

O workflow ficou com **7 inputs**, então sobraram 18 slots: dá para adicionar
estágios sem bater no mesmo muro.

A condição de cada estágio é um `contains(fromJSON('['...']'), folio_stage)` com a
lista **explícita** dos estágios até ele, e não uma comparação de índice. Lista
explícita tem uma propriedade que ordem numérica não tem: um nome de estágio
digitado errado simplesmente nunca casa, enquanto um off-by-one na sequência liga
o estágio errado sem ninguém perceber. A verificação confere que cada lista é o
prefixo exato e que `off` não está em nenhuma delas, que é o que garante que o
padrão não integra folios.

### Como isso e testado

Rodar os oito `verify-*.sh` na arvore acumulada, e nao so o do estagio novo,
e o que pega esse tipo deassa. O step do G2.5e no workflow faz isso, e foi ele
que revelou as contagens envelhecidas.

Os scripts rodam em bash 5.3 de verdade, nao em um espelho em PowerShell. O
`sh.exe` do MinGit e um bash completo, mas so enxerga a propria raiz, entao
precisa de uma juncao para|area de trabalho e de uma copia dele mesmo nomeada
`bash.exe`, porque os scripts de apply chamam `bash "$SCRIPT_DIR/apply-gNNN.sh"`.

## G2.5f

`e404-folio-g2.5f.patch` aplica, sobre o G2.5e, o patch upstream 90/90
(`mm/writeback: Add folio_write_one`). É o último da série `folio-5.16`.

`write_one_page()` vira `folio_write_one()`, e `clear_page_dirty_for_io()` vira
`folio_clear_dirty_for_io()` com a versão de page como wrapper.
`folio_wait_writeback()` entra como `static inline` ao lado de
`wait_on_page_writeback()`.

O `write_one_page()` do E404 era byte a byte o do 5.16 que este patch reescreve,
então o hunk portou direto. As três coisas que mudam de verdade são
`.nr_to_write`, que passa a ser a contagem de páginas do folio, e os dois
helpers. O ponteiro de `writepage()` ainda toma `struct page *`, então a chamada
passa `&folio->page`.

### Por que `write_one_page` continua sendo função real

O upstream vira-o `static inline` em `pagemap.h` e julga que a economia não
compensa um wrapper no core. Aqui há duas razones medidas, não adivinhadas:

- São **nove callers in-tree**, um deles o driver `block2mtd`. Tirar o símbolo
  quebraria qualquer coisa que não recompilasse contra o header novo.
- **Cinco dos nove** — `fs/jfs`, `fs/minix`, `fs/ufs`, `fs/exofs` e `fs/ocfs2` —
  não incluem `linux/pagemap.h`. Mover a declaração para lá, como o upstream faz,
  **não compilaria**.

O símbolo não está em `android/abi_gki_aarch64_qcom`, então nenhuma promessa de
ABI está sendo quebrada ao mantê-lo. A razão são os callers, não a lista de ABI.

`task_dirty_inc()` continua em `mm.h`. O upstream remove essa linha no mesmo
hunk porque o patch 75/90 já tinha movido a declaração, e o 75/90 não faz parte
deste backport.

### `folio_clear_dirty_for_io` é parte do patch 74/90

O 90/90 precisa dela, e o 74/90 sozinho só entregaria um helper sem uso. O corpo
é o do E404 com a page trocada pelo folio que a head, o que preserva três
grafias que o 5.16 escreve diferente:

- `mapping_can_writeback()` é `mapping_cap_account_dirty()`.
- A contabilidade continua na page: `dec_lruvec_page_state()` e
  `dec_zone_page_state()` são os nomes do E404, e a primeira toma `struct page *`,
  não o `struct lruvec *` que o `dec_lruvec_state()` desta árvore toma.
- `set_page_dirty(&folio->page)`, e **não** `folio_mark_dirty(folio)`. Este é o
  ponto que mudaria comportamento em silêncio. O `folio_mark_dirty()` do 5.16
  carrega os efeitos colaterais que a chamada existe para ter, e o comentário do
  próprio E404 diz isso explicitamente. O `folio_set_dirty()` que o macro
  `PAGEFLAG(Dirty)` gera é um `set_bit()` puro: usá-lo perderia a tag dirty do
  xarray, o timestamp e a contabilidade de writeback, sem nenhum erro de
  compilação para denunciar.

O tipo de retorno é `int`, e não `bool`, para que `clear_page_dirty_for_io()`
mantenha a assinatura que já exporta.

### `folio_wait_stable` não foi mexido

O `folio_wait_stable()` do G2.5e continua escrevendo o próprio pré-check em vez
de chamar o `folio_wait_writeback()` novo. O upstream também escreve o dele, e
deixar um estágio já verificado intacto vale mais aqui do que remover duas linhas
duplicadas. O `verify-g25f.sh` afirma isso explicitamente, para que uma
refatoração futura não reposicione a verificação sem perceber.

### Onde a série parou

Com o G2.5f, o que está portado da série de 90 patches:

| patches | estágio |
| --- | --- |
| 1–37 | G1, G2.1, G2.2a, G2.2b, G2.3a–G2.3f |
| 38–48 | **pulados**: exigiriam backportar `obj_cgroup`/`memcg_data` |
| 49–65 | **pulados**: família de vmstat do upstream (`wb_stat_mod`, `__fprop_add_percpu_max`) |
| 66 | G2.4a |
| 67–79 | **pulados**: `filemap_dirty_folio()` e a família de redirty |
| 80 | G2.4b |
| 81–82 | **pulados**: `folio_evictable()` e `__pagevec_lru_add_fn` |
| 83–89 | G2.5a–G2.5e |
| 90 | G2.5f |

Os pulos não são omissão: cada um foi medido antes de ser decidido, e o motivo
está no README. O que falta é a família de writeback por folio (67–79) e os dois
patches de LRU (81–82), que são os candidatos naturais para a próxima rodada.

## G2.5e

`e404-folio-g2.5e.patch` aplica, sobre o G2.5d, o patch upstream 89/90
(`mm/filemap: Add FGP_STABLE`).

`__filemap_get_folio()` ganha `FGP_STABLE`, que espera o folio ficar estável, e
`grab_cache_page_write_begin()` para de chamar `wait_for_stable_page()` e passa
a pedir isso pela flag. `folio_wait_stable()` é nova em `mm/page-writeback.c`, ao
lado de `wait_for_stable_page()`, que vira o wrapper dela.

### FGP_STABLE vale 0x00000200, o valor do upstream

Não é o próximo bit livre desta árvore, que seria `0x00000080`. O upstream tem
`FGP_HEAD` em `0x00000080` e `FGP_ENTRY` em `0x00000100`, e nenhum dos dois
existe aqui. Deixar os dois bits sem uso não custa nada, mantém a numeração
idêntica à do 5.16 e impede que uma flag adicionada mais tarde colida com um
valor copiado do upstream.

O `verify-g25e.sh` confere que `FGP_STABLE` não colide com nenhuma das outras
oito flags, o que é a checagem que realmente importa aqui.

### O ramo fica antes do rótulo `no_page:`

O upstream põe o tratamento de `FGP_STABLE` depois do ramo
`FGP_WRITE`/`page_is_idle()`. A versão do E404 dessa função não tem esse ramo,
então não há nada entre o bloco de `FGP_ACCESSED` e `no_page:` para ele seguir.
Chegar ali já garante que o folio não é `NULL`, porque o bloco de cima só salta
para `no_page:` quando ele é.

### O pre-check de writeback foi mantido

`folio_wait_stable()` carrega o corpo do E404, com o pré-check de
`PageWriteback()` que vinha de `wait_on_page_writeback()`, escrito como
`folio_test_writeback()`. Ele não é redundante: sem ele todo caller pegaria o
lock da waitqueue só para descobrir que não há nada para esperar.

### `grab_cache_page_write_begin` continua sendo função real

O upstream o move para `mm/folio-compat.c`, que esta árvore não tem. Ele não
está em `android/abi_gki_aarch64_qcom`, então — ao contrário de
`pagecache_get_page()` — não há promessa de ABI o obrigando a continuar
exportado. Mas os filesystems do vendor desta árvore (f2fs, ubifs) chamam ele,
então continua sendo uma função real com o seu `EXPORT_SYMBOL`, e não um
`static inline`.

O corpo do E404 era byte a byte o do 5.16 que este patch reescreve, então o hunk
portou direto. A espera continua rodando antes de a page ser devolvida, que é
onde o `wait_for_stable_page()` explícito rodava.

O `noinline` que o upstream põe em `pagecache_get_page()` vai no mesmo lugar de
lá: no `mm/filemap.c`, porque é onde a função está. A razão é a mesma — manter um
wrapper de compatibilidade fora do caminho quente de quem só quer uma page.

## G2.5d

`e404-folio-g2.5d.patch` aplica, sobre o G2.5c, o patch upstream 88/90
(`mm/filemap: Add filemap_get_folio`).

`pagecache_get_page()` vira `__filemap_get_folio()` e ganha um inline novo,
`filemap_get_folio()`, por cima. Em `mm/swap.c`, `folio_mark_accessed()` passa a
ser a implementação e `mark_page_accessed()` vira o wrapper.

### `pagecache_get_page` continua sendo função real

Esta é a divergência que mais merece atenção. O upstream transforma
`pagecache_get_page()` em `static inline` dentro de `mm/folio-compat.c`, arquivo
que esta árvore não tem. Aqui ele vira um `static inline` em `pagemap.h`, o
símbolo sai do `.ko` e a promessa de ABI do vendor quebra.

`pagecache_get_page` está em `android/abi_gki_aarch64_qcom`, a lista de 2502
símbolos que o build GKI do Qualcomm promete manter. Por isso a função continua
em `mm/filemap.c` como função real, com o seu `EXPORT_SYMBOL`. É a razão de o
wrapper ser de três linhas em vez dos oito do upstream: sem `FGP_HEAD` não há
para que lado cair, então a head page é sempre a resposta certa.

O `verify-g25d.sh` checa isso de duas formas. A checagem direta do
`EXPORT_SYMBOL` roda sempre; a checagem contra a lista de ABI é pulada quando o
arquivo não está na árvore — a árvore de trabalho local tem só
`fs/include/kernel/mm` — e roda de verdade no CI, onde a árvore é completa. O
workflow ainda tem um passo separado que falha se a lista estiver ausente, para
que o pulo local nunca vire um pulo silencioso no CI.

O arquivo de ABI é um ini: `[abi_symbol_list]` no topo e dois espaços de
indentação em cada símbolo. A busca usa `^[[:space:]]*pagecache_get_page[[:space:]]*$`
e não `^pagecache_get_page$`, que não casaria com nada.

### O `pagecache_get_page` do E404 era mais simples que o do 5.16

Quatro partes do patch upstream não têm o que converter aqui, e reproduzi-las
seria importar de 5.16 algo que não tem contraparte:

- **`FGP_HEAD` e o `find_subpage()` que vinha junto.** O xarray do E404 só guarda
  head pages, então a entrada de `@index` sempre começa em `@index`. Não existe
  flag `FGP_HEAD`, e não existe `find_lock_head()` para remover.
- **`thp_contains()`** na checagem de truncamento do `FGP_LOCK`. A invariante do
  E404 era `page->index == offset`, que vira `folio->index == index` e é
  verificada com `VM_BUG_ON_FOLIO()`.
- **O ramo `FGP_WRITE`/`page_is_idle()`.** A função do E404 não tem esse ramo;
  o bit idle é limpo por `folio_mark_accessed()`.
- **`FGP_ENTRY`.** Não existe no E404, e a função sempre converte entrada de
  shadow ou swap em `NULL`. Isso é preservado.

### `folio_mark_accessed` fica com o corpo do E404

O `mark_page_accessed()` do E404 e o `folio_mark_accessed()` do 5.16 diferem em
dois pontos: o E404 não retorna cedo em página unevictable, e o 5.16 sim; o E404
limpa o bit idle no fim, e o 5.16 não. Trocar qualquer um dos dois mudaria
comportamento, e não só o tipo, então o corpo do E404 foi mantido.

O que de fato sai é o `compound_head()` do começo: um folio já é a head, que é
justamente o ponto da conversão. O resto do corpo — o ramo do MGLRU com
`page_inc_refs()`, a ativação pelo pagevec, `workingset_activation()` e a limpeza
de idle — está intacto.

### `find_get_entry` continua de pé

O 88/90 converte apenas `pagecache_get_page()`. `find_lock_entry()` e
`mm/memcontrol.c` ainda chamam `find_get_entry()`, então o wrapper do G2.5c não
pode sair aqui. No upstream ele só é removido depois que esses dois são
convertidos, num patch posterior.

## G2.5c

`e404-folio-g2.5c.patch` aplica, sobre o G2.5b, o patch upstream 87/90
(`mm/filemap: Convert mapping_get_entry to return a folio`).

O page cache só contém folios, então a entrada carregada do xarray **já é** a
head, e a especulação pode ir direto nela em vez de numa head obtida com
`compound_head()`.

A segunda metade do patch decorre da primeira: como o objeto em que temos
referência e o objeto que comparamos com `xas_reload()` passaram a ser o mesmo,
a checagem separada de "a page foi dividida embaixo de nós" do E404 deixou de
fazer falta. O upstream chega ao mesmo ponto pelo outro lado, apagando a
equivalente dentro de `mapping_get_entry()`.

### Os dois nomes convivem

No upstream a função se chama `mapping_get_entry()` e devolve `void *`, para que
o tipo diga ao caller se ele recebeu um folio ou uma entrada de shadow/swap. No
E404 ela se chamava `find_get_entry()` e devolvia `struct page *`.

Ambos existem aqui: `mapping_get_entry()` é a função estática convertida, e
`find_get_entry()` vira um wrapper fino exportado que devolve a head page para
os callers ainda não convertidos (dois em `mm/filemap.c`, um em
`mm/memcontrol.c`). O upstream converte esses callers nos patches 88/90 e 89/90,
depois dos quais o wrapper sai.

O wrapper precisa tratar NULL e `xa_is_value()` antes de dereferenciar: uma
entrada de shadow tem o bit baixo setado, e NULL não é folio, então um
`page_folio()` puro não faria sentido em nenhum dos dois casos. E `page_folio()`
é um macro `_Generic` cujos braços são `struct page *` e `const struct page *`,
então o wrapper faz cast explícito antes de chamar: uma expressão `void *` não
selecionaria nenhum braço e não compilaria.

### A semântica da referência é a mesma

`folio_try_get_rcu()` e `page_cache_get_speculative()` do E404 são a mesma
operação aqui: sem `CONFIG_TINY_RCU` — este build tem `CONFIG_PREEMPT_RCU=y` e
não tem TINY_RCU — a primeira é `folio_ref_add_unless(folio, 1, 0)` e a segunda é
`get_page_unless_zero()`. A única coisa que se perde é o
`VM_BUG_ON_PAGE(PageTail(page))` da versão de page, que um folio satisfaz por
construção.

## G2.5b

`e404-folio-g2.5b.patch` aplica, sobre o G2.5a, os patches upstream 83/90
(`mm/swap: Add folio_add_lru`) e 86/90 (`mm/filemap: Add filemap_add_folio`).
Eles vão juntos porque o 86 chama `folio_add_lru()`.

`__add_to_page_cache_locked()` vira `__filemap_add_folio()`, e
`add_to_page_cache_lru()` vira `filemap_add_folio()`. Os dois pontos de entrada
antigos sobrevivem como wrappers finos, então os **sete** callers in-tree
(três em `mm/filemap.c`, quatro em `fs/cachefiles/rdwr.c`) continuam compilando
sem mudança.

### Divergências

- `__filemap_add_folio()` continua `static`. O upstream exporta e só remove o
  `ALLOW_ERROR_INJECTION()` e o `BTF_ID()` em `kernel/bpf/verifier.c` porque
  error injection e BTF precisam do símbolo visível. O E404 não tem nenhum dos
  dois nessa função, então exportar seria ruído.
- O charge de memcg mantém o protocolo de três fases do E404, tomando a page
  head: `mem_cgroup_try_charge()` → `mem_cgroup_commit_charge()`, ou
  `mem_cgroup_cancel_charge()` no caminho de erro. O upstream chama
  `mem_cgroup_charge()` e `mem_cgroup_uncharge()` aqui, e **nenhuma das duas
  existe** no E404 4.19 — é o rework de `memcg_data`/`obj_cgroup` dos patches
  38-43, que não é portável.
- `__inc_node_page_state()` foi mantido, não `__lruvec_stat_add_folio()`. O E404
  contabiliza `NR_FILE_PAGES` por nó, e os helpers de stat de lruvec vêm do
  rework de vmstat dos patches 50-56.
- Os hunks de split do xarray foram descartados: precisam de `xa_get_order()`,
  `xas_split_alloc()` e `xas_split()`, nenhum dos quais existe no E404. Vieram
  junto com o suporte a xarray multipage, que faz parte do mesmo rework de
  memcg.
- O xarray ainda guarda ponteiro de page, então `xas_store()` recebe
  `&folio->page` em vez do folio. Os endereços são idênticos, mas nomear a page
  é honesto sobre o que o xarray guarda nesta árvore.
- `folio_add_lru()` chama o `__lru_cache_add(&folio->page)` do MGLRU em vez de
  inlineizar o corpo com `pagevec_add_and_need_flush()`, que não existe no
  E404. O MGLRU já tinha dividido `lru_cache_add()` exatamente nessa forma,
  então a versão de folio reaproveita aquele corpo sem alteração.
- Os wrappers de compatibilidade ficam inline em `mm/filemap.c`, `mm/swap.c` e
  `include/linux/pagemap.h` em vez de irem para `mm/folio-compat.c`, que esta
  árvore não tem. É a mesma escolha feita com `add_page_wait_queue()` no G2.3f.
- A assert de alinhamento natural do upstream foi adicionada como ele escreve.
  Em ordem 0, que é todo folio nesta configuração, `folio_nr_pages()` é 1, então
  `index & (1 - 1)` é 0 e ela nunca pode disparar; só fica viva se algum caller
  passar ordem > 1.

## G2.5a

`e404-folio-g2.5a.patch` aplica, sobre o G2.4b, os patches upstream 84/90
(`mm/page_alloc: Add folio allocation functions`) e 85/90
(`mm/filemap: Add filemap_alloc_folio`). Eles não podem ser separados: o 85
chama `folio_alloc()` e `__folio_alloc_node()`, que o 84 introduz.

Adiciona quatro pontos de entrada, como wrappers finos sobre o alocador de
pages **intocado**:

| função | onde |
|---|---|
| `__folio_alloc()` | `mm/page_alloc.c` |
| `__folio_alloc_node()` | `include/linux/gfp.h` |
| `folio_alloc()` | `mm/mempolicy.c` (NUMA) / `gfp.h` (resto) |
| `filemap_alloc_folio()` | `mm/filemap.c` (NUMA) / `pagemap.h` (resto) |

`__page_cache_alloc()` vira um `static inline` que delega para
`filemap_alloc_folio(gfp, 0)`, então o page cache mantém o ponto de entrada que
já tinha enquanto os filesystems podem ser convertidos no ritmo que quiser.

### `__GFP_COMP` em ordem 0 é um no-op — verificado

Os wrappers somam `__GFP_COMP` na máscara de gfp, que é o que faz o buddy
allocator preparar uma page composta. Para o page cache a ordem é sempre 0, e
nesse caso a flag não faz nada:

- `mm/page_alloc.c:prep_new_page()` guarda a chamada com
  `if (order && (gfp_flags & __GFP_COMP))`, então ordem 0 nunca chega em
  `prep_compound_page()`;
- `___GFP_COMP` é `0x4000`, que não colide com nenhum dos bits de seleção de
  zona (`___GFP_DMA` 0x01, `___GFP_HIGHMEM` 0x02, `___GFP_DMA32` 0x04,
  `___GFP_MOVABLE` 0x08) usados para derivar `zone_idx` e o migratetype.

Ou seja: o caminho quente de alocação de page cache fica bit a bit igual. A
flag só passa a importar se algum caller pedir ordem > 1.

`prep_transhuge_page()` é chamada como o upstream faz. Com
`CONFIG_TRANSPARENT_HUGEPAGE` desligado — e está, neste build — ela é um
`static inline` vazio em `include/linux/huge_mm.h`, então a chamada some na
compilação.

### Divergências do upstream

- `__folio_alloc()` chama `__alloc_pages_nodemask()`, não `__alloc_pages()`. O
  E404 divide o alocador de outro jeito: `__alloc_pages_nodemask()` é a função
  real em `mm/page_alloc.c` e `__alloc_pages()` é um inline de três argumentos
  ao redor dela. A forma de `__alloc_pages()` do 5.16, que recebe o nodemask,
  não existe aqui.
- `folio_alloc()` fica ao lado de `alloc_pages_current()`, não de
  `alloc_pages()`. No `gfp.h` do E404, `alloc_pages()` é um inline que chama
  `alloc_pages_current()`; não há `alloc_pages()` em `mempolicy.c` para pendurar
  a função nova.
- A checagem de validade do node é repetida em `__folio_alloc_node()` em vez de
  compartilhada com `__alloc_pages_node()`. O upstream também repete, porque lá
  o `__alloc_pages()` não tem checagem para delegar.
- `EXPORT_SYMBOL(__page_cache_alloc)` sai, entra
  `EXPORT_SYMBOL(filemap_alloc_folio)`. `__page_cache_alloc()` sobrevive como
  `static inline` no `pagemap.h`, então os dois callers in-tree
  (`mm/filemap.c` e `fs/cachefiles/rdwr.c`) continuam funcionando sem mudança.
  O upstream faz exatamente o mesmo.

## G2.4b

`e404-folio-g2.4b.patch` aplica, sobre o G2.4a, o patch upstream 80/90
(`mm/workingset: Convert workingset_refault() to take a folio`).

`workingset_refault()` passa a receber `struct folio *`, e o chamador resolve
`page_folio(page)`. As duas flags que ela escrevia — `PG_active` e
`PG_workingset`, ambas `PF_HEAD` — passam a ser setadas pelos acessores de
folio, então a operação fica ancorada na page head em vez de whatever o
chamador tenha passado.

### O caminho do MGLRU continua sendo de page, de propósito

`workingset_refault()` no E404 tem um early return do MGLRU logo no topo:

```c
if (lru_gen_enabled()) {
	lru_gen_refault(page, shadow);
	return;
}
```

`lru_gen_refault()` é do MGLRU, não da conversão de folios, então **não** foi
reescrito. A chamada passou a ser `lru_gen_refault(&folio->page, shadow)` — a
page head, que é tanto a page que o chamador tinha quanto a dona de
`PG_workingset`. Reescrever o MGLRU seria sair do escopo do projeto.

### Os contadores ficam sem o split por file/anon

O upstream escreve `WORKINGSET_REFAULT_BASE + file`, que vem do rework de
vmstat que também renumerou esses itens do enum. O E404 tem os contadores
simples, `WORKINGSET_REFAULT` / `WORKINGSET_ACTIVATE` / `WORKINGSET_RESTORE`.
Eles passam a ser carregados com `mod_lruvec_state(..., nr)` em vez de
`inc_lruvec_state(...)`, para que o valor cobrado continue expresso em
geometria de folio como o upstream pretende.

Também não há `page_memcg()` para converter: o E404 tira o memcg da entrada
shadow via `mem_cgroup_from_id()`. O upstream lê do folio, e é por isso que ele
precisava do `folio_memcg()` do patch 38.

### O que o E404 não tem, continua não tendo

- `workingset_age_nonresident()` não existe no E404 4.19, então a chamada que o
  upstream converte simplesmente não está aqui;
- `lru_note_cost()` não existe (0 ocorrências na árvore): é a contabilidade de
  custo de writeback por CPU que chegou no 5.16. O rename
  `lru_note_cost_page()` → `lru_note_cost_folio()` é descartado;
- `include/linux/vmstat.h`: o upstream apaga `inc_lruvec_state()` por ela ficar
  sem uso. No E404 ela vive em `memcontrol.h` e foi deixada — remover um helper
  é churn sem benefício, e `dec_lruvec_state()` continua em uso pelo caminho de
  writeback do G2.4a.

### E404 tem um chamador só

`mm/filemap.c:add_to_page_cache_lru()`. Os outros dois que o upstream converte
(`do_swap_page()` e `__read_swap_cache_async()`) **não** chamam
`workingset_refault()` nesta árvore: `get_shadow_from_swap_cache()` também não
existe aqui.

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

O workflow aplica G1 -> G2.1 -> G2.2a -> G2.2b quando
`folio_stage: g22b`.

A base exata do patch e o commit E404
`ca410e68b6aa31efca73bbec288ef1ed671701f6`.
