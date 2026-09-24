# MagicTime EEVDF/CASS — port experimental

Este diretório mantém o port experimental de **EEVDF + CASS com remoção de
WALT** para a base AOSP16 do Alioth. Ele não altera o build diário, a `main` nem
os perfis `default`, `minimal` e `lxc` existentes.

## Fontes e escopo

- Base AOSP16: `PocoF3Releases/kernel_xiaomi_sm8250` no commit
  `10f8a106de65d4fb5cd9c2f2fe2714f11d97bcd5`.
- Referência MagicTime: `TIMISONG-dev/kernel_xiaomi_sm8250`, branch
  `magictime-new`, commit `eba8dbd9d11b479cae68918826c344065a6b5d3c`.
- Base comum usada para preparar a série:
  `a28b116d7545dd4d5c4b52becfcb803bb135c243`.

A série é aplicada como patches sobre a árvore AOSP16. Não substitui a árvore
AOSP16 inteira nem copia a árvore do MagicTime. As diferenças de ABI do
scheduler são mantidas do lado AOSP16; apenas os hunks coordenados de
EEVDF/CASS/WALT são portados.

## WALT

A desativação de WALT faz parte da mesma unidade do port:

1. O objeto e os símbolos `SCHED_WALT` saem do Makefile/Kconfig.
2. Os campos, hooks, tracepoints e sysctls exclusivamente de WALT são removidos
   ou protegidos no conjunto scheduler portado.
3. Os chamadores vendor que dependiam de `set_task_boost`,
   `sched_set_refresh_rate` ou `sched_update_cpu_freq_min_max` são adaptados
   somente quando necessário.
4. O `.config` final falha se `CONFIG_SCHED_WALT=y`,
   `CONFIG_SCHED_TUNE=y` ou `CONFIG_SCHED_CORE_CTL=y`.

A remoção física dos arquivos WALT é incluída no primeiro patch da série. A
auditoria final ainda deve confirmar que não há objetos WALT, referências
vendor ou interfaces de userspace que dependam desses campos.

## Configuração

`magictime-eeVdf-cass.config` habilita:

- `CONFIG_SCHED_CASS=y`;
- `CONFIG_SCHED_THERMAL_PRESSURE=y`;
- uClamp task/group;
- as extensões opcionais `RT_SOFTIRQ_AWARE_SCHED` e `UCLAMP_ASSIST`.

`FAIR_GROUP_SCHED`, `CFS_BANDWIDTH` e `RT_GROUP_SCHED` não são desligados
silenciosamente. A interação entre eles e EEVDF precisa de uma matriz de
build/teste própria. `NTSYNC` é um port separado e não faz parte deste
perfil.

## Gate de validação

O workflow manual deve:

1. aplicar a série em um checkout AOSP16 completo;
2. gerar a configuração e executar `validate-config.sh`;
3. compilar primeiro `kernel/sched/` e depois `Image dtbs dtbo.img`;
4. verificar que não existem `walt.o`, `boost.o`, `sched_avg.o`, `tune.o` ou
   `core_ctl.o`;
5. testar boot, Binder, cgroups, RT, thermal pressure, hotplug, suspend e
   benchmarks em aparelho real.

Nenhum release é criado pelo workflow experimental. A promoção só deve
ocorrer depois dos gates de build e runtime.
