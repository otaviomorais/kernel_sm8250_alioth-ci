# E404 folio backport

Este diretorio contem o primeiro estagio do backport de folios para o E404
4.19.404R, usando somente a serie upstream Linux.

## G1

`e404-folio-g1.patch` e um shim aditivo e layout-preserving que introduz:

- `struct folio` como wrapper transitional de `struct page`;
- `page_folio()` e `folio_page()`;
- `folio_order()`, `folio_nr_pages()`, `folio_size()` e helpers de zona;
- `compound_nr()` e `hpage_pincount_available()`.

O G1 nao habilita `mTHP`, nao converte page cache e nao altera reclaim,
swap, MGLRU, KSU/SUSFS ou DroidSpaces. O workflow aplica o patch somente
quando `enable_folios_g1=true`.

A base exata do patch e o commit E404
`ca410e68b6aa31efca73bbec288ef1ed671701f6`.
