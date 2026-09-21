#!/usr/bin/env bash
set -e

# Script de integração do SUSFS sobre o KernelSU nativo do E404 (Kowsu / backslashxx)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$1" ]; then
    echo "Uso: $0 <caminho_do_kernel> [enable_susfs: true|false] [defconfig_path]"
    exit 1
fi
KERNEL_DIR="$(cd "$1" && pwd)"
ENABLE_SUSFS="${2:-true}"
CONFIG_FILE="${3:-$KERNEL_DIR/arch/arm64/configs/vendor/alioth_defconfig}"

echo "======================================================"
echo " Configurando KernelSU nativo do E404 (Kowsu)         "
echo " SUSFS Habilitado: $ENABLE_SUSFS                      "
echo " Defconfig: $CONFIG_FILE                              "
echo "======================================================"

# 1. Garantir que o submódulo KernelSU do E404 esteja presente
echo "[1/4] Verificando integridade do KernelSU nativo (Kowsu)..."
cd "$KERNEL_DIR"
if [ ! -d "KernelSU/kernel" ]; then
    echo "Inicializando submódulo KernelSU..."
    git submodule update --init --recursive KernelSU || git clone --depth 1 https://github.com/backslashxx/KernelSU KernelSU
fi

# Garantir symlink drivers/kernelsu -> ../KernelSU/kernel
if [ ! -e "drivers/kernelsu" ]; then
    ln -sf ../KernelSU/kernel drivers/kernelsu
fi
cd - >/dev/null

if [ "$ENABLE_SUSFS" = "true" ]; then
    # 2. Copiar arquivos do SUSFS para o Kernel
    echo "[2/4] Copiando arquivos fonte do SUSFS..."
    cp -f "$SCRIPT_DIR/fs/susfs.c" "$KERNEL_DIR/fs/susfs.c"
    cp -f "$SCRIPT_DIR/fs/sus_su.c" "$KERNEL_DIR/fs/sus_su.c"
    cp -f "$SCRIPT_DIR/include/linux/susfs.h" "$KERNEL_DIR/include/linux/susfs.h"
    cp -f "$SCRIPT_DIR/include/linux/susfs_def.h" "$KERNEL_DIR/include/linux/susfs_def.h"

    # 3. Aplicar hooks do SUSFS no Kernel (fs, include, kernel)
    echo "[3/4] Aplicando patches de hooks do SUSFS no Kernel..."
    cd "$KERNEL_DIR"
    if git apply --check "$SCRIPT_DIR/patches/e404_ksu_susfs_hooks.patch" 2>/dev/null; then
        git apply "$SCRIPT_DIR/patches/e404_ksu_susfs_hooks.patch"
    else
        echo "AVISO: tentando git apply com 3-way..."
        git apply -3 "$SCRIPT_DIR/patches/e404_ksu_susfs_hooks.patch"
    fi
    cd - >/dev/null

    # 4. Integrar suporte do SUSFS no próprio KernelSU (Kowsu)
    echo "[4/4] Injetando compatibilidade do SUSFS no KernelSU (Kowsu)..."
    cd "$KERNEL_DIR/KernelSU"
    if git apply --check "$SCRIPT_DIR/patches/kowsu_susfs.patch" 2>/dev/null; then
        git apply "$SCRIPT_DIR/patches/kowsu_susfs.patch"
        echo "Patch SUSFS aplicado no Kowsu com sucesso!"
    else
        echo "Aplicando patch no Kowsu via git apply 3-way/patch..."
        git apply -3 "$SCRIPT_DIR/patches/kowsu_susfs.patch" || patch -p1 < "$SCRIPT_DIR/patches/kowsu_susfs.patch" || true
    fi
    cd - >/dev/null

    # Injetar configurações do SUSFS no defconfig
    echo "Ativando flags do SUSFS no defconfig..."
    sed -i '/CONFIG_KSU_SUSFS/d' "$CONFIG_FILE"
    cat << 'EOF' >> "$CONFIG_FILE"
# KernelSU (Kowsu) + SUSFS Integration
CONFIG_KSU=y
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
    echo "[3/4] Pulando patch de hooks do SUSFS no Kernel (desabilitado)..."
    echo "[4/4] Mantendo KernelSU nativo (Kowsu) original sem SUSFS..."
    sed -i '/CONFIG_KSU_SUSFS/d' "$CONFIG_FILE"
fi

echo "======================================================"
echo " Integração E404 concluída com sucesso!               "
echo "======================================================"
