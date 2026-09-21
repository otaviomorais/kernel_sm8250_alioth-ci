#!/bin/bash
# ==============================================================================
# Script de aplicação do Droidspaces no Kernel Xiaomi SM8250 (Alioth)
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

echo "=== Aplicando Suporte ao Droidspaces no Kernel em $KERNEL_DIR ==="

cd "$KERNEL_DIR"

# 1. Aplicar patch de fix do cgroup (necessário para compatibilidade com Droidspaces / LXC)
echo "[1/2] Aplicando patch de prefixo cgroup para Droidspaces..."
PATCH_FILE="$SCRIPT_DIR/patches/01.fix_restore_cgroup_file_prefix_handling.patch"
if git apply --check "$PATCH_FILE" 2>/dev/null; then
    git apply "$PATCH_FILE"
    echo "Patch cgroup aplicado com sucesso!"
else
    echo "Tentando aplicar patch com patch -p1..."
    patch -p1 < "$PATCH_FILE" || echo "AVISO: Patch já aplicado ou incompatível."
fi

# 2. Injetar configurações do Droidspaces no alioth_defconfig
echo "[2/2] Injetando configurações Droidspaces no alioth_defconfig..."
CONFIG_FILE="$KERNEL_DIR/arch/arm64/configs/alioth_defconfig"

# Remover possíveis flags conflitantes
sed -i '/CONFIG_ANDROID_PARANOID_NETWORK/d' "$CONFIG_FILE"

cat "$SCRIPT_DIR/droidspaces.config" >> "$CONFIG_FILE"

cd - >/dev/null

echo "======================================================"
echo " Suporte ao Droidspaces integrado com sucesso!        "
echo "======================================================"
