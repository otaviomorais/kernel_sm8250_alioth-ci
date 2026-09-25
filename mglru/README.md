# MGLRU E404

Este diretorio contem o backport opt-in do Multi-Gen LRU do AOSPA para o
E404 4.19.404R.

A patch consolidada foi gerada contra o commit E404
`ca410e68b6aa31efca73bbec288ef1ed671701f6` e inclui a serie AOSPA completa,
从 a partir de `3904c29400c6` (groundwork) até `f0125de52729`, incluindo:

- estruturas MGLRU e bits de page flags;
- reclaim, aging, memcg, page-table walks, sysfs/debugfs e `min_ttl`;
- adaptacao de swap/workingset para Xarray;
- camada de compatibilidade para a API `mm_walk` do 4.19;
- preservacao dos campos vendor e dos watermarks do E404.

O workflow aplica `apply.sh` somente quando `enable_mglru=true`. O baseline
UAPI2 + DroidSpaces validado nao e alterado quando a opcao permanece false.
A configuracao da candidata exige `CONFIG_LRU_GEN=y` e
`CONFIG_LRU_GEN_ENABLED=y` no `.config` final.
