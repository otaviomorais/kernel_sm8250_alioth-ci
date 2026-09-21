# Alioth Kernel CI Builder (AOSP 16) 🚀

Repositório automatizado com **GitHub Actions** para compilar e empacotar continuamente o kernel do **POCO F3 / Redmi K40 (alioth)** diretamente da base oficial upstream [PocoF3Releases/kernel_xiaomi_sm8250 (branch `aosp-16`)](https://github.com/PocoF3Releases/kernel_xiaomi_sm8250/tree/aosp-16).

---

## 📦 Artefatos Gerados em Cada Release

A cada compilação (automática ou manual), uma nova Release é gerada no repositório contendo:

1. **`AnyKernel3-Alioth-aosp16-<commit>.zip`**
   - Pacote flashável via **Recovery (TWRP / OrangeFox)** ou direto pelo app do **KernelSU / Magisk**.
   - Preserva o ramdisk original da sua ROM (EvolutionX, LineageOS, crDroid, AOSP 16, etc.), substitui o kernel (`Image`), `dtb` e grava a partição `dtbo`.
2. **`boot.img`**
   - Imagem de boot completa já reempacotada com o kernel e dtb novos para flash via Fastboot.
3. **`dtbo.img`**
   - Imagem de device-tree overlay compilada a partir da fonte.
4. **`Image`**
   - Binário puro do kernel para desenvolvedores ou ferramentas de boot customizadas.

---

## ⚡ Atualização Contínua (Sempre na Base Upstream)

- **Verificação Diária:** Um cron job roda todos os dias às 03:00 UTC. Ele consulta a API do GitHub e compara o último commit da branch `aosp-16` da PocoF3Releases. Se houver novidades, compila e gera uma nova release automaticamente!
- **Execução Manual (On-Demand):** Você pode disparar a compilação a qualquer momento na aba **Actions -> Run workflow**.

---

## 🛡️ KernelSU + SUSFS Integrado (Aurora)

O workflow integra nativamente o **KernelSU-Next + SUSFS completo** portado do seu repositório [aurora-kernel_alioth](https://github.com/otaviomorais/aurora-kernel_alioth), contendo:
- `drivers/kernelsu/` com suporte a `ksud` embutido e hooks LSM.
- `fs/susfs.c` com proteção de montagens (`sus_mount`), ocultação de paths (`sus_path`) e try_umount.
- Totalmente compatível com detecções de root modernas e módulos.
- Pode ser desativado ou ativado pelo seletor ao disparar a Action manualmente.

---

## 📲 Como Instalar (Métodos de Flash)

### Método 1: Via Recovery (TWRP / OrangeFox) — *Recomendado*
1. Baixe o arquivo `AnyKernel3-Alioth-aosp16-<commit>.zip` da [Aba de Releases](https://github.com/otaviomorais/kernel_sm8250_alioth-ci/releases).
2. Reinicie no recovery (TWRP ou OrangeFox).
3. Vá em **Install**, selecione o zip e confirme o deslize.
4. Reinicie o sistema.

### Método 2: Via Fastboot
1. Baixe os arquivos `boot.img` e `dtbo.img` da release desejada.
2. Reinicie o aparelho em modo Fastboot (`Power + Volume Menos`).
3. Conecte ao computador ou Termux e execute:
   ```bash
   fastboot flash boot boot.img
   fastboot flash dtbo dtbo.img
   fastboot reboot
   ```

---

## ⚙️ Opções do Workflow Manual

Ao clicar em **Actions -> Build Alioth Kernel (AOSP 16) -> Run workflow**:

| Parâmetro | Tipo | Padrão | Descrição |
|-----------|------|--------|-----------|
| `enable_ksu` | boolean | `true` | Ativa/desativa integração do KernelSU |
| `force_build` | boolean | `true` | Força a compilação mesmo se não houver novos commits |
| `enable_droidspaces` | boolean | `true` | Habilita suporte completo ao Droidspaces (LXC, binfmt_misc, cgroups, veth) |
| `custom_boot_url` | string | `""` | Link direto de um boot.img específico da sua ROM para injetar o kernel |
