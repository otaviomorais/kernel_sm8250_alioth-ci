#!/usr/bin/env bash
set -e

# Script de integração do KernelSU + SUSFS do Aurora Kernel no Alioth AOSP 16
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="$1"

if [ -z "$KERNEL_DIR" ]; then
    echo "Uso: $0 <caminho_do_kernel>"
    exit 1
fi

echo "======================================================"
echo " Aplicando KernelSU (KernelSU-Next) + SUSFS no Kernel "
echo "======================================================"

# 1. Copiar diretório drivers/kernelsu
echo "[1/4] Copiando drivers/kernelsu..."
rm -rf "$KERNEL_DIR/drivers/kernelsu"
cp -r "$SCRIPT_DIR/drivers/kernelsu" "$KERNEL_DIR/drivers/kernelsu"

# 2. Copiar arquivos do SUSFS
echo "[2/4] Copiando arquivos fonte do SUSFS..."
cp -f "$SCRIPT_DIR/fs/susfs.c" "$KERNEL_DIR/fs/susfs.c"
cp -f "$SCRIPT_DIR/fs/sus_su.c" "$KERNEL_DIR/fs/sus_su.c"
cp -f "$SCRIPT_DIR/include/linux/susfs.h" "$KERNEL_DIR/include/linux/susfs.h"
cp -f "$SCRIPT_DIR/include/linux/susfs_def.h" "$KERNEL_DIR/include/linux/susfs_def.h"

# 3. Aplicar patch de hooks do kernel
echo "[3/4] Aplicando patches de hooks do Kernel (fs, include, drivers)..."
cd "$KERNEL_DIR"
git apply --check "$SCRIPT_DIR/patches/ksu_susfs_hooks.patch" || {
    echo "AVISO: git apply --check falhou, tentando git apply com 3-way..."
    git apply -3 "$SCRIPT_DIR/patches/ksu_susfs_hooks.patch"
}
git apply "$SCRIPT_DIR/patches/ksu_susfs_hooks.patch"

# 4. Habilitar configurações no defconfig
echo "[4/4] Injetando configurações KSU + SUSFS no alioth_defconfig..."
CONFIG_FILE="$KERNEL_DIR/arch/arm64/configs/alioth_defconfig"

cat << 'EOF' >> "$CONFIG_FILE"
# KernelSU + SUSFS (Aurora Integration)
CONFIG_KSU=y
CONFIG_KSU_LSM_SECURITY_HOOKS=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_PROC_CHILDREN=y
CONFIG_FHANDLE=y
EOF

echo "======================================================"
echo " KernelSU + SUSFS aplicado com sucesso no Kernel!    "
echo "======================================================"
