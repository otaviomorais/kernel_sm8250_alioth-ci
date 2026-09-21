#!/bin/bash
# ==============================================================================
# Script de aplicação do Droidspaces no Kernel Xiaomi SM8250 (Alioth)
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

echo "=== Aplicando Suporte ao Droidspaces no Kernel em $KERNEL_DIR ==="
echo "Defconfig alvo: $CONFIG_FILE"

cd "$KERNEL_DIR"

# 1. Aplicar patch de fix do cgroup (necessário para compatibilidade com Droidspaces / LXC)
echo "[1/2] Aplicando patch de prefixo cgroup para Droidspaces..."
PATCH_FILE="$SCRIPT_DIR/patches/01.fix_restore_cgroup_file_prefix_handling.patch"
if git apply --check "$PATCH_FILE" 2>/dev/null; then
    git apply "$PATCH_FILE"
    echo "Patch cgroup aplicado com sucesso!"
else
    echo "AVISO: Patch cgroup já integrado nativamente na árvore ou não aplicável diretamente. Prosseguindo."
fi

# 2. Injetar configurações do Droidspaces no defconfig
echo "[2/2] Injetando configurações Droidspaces no defconfig..."
if [ -f "$CONFIG_FILE" ]; then
    sed -i '/CONFIG_ANDROID_PARANOID_NETWORK/d' "$CONFIG_FILE"
    cat "$SCRIPT_DIR/droidspaces.config" >> "$CONFIG_FILE"
    echo "Configurações do Droidspaces injetadas com sucesso em $CONFIG_FILE"
else
    echo "AVISO: Arquivo defconfig $CONFIG_FILE não encontrado."
fi

cd - >/dev/null

echo "======================================================"
echo " Suporte ao Droidspaces integrado com sucesso!        "
echo "======================================================"
