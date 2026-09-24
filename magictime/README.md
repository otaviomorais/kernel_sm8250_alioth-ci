# MagicTime + KernelSU-Next/SUSFS

Este branch agora tem um workflow experimental para compilar diretamente a
source [`TIMISONG-dev/kernel_xiaomi_sm8250`](https://github.com/TIMISONG-dev/kernel_xiaomi_sm8250/tree/magictime-new),
substituindo o port AOSP16/EEVDF-CASS anterior. O `main`, o build diário e o
workflow estável não são alterados.

## Source e pin

- Source: `TIMISONG-dev/kernel_xiaomi_sm8250`
- Branch: `magictime-new`
- Commit usado pelo CI: `eba8dbd9d11b479cae68918826c344065a6b5d3c`
- Perfil de containers: `none` ou `lxc` via `workflow_dispatch`

O pin é intencional para que uma execução possa ser reproduzida. Uma atualização
do kernel exige revisar e testar o commit MagicTime explicitamente no workflow.

## KernelSU

A source MagicTime contém um submódulo `KernelSU` e um symlink
`drivers/kernelsu` para essa cópia. O pipeline:

1. checkout do commit MagicTime sem inicializar o submódulo;
2. remove `KernelSU`, `drivers/kernelsu`, a fiação KSU e os hooks KSU manuais
   da própria source usando `remove-magictime-kernelsu-hooks.patch`;
3. copia o KernelSU-Next e os arquivos SUSFS que estão em `kernelsu/`;
4. aplica `magictime/patches/ksu-susfs-magictime.patch`, adaptado à API/filesystem
   da source MagicTime (a ordem está em `magictime/patches/series-ksu-next`);
5. injeta as opções KernelSU-Next/SUSFS no defconfig e valida o `.config` final.

O `kernelsu/apply.sh` continua compatível com o workflow estável: o quarto
argumento é opcional e, quando ausente, usa o patch original do `main`.

## Gate de CI

O workflow manual executa:

1. o cleanup do KernelSU embutido e a instalação do KernelSU-Next + SUSFS;
2. a geração do `.config` e a validação de todos os símbolos KSU/SUSFS;
3. opcionalmente a aplicação e validação do perfil LXC/nspawn;
4. a compilação de `Image`, `dtbs` e `dtbo.img` usando GitHub Actions;
5. a verificação dos objetos `kernelsu.o` e `susfs.o`;
6. a coleta e o upload de `Image`, `dtb`, `dtbo.img`, configuração, revisão da
   source e AnyKernel3.

Não são feitos builds locais do kernel. O workflow é manual-only e não cria
release.

## Escopo do scheduler

A source MagicTime é usada como está; portanto seus recursos de scheduler e
WALT/schedtune/core-control fazem parte do build desta nova direção. A série
antiga `magictime/patches/0001-walt-eevdf-cass-core.patch` e os scripts
`apply-scheduler-patches.sh`/`validate-config.sh` permanecem apenas como
material histórico do port AOSP16 e não são chamados pelo workflow ativo.

`NTSYNC` continua fora do escopo deste workflow.

## Promoção

Build, configuração e artefatos não substituem testes de boot. Antes de promover
qualquer resultado, é necessário flashear e testar em um aparelho Alioth:
estabilidade, Binder, cgroups, prioridades RT, pressão térmica, hotplug,
suspend e o comportamento de `nspawn`/LXC.
