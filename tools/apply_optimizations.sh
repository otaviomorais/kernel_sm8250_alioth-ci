#!/bin/bash
# ==============================================================================
# Injeção de Otimizações de Kernel (BBR, ZSTD, Kyber, PSI)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="$1"

if [ -z "$KERNEL_DIR" ] || [ ! -d "$KERNEL_DIR" ]; then
    echo "ERRO: Diretório do kernel não especificado ou inexistente."
    echo "Uso: $0 <caminho-para-o-kernel>"
    exit 1
fi

KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
CONFIG_FILE="$KERNEL_DIR/arch/arm64/configs/alioth_defconfig"

echo "=== Aplicando Otimizações de Performance (BBR, ZSTD, Kyber) no defconfig ==="

# Remover defaults conflitantes se existirem
sed -i '/CONFIG_DEFAULT_CUBIC/d' "$CONFIG_FILE"
sed -i '/CONFIG_DEFAULT_TCP_CONG/d' "$CONFIG_FILE"

cat "$SCRIPT_DIR/optimizations.config" >> "$CONFIG_FILE"
echo "Otimizações injetadas com sucesso em $CONFIG_FILE!"
