#!/usr/bin/env bash
set -e

# Script de integração do KernelSU-Next com SUSFS no Kernel E404 BPF (staging-bpf)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$1" ]; then
    echo "Uso: $0 <caminho_do_kernel> [enable_susfs: true|false] [defconfig_path]"
    exit 1
fi
KERNEL_DIR="$(cd "$1" && pwd)"
ENABLE_SUSFS="${2:-true}"
CONFIG_FILE="${3:-$KERNEL_DIR/arch/arm64/configs/vendor/alioth_defconfig}"

echo "======================================================"
echo " Aplicando KernelSU-Next no Kernel E404 BPF           "
echo " SUSFS Habilitado: $ENABLE_SUSFS                      "
echo " Defconfig: $CONFIG_FILE                              "
echo "======================================================"

# 1. Substituir o submódulo/symlink Kowsu pelo KernelSU-Next limpo
echo "[1/4] Substituindo Kowsu pelo KernelSU-Next em drivers/kernelsu..."
rm -rf "$KERNEL_DIR/KernelSU"
rm -rf "$KERNEL_DIR/drivers/kernelsu"
cp -r "$SCRIPT_DIR/drivers/kernelsu" "$KERNEL_DIR/drivers/kernelsu"

# 2. Copiar arquivos do SUSFS para o Kernel se habilitado
if [ "$ENABLE_SUSFS" = "true" ]; then
    echo "[2/4] Copiando arquivos fonte do SUSFS..."
    cp -f "$SCRIPT_DIR/fs/susfs.c" "$KERNEL_DIR/fs/susfs.c"
    cp -f "$SCRIPT_DIR/fs/sus_su.c" "$KERNEL_DIR/fs/sus_su.c"
    cp -f "$SCRIPT_DIR/include/linux/susfs.h" "$KERNEL_DIR/include/linux/susfs.h"
    cp -f "$SCRIPT_DIR/include/linux/susfs_def.h" "$KERNEL_DIR/include/linux/susfs_def.h"
else
    echo "[2/4] Pulando cópia de arquivos fonte do SUSFS (desabilitado)..."
fi

# 3. Aplicar hooks do KernelSU-Next e SUSFS no Kernel (fs, include, kernel)
echo "[3/4] Aplicando patches de hooks do KernelSU-Next e SUSFS no Kernel..."
cd "$KERNEL_DIR"
if git apply --check "$SCRIPT_DIR/patches/e404_ksu_susfs_hooks.patch" 2>/dev/null; then
    git apply "$SCRIPT_DIR/patches/e404_ksu_susfs_hooks.patch"
    echo "Patch aplicado com sucesso via git apply!"
else
    echo "AVISO: tentando git apply com 3-way..."
    git apply -3 "$SCRIPT_DIR/patches/e404_ksu_susfs_hooks.patch" || patch -p1 < "$SCRIPT_DIR/patches/e404_ksu_susfs_hooks.patch"
fi
cd - >/dev/null

# 4. Injetar configurações limpas do KernelSU-Next no defconfig
echo "[4/4] Injetando configurações limpas do KernelSU-Next no defconfig..."
# Remover configurações antigas do Kowsu (especialmente CONFIG_KSU_TAMPER_SYSCALL_TABLE)
sed -i '/CONFIG_KSU/d' "$CONFIG_FILE"
sed -i '/CONFIG_FHANDLE/d' "$CONFIG_FILE"

if [ "$ENABLE_SUSFS" = "true" ]; then
    cat << 'EOF' >> "$CONFIG_FILE"
# KernelSU-Next + SUSFS Integration
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
    cat << 'EOF' >> "$CONFIG_FILE"
# KernelSU-Next Integration (Without SUSFS)
CONFIG_KSU=y
CONFIG_KSU_LSM_SECURITY_HOOKS=y
CONFIG_FHANDLE=y
EOF
fi

echo "======================================================"
echo " Integração KernelSU-Next no E404 concluída com sucesso!"
echo "======================================================"
