#!/usr/bin/env bash
set -e

# Script de integração do KernelSU (Next) com opção de SUSFS
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$1" ]; then
    echo "Uso: $0 <caminho_do_kernel> [enable_susfs: true|false] [defconfig_path]"
    exit 1
fi
KERNEL_DIR="$(cd "$1" && pwd)"
ENABLE_SUSFS="${2:-true}"
CONFIG_FILE="${3:-$KERNEL_DIR/arch/arm64/configs/alioth_defconfig}"

echo "======================================================"
echo " Aplicando KernelSU (KernelSU-Next) no Kernel         "
echo " SUSFS Habilitado: $ENABLE_SUSFS                      "
echo " Defconfig: $CONFIG_FILE                              "
echo "======================================================"

# 1. Copiar diretório drivers/kernelsu
echo "[1/4] Copiando drivers/kernelsu (KernelSU-Next)..."
rm -rf "$KERNEL_DIR/drivers/kernelsu"
cp -r "$SCRIPT_DIR/drivers/kernelsu" "$KERNEL_DIR/drivers/kernelsu"

if [ "$ENABLE_SUSFS" = "true" ]; then
    # 2. Copiar arquivos do SUSFS
    echo "[2/4] Copiando arquivos fonte do SUSFS..."
    cp -f "$SCRIPT_DIR/fs/susfs.c" "$KERNEL_DIR/fs/susfs.c"
    cp -f "$SCRIPT_DIR/fs/sus_su.c" "$KERNEL_DIR/fs/sus_su.c"
    cp -f "$SCRIPT_DIR/include/linux/susfs.h" "$KERNEL_DIR/include/linux/susfs.h"
    cp -f "$SCRIPT_DIR/include/linux/susfs_def.h" "$KERNEL_DIR/include/linux/susfs_def.h"

    # 3. Aplicar patch de hooks do kernel
    echo "[3/4] Aplicando patches de hooks do SUSFS no Kernel..."
    cd "$KERNEL_DIR"
    if git apply --check "$SCRIPT_DIR/patches/ksu_susfs_hooks.patch" 2>/dev/null; then
        git apply "$SCRIPT_DIR/patches/ksu_susfs_hooks.patch"
    else
        echo "AVISO: tentando git apply com 3-way..."
        git apply -3 "$SCRIPT_DIR/patches/ksu_susfs_hooks.patch"
    fi
    cd - >/dev/null

    # 4. Habilitar configurações no defconfig
    echo "[4/4] Injetando configurações KSU + SUSFS no defconfig..."
    cat << 'EOF' >> "$CONFIG_FILE"
# KernelSU + SUSFS Complete Integration
CONFIG_KSU=y
CONFIG_KSU_LSM_SECURITY_HOOKS=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_OVERLAYFS=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAPS=y
CONFIG_FHANDLE=y
EOF

else
    echo "[2/4] Pulando arquivos do SUSFS (desabilitado)..."
    echo "[3/4] Pulando patch de hooks do SUSFS (desabilitado)..."
    echo "[4/4] Injetando configurações apenas de KernelSU (sem SUSFS)..."
    cat << 'EOF' >> "$CONFIG_FILE"
# KernelSU Integration (Without SUSFS)
CONFIG_KSU=y
CONFIG_KSU_LSM_SECURITY_HOOKS=y
CONFIG_FHANDLE=y
EOF
fi

echo "======================================================"
echo " Integração concluída com sucesso!                    "
echo "======================================================"
