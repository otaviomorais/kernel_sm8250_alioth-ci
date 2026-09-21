#!/bin/bash
# ==============================================================================
# Injeção de Otimizações de Kernel (BBR, ZSTD, Kyber, PSI)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="$1"
CONFIG_FILE="${2:-$KERNEL_DIR/arch/arm64/configs/alioth_defconfig}"

if [ -z "$KERNEL_DIR" ] || [ ! -d "$KERNEL_DIR" ]; then
    echo "ERRO: Diretório do kernel não especificado ou inexistente."
    echo "Uso: $0 <caminho-para-o-kernel> [caminho-para-o-defconfig]"
    exit 1
fi

KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"

echo "=== Aplicando Otimizações de Performance (BBR, ZSTD, Kyber) no defconfig ==="
echo "Defconfig alvo: $CONFIG_FILE"

if [ -f "$CONFIG_FILE" ]; then
    # Remover defaults conflitantes se existirem
    sed -i '/CONFIG_DEFAULT_CUBIC/d' "$CONFIG_FILE"
    sed -i '/CONFIG_DEFAULT_TCP_CONG/d' "$CONFIG_FILE"
    sed -i '/CONFIG_TCP_CONG_ADVANCED/d' "$CONFIG_FILE"

    cat "$SCRIPT_DIR/optimizations.config" >> "$CONFIG_FILE"
fi

# Definir ZSTD como compressor padrão nativo da zRAM no driver do kernel se aplicável
ZRAM_DRV="$KERNEL_DIR/drivers/block/zram/zram_drv.c"
if [ -f "$ZRAM_DRV" ] && grep -q 'static const char \*default_compressor = "lz4";' "$ZRAM_DRV"; then
    sed -i 's/static const char \*default_compressor = "lz4";/static const char \*default_compressor = "zstd";/' "$ZRAM_DRV"
    echo "Driver zram atualizado para zstd por padrão."
fi

echo "Otimizações injetadas com sucesso em $CONFIG_FILE e drivers!"
