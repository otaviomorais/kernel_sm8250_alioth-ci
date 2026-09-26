#!/usr/bin/env bash
# Verificacao do G2.5e (upstream patch 89/90: FGP_STABLE).
# Rodada separadamente do apply para que o log do CI aponte a assercao exata.
#
# O `|| true` em n()/nc() e obrigatorio: com `set -o pipefail`, um grep sem
# casamento faz o pipeline inteiro devolver 1 e o script morre ali em vez de
# comparar a contagem com 0.
set -euo pipefail

KERNEL_DIR="${1:-}"
[ -n "$KERNEL_DIR" ] || { echo "Uso: $0 <kernel>" >&2; exit 1; }
KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"

FL="$KERNEL_DIR/mm/filemap.c"
PW="$KERNEL_DIR/mm/page-writeback.c"
PM="$KERNEL_DIR/include/linux/pagemap.h"
PF="$KERNEL_DIR/include/linux/page-flags.h"

for f in "$FL" "$PW" "$PM" "$PF"; do
    [ -f "$f" ] || { echo "FATAL: $f ausente" >&2; exit 1; }
done

n() { grep -c "$1" "$2" || true; }
nc() { grep -v '^[[:space:]]*\*' "$2" | grep -c "$1" || true; }
# ncd() = "nao comentario", para as contagens que precisam valer.
#
# nc() so descarta a linha de CONTINUACAO de um comentario de bloco.  A linha
# que abre e fecha o comentario na mesma linha passa direto por ela, porque
# comeca com '/' e nao com '*'.  Isso ja enganou duas vezes: comentando um
# EXPORT_SYMBOL com /* ... */ na propria linha, nc() continuava contando a
# linha e a asercao passava numa arvore sem o simbolo.  ncd() descarta tambem
# qualquer linha que contenha /* ou */.
ncd() { grep -v -e '^[[:space:]]*\*' -e '/\*' -e '\*/' "$2" | grep -c "$1" || true; }
# fn() extrai o corpo de uma funcao, ate a chave de abertura no nivel 0.
# A assinatura passada tem de ser mais especifica que a linha do comentario
# kdoc, senao awk casa na documentacao e devolve o bloco errado.
fn() { awk -v sig="$2" 'index($0, sig) { inb=1 } inb { print } inb && /^[}]$/ { exit }' "$1"; }
ok() { if eval "$2"; then echo "  ok   $1"; else echo "  FALHA $1 -> $3" >&2; exit 1; fi; }

echo "Validando o G2.5e..."

GET="$(fn "$FL" 'struct folio *__filemap_get_folio(struct address_space *mapping')"
GCWB="$(fn "$FL" 'struct page *grab_cache_page_write_begin(struct address_space *mapping')"
FWS="$(fn "$PW" 'void folio_wait_stable(struct folio *folio)')"
WFS="$(fn "$PW" 'void wait_for_stable_page(struct page *page)')"

ok "corpo de __filemap_get_folio extraido" \
   "grep -q 'if (fgp_flags & FGP_STABLE)' <<< \"\$GET\"" "nao achei o corpo"
ok "corpo de grab_cache_page_write_begin extraido" \
   "grep -q 'FGP_STABLE' <<< \"\$GCWB\"" "nao achei a funcao"
ok "corpo de folio_wait_stable extraido" \
   "grep -q 'folio_wait_bit(folio, PG_writeback);' <<< \"\$FWS\"" "nao achei a implementacao"
ok "corpo de wait_for_stable_page extraido" \
   "grep -q 'folio_wait_stable(page_folio(page));' <<< \"\$WFS\"" "o wrapper nao delega"

# --- a flag nova --------------------------------------------------
# O valor e o do upstream, 0x00000200, e nao o proximo bit livre desta arvore.
# 0x80 e 0x100 ficam sem uso de proposito: FGP_HEAD e FGP_ENTRY nao existem
# aqui, porque o xarray do E404 so guarda head pages e nao expoe entrada de
# shadow/swap.  A numeracao igual a do 5.16 impede que uma flag futura colida
# com um valor copiado do upstream.
ok "FGP_STABLE vale 0x00000200, o valor do upstream" \
   "grep -q '^#define FGP_STABLE[[:space:]]*0x00000200\$' \"\$PM\"" \
   "o valor diverge do upstream, ou o bit esta certo"
ok "FGP_STABLE e distinto de todas as outras flags FGP" \
   "[ \"\$(grep -Eo '0x[0-9a-f]{8}' <<< \"\$(grep '^#define FGP_' \"\$PM\")\" | sort | uniq -d | wc -l)\" = 0 ]" \
   "duas flags FGP com o mesmo valor"
ok "FGP_HEAD nao foi criado" \
   "[ \"\$(nc 'FGP_HEAD' \"\$PM\")\" = 0 ]" "FGP_HEAD nao existe no E404"
ok "FGP_ENTRY nao foi criado" \
   "[ \"\$(nc 'FGP_ENTRY' \"\$PM\")\" = 0 ]" "FGP_ENTRY nao existe no E404"
ok "os dois buracos de bit estao documentados" \
   "grep -q 'FGP_HEAD at' \"\$PM\" && grep -q '0x00000080' \"\$PM\" && \
    grep -q 'FGP_ENTRY at' \"\$PM\" && grep -q '0x00000100' \"\$PM\"" \
   "a razao dos buracos 0x80 e 0x100 ficou sem escrever"
ok "as sete flags anteriores seguem com os valores de sempre" \
   "grep -q '^#define FGP_ACCESSED[[:space:]]*0x00000001\$' \"\$PM\" && \
    grep -q '^#define FGP_LOCK[[:space:]]*0x00000002\$' \"\$PM\" && \
    grep -q '^#define FGP_CREAT[[:space:]]*0x00000004\$' \"\$PM\" && \
    grep -q '^#define FGP_WRITE[[:space:]]*0x00000008\$' \"\$PM\" && \
    grep -q '^#define FGP_NOFS[[:space:]]*0x00000010\$' \"\$PM\" && \
    grep -q '^#define FGP_NOWAIT[[:space:]]*0x00000020\$' \"\$PM\" && \
    grep -q '^#define FGP_FOR_MMAP[[:space:]]*0x00000040\$' \"\$PM\"" \
   "uma flag anterior mudou de valor"
ok "sao oito flags FGP no total" \
   "[ \"\$(nc '#define FGP_' \"\$PM\")\" = 8 ]" "esperava 8"

# --- o ramo FGP_STABLE em __filemap_get_folio ----------------------
ok "FGP_STABLE esta documentado no kdoc" \
   "grep -q '%FGP_STABLE - Wait for the folio to be stable' \"\$FL\"" \
   "a flag nova nao entrou no kdoc"
ok "o ramo existe" \
   "grep -q 'if (fgp_flags & FGP_STABLE)' <<< \"\$GET\"" "o ramo sumiu"
ok "o ramo espera pelo folio" \
   "grep -q 'folio_wait_stable(folio);' <<< \"\$GET\"" "a espera sumiu"
ok "o ramo vem antes do rotulo no_page" \
   "[ \"\$(grep -n 'if (fgp_flags & FGP_STABLE)' <<< \"\$GET\" | head -1 | cut -d: -f1)\" \
      -lt \"\$(grep -n '^no_page:' <<< \"\$GET\" | head -1 | cut -d: -f1)\" ]" \
   "o ramo tem de vir antes de no_page, como no upstream"
ok "o ramo vem depois de FGP_ACCESSED" \
   "[ \"\$(grep -n 'folio_mark_accessed(folio);' <<< \"\$GET\" | head -1 | cut -d: -f1)\" \
      -lt \"\$(grep -n 'if (fgp_flags & FGP_STABLE)' <<< \"\$GET\" | head -1 | cut -d: -f1)\" ]" \
   "a ordem das duas flags mudou"
ok "o ramo nao foi colocado dentro do FGP_CREAT" \
   "[ \"\$(grep -n 'if (fgp_flags & FGP_STABLE)' <<< \"\$GET\" | head -1 | cut -d: -f1)\" \
      -lt \"\$(grep -n 'if (!folio && (fgp_flags & FGP_CREAT))' <<< \"\$GET\" | head -1 | cut -d: -f1)\" ]" \
   "FGP_STABLE tem de ser verificado antes de criar a pagina"
ok "so ha um ramo FGP_STABLE" \
   "[ \"\$(grep -c 'if (fgp_flags & FGP_STABLE)' <<< \"\$GET\")\" = 1 ]" "esperava 1"
ok "o ramo nao inventou FGP_HEAD" \
   "[ \"\$(grep -c 'FGP_HEAD' <<< \"\$GET\")\" = 0 ]" "veio FGP_HEAD do 5.16"

# --- folio_wait_stable -------------------------------------------
# O corpo e o do E404: o pre-check de PageWriteback() que vinha de
# wait_on_page_writeback() e mantido, escrito como folio_test_writeback().  Sem
# ele todo caller pegaria o lock da waitqueue so para descobrir que nao ha
# nada para esperar.
ok "folio_wait_stable devolve void" \
   "grep -q '^void folio_wait_stable(struct folio \*folio)\$' \"\$PW\"" \
   "a assinatura mudou"
ok "folio_wait_stable checa o bdi pelo inode do folio" \
   "grep -q 'bdi_cap_stable_pages_required(inode_to_bdi(folio->mapping->host))' <<< \"\$FWS\"" \
   "a checagem de bdi mudou"
ok "o pre-check de writeback foi mantido" \
   "grep -q 'folio_test_writeback(folio)' <<< \"\$FWS\"" \
   "o pre-check do E404 sumiu; todo caller passaria a pegar o lock a toa"
ok "a espera e pelo bit de writeback do folio" \
   "grep -q 'folio_wait_bit(folio, PG_writeback);' <<< \"\$FWS\"" \
   "a espera mudou"
ok "o pre-check e a espera estao na mesma sentenca" \
   "grep -q 'folio_test_writeback(folio))\$' <<< \"\$FWS\"" \
   "o pre-check virou uma sentenca separada"
ok "folio_wait_stable esta exportada" \
   "[ \"\$(ncd 'EXPORT_SYMBOL_GPL(folio_wait_stable);' \"\$PW\")\" = 1 ]" "perdeu o export"
ok "folio_wait_stable nao volta a compound_head" \
   "[ \"\$(grep -c 'compound_head' <<< \"\$FWS\")\" = 0 ]" "ainda resolve compound_head()"
ok "folio_wait_stable foi declarado no header" \
   "grep -q '^void folio_wait_stable(struct folio \*folio);\$' \"\$PM\"" "falta a declaracao"
ok "a declaracao de wait_for_stable_page nao mudou" \
   "grep -q '^void wait_for_stable_page(struct page \*page);\$' \"\$PM\"" \
   "a declaracao antiga foi sobrescrita"
ok "wait_for_stable_page virou wrapper" \
   "[ \"\$(grep -c 'bdi_cap_stable_pages_required' <<< \"\$WFS\")\" = 0 ]" \
   "o wrapper ainda e a implementacao"
ok "wait_for_stable_page continua exportada" \
   "[ \"\$(ncd 'EXPORT_SYMBOL_GPL(wait_for_stable_page);' \"\$PW\")\" = 1 ]" "perdeu o export"
ok "wait_for_stable_page e declarada uma vez" \
   "[ \"\$(nc 'wait_for_stable_page' \"\$PM\")\" = 1 ]" "declaracao faltando ou duplicada"

# --- grab_cache_page_write_begin ---------------------------------
# O corpo do E404 era byte a byte o do 5.16 que este patch reescreve, entao o
# hunk porteia direto.  A espera continua acontecendo antes de a page ser
# devolvida, que e onde o wait_for_stable_page() explicito rodava.
ok "grab_cache_page_write_begin soma FGP_STABLE as flags" \
   "grep -q 'int fgp_flags = FGP_LOCK|FGP_WRITE|FGP_CREAT|FGP_STABLE;' <<< \"\$GCWB\"" \
   "esperava as quatro flags"
ok "grab_cache_page_write_begin nao chama mais wait_for_stable_page" \
   "[ \"\$(grep -c 'wait_for_stable_page' <<< \"\$GCWB\")\" = 0 ]" \
   "a espera continua fora do flag"
ok "grab_cache_page_write_begin nao tem mais variavel local de page" \
   "[ \"\$(grep -c 'struct page \*page;' <<< \"\$GCWB\")\" = 0 ]" \
   "a variavel local ficou sem uso"
ok "grab_cache_page_write_begin delega para pagecache_get_page" \
   "grep -q 'return pagecache_get_page(mapping, index, fgp_flags,' <<< \"\$GCWB\"" \
   "o wrapper nao delega"
ok "grab_cache_page_write_begin repassa mapping_gfp_mask" \
   "grep -q 'mapping_gfp_mask(mapping));' <<< \"\$GCWB\"" "a gfp do mapping sumiu"
ok "o tratamento de AOP_FLAG_NOFS continua igual" \
   "grep -q 'if (flags & AOP_FLAG_NOFS)' <<< \"\$GCWB\"" "o AOP_FLAG_NOFS saiu"
ok "grab_cache_page_write_begin continua sendo funcao real" \
   "grep -q '^struct page \*grab_cache_page_write_begin(struct address_space \*mapping,$' \"\$FL\"" \
   "virou static inline e os filesystems do vendor quebram"
ok "grab_cache_page_write_begin continua exportada" \
   "[ \"\$(ncd 'EXPORT_SYMBOL(grab_cache_page_write_begin);' \"\$FL\")\" = 1 ]" \
   "os filesystems do vendor chamam esse simbolo"
ok "a assinatura nao mudou" \
   "grep -q '^struct page \*grab_cache_page_write_begin(struct address_space \*mapping,$' \"\$FL\" && \
    grep -q '^[[:space:]]*pgoff_t index, unsigned flags)\$' \"\$FL\"" "a assinatura mudou"

# --- noinline em pagecache_get_page ------------------------------
# Vem do patch 89/90, onde fica em mm/folio-compat.c pelo mesmo motivo: manter
# um wrapper de compatibilidade fora do caminho quente.  Aqui a funcao ja e
# real desde o G2.5d, por causa da ABI do vendor.
ok "pagecache_get_page tem noinline" \
   "grep -B1 '^struct page \*pagecache_get_page(struct address_space \*mapping, pgoff_t offset,$' \"\$FL\" | grep -q '^noinline\$'" \
   "o atributo noinline sumiu ou ficou longe da definicao"
ok "pagecache_get_page continua exportada (ABI do vendor)" \
   "[ \"\$(ncd 'EXPORT_SYMBOL(pagecache_get_page);' \"\$FL\")\" = 1 ]" \
   "a lista de ABI do vendor exige o simbolo"
ok "o noinline nao foi para outra funcao" \
   "[ \"\$(n '^noinline\$' \"\$FL\")\" = 1 ]" "esperava exatamente 1"

# --- nada de 5.16 foi inventado aqui ------------------------------
ok "mm/folio-compat.c nao foi criado" \
   "[ ! -e \"\$KERNEL_DIR/mm/folio-compat.c\" ]" \
   "a arvore de folios e aditiva; esse arquivo nao deve existir"
ok "mm/Makefile nao ganhou entrada nova" \
   "[ ! -e \"\$KERNEL_DIR/mm/Makefile\" ] || [ \"\$(nc 'folio-compat' \"\$KERNEL_DIR/mm/Makefile\")\" = 0 ]" \
   "mm/Makefile foi mexido"

# --- invariantes dos estagios anteriores -------------------------
ok "__filemap_get_folio do G2.5d segue inteiro" \
   "grep -q '^struct folio \*__filemap_get_folio(struct address_space \*mapping, pgoff_t index,$' \"\$FL\"" "sumiu"
ok "filemap_get_folio do G2.5d segue inteiro" \
   "grep -q '^static inline struct folio \*filemap_get_folio(struct address_space \*mapping,$' \"\$PM\"" "sumiu"
ok "o ramo FGP_CREAT do G2.5d segue usando filemap_add_folio" \
   "grep -q 'err = filemap_add_folio(mapping, folio, index, gfp);' \"\$FL\"" "sumiu"
ok "filemap_alloc_folio do G2.5a segue inteiro" \
   "grep -q '^struct folio \*filemap_alloc_folio(gfp_t gfp, unsigned int order)\$' \"\$FL\"" "sumiu"
ok "mapping_get_entry do G2.5c segue inteiro" \
   "grep -q '^static void \*mapping_get_entry(struct address_space \*mapping, pgoff_t index)\$' \"\$FL\"" "sumiu"
ok "find_get_entry do G2.5c continua exportado" \
   "[ \"\$(ncd 'EXPORT_SYMBOL(find_get_entry);' \"\$FL\")\" = 1 ]" "perdeu o export"
ok "folio_mark_accessed do G2.5d segue inteiro" \
   "[ \"\$(ncd 'EXPORT_SYMBOL(folio_mark_accessed);' \"\$KERNEL_DIR/mm/swap.c\")\" = 1 ]" "sumiu"
ok "folio_test_writeback vem do PAGEFLAG, nao foi escrito a mao" \
   "grep -q '^TESTPAGEFLAG(Writeback, writeback, PF_NO_TAIL)\$' \"\$PF\"" \
   "o gerador do bit de writeback mudou"
ok "folio_wait_bit do G2.3f segue declarado" \
   "grep -q '^void __sched folio_wait_bit(struct folio \*folio, int bit_nr);\$' \"\$PM\"" "sumiu"

echo "G2.5e: todas as verificacoes passaram."
