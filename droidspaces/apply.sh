#!/bin/bash
# ==============================================================================
# Script de aplicação do Droidspaces no Kernel Xiaomi SM8250 (Alioth)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIG_PWD="$(pwd)"
KERNEL_ARG="$1"
CONFIG_ARG="$2"
DROID_CONFIG_ARG="$3"

if [ -z "$KERNEL_ARG" ] || [ ! -d "$KERNEL_ARG" ]; then
    echo "ERRO: Diretório do kernel não especificado ou inexistente."
    echo "Uso: $0 <caminho-para-o-kernel> [caminho-para-o-defconfig] [arquivo-de-config-droidspaces]"
    exit 1
fi

# Arquivo de configurações Droidspaces (full por padrão; ex: droidspaces-minimal.config)
if [ -n "$DROID_CONFIG_ARG" ]; then
    case "$DROID_CONFIG_ARG" in
        /*) DROIDSPACES_CONFIG="$DROID_CONFIG_ARG" ;;
        *) DROIDSPACES_CONFIG="$ORIG_PWD/$DROID_CONFIG_ARG" ;;
    esac
else
    DROIDSPACES_CONFIG="$SCRIPT_DIR/droidspaces.config"
fi

if [ ! -f "$DROIDSPACES_CONFIG" ]; then
    echo "FATAL: Arquivo de config Droidspaces $DROIDSPACES_CONFIG não encontrado."
    exit 1
fi

KERNEL_DIR="$(cd "$KERNEL_ARG" && pwd)"

# Resolve CONFIG_FILE para caminho absoluto ANTES de qualquer cd.
# Aceita path relativo (ao cwd original) ou absoluto, com fallback vendor/ -> raiz.
if [ -n "$CONFIG_ARG" ]; then
    case "$CONFIG_ARG" in
        /*) CONFIG_FILE="$CONFIG_ARG" ;;
        *) CONFIG_FILE="$ORIG_PWD/$CONFIG_ARG" ;;
    esac
else
    if [ -f "$KERNEL_DIR/arch/arm64/configs/vendor/alioth_defconfig" ]; then
        CONFIG_FILE="$KERNEL_DIR/arch/arm64/configs/vendor/alioth_defconfig"
    else
        CONFIG_FILE="$KERNEL_DIR/arch/arm64/configs/alioth_defconfig"
    fi
fi

echo "Arquivo Droidspaces: $DROIDSPACES_CONFIG"
echo "=== Aplicando Suporte ao Droidspaces no Kernel em $KERNEL_DIR ==="
echo "Defconfig alvo: $CONFIG_FILE"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "FATAL: Arquivo defconfig $CONFIG_FILE não encontrado."
    exit 1
fi

# 1. Aplicar patch de fix do cgroup (necessário para compatibilidade com Droidspaces / LXC)
echo "[1/2] Aplicando patch de prefixo cgroup para Droidspaces..."
PATCH_FILE="$SCRIPT_DIR/patches/01.fix_restore_cgroup_file_prefix_handling.patch"
if (cd "$KERNEL_DIR" && git apply --check "$PATCH_FILE" 2>/dev/null); then
    (cd "$KERNEL_DIR" && git apply "$PATCH_FILE")
    echo "Patch cgroup aplicado com sucesso!"
else
    echo "AVISO: Patch cgroup já integrado nativamente na árvore ou não aplicável diretamente. Prosseguindo."
fi

# 2. Injetar configurações do Droidspaces no defconfig
echo "[2/2] Injetando configurações Droidspaces no defconfig..."

# Remove entradas conflitantes/duplicadas antes do append.
# Extrai todos os símbolos do arquivo Droidspaces selecionado
# (CONFIG_X=y e "# CONFIG_X is not set") para garantir que o append
# seja a última ocorrência (vence no Kconfig).
# IMPORTANTE: só mexe nos símbolos presentes no arquivo selecionado.
while IFS= read -r line || [ -n "$line" ]; do
    sym=""
    case "$line" in
        CONFIG_*=*) sym=$(echo "$line" | sed -n 's/^CONFIG_\([A-Za-z0-9_]*\)=.*/\1/p') ;;
        "# CONFIG_"*" is not set") sym=$(echo "$line" | sed -n 's/^# CONFIG_\([A-Za-z0-9_]*\) is not set/\1/p') ;;
    esac
    if [ -n "$sym" ]; then
        # Match the complete symbol name; CONFIG_NET must not remove CONFIG_NETDEVICES.
        sed -i \
            -e "/^CONFIG_${sym}=/d" \
            -e "/^# CONFIG_${sym} is not set$/d" \
            "$CONFIG_FILE"
    fi
done < "$DROIDSPACES_CONFIG"

cat "$DROIDSPACES_CONFIG" >> "$CONFIG_FILE"

# Fail-fast: se USER_NS não entrou, o build não deve prosseguir silenciosamente
if ! grep -q "^CONFIG_USER_NS=y" "$CONFIG_FILE"; then
    echo "FATAL: CONFIG_USER_NS=y não encontrado em $CONFIG_FILE após injeção."
    exit 1
fi

echo "Verificação Droidspaces no defconfig:"
grep -E "^CONFIG_(USER_NS|NAMESPACES|PID_NS|UTS_NS|IPC_NS|NET_NS|OVERLAY_FS|BINFMT_MISC|CFS_BANDWIDTH)=y" "$CONFIG_FILE" || true
echo "Configurações do Droidspaces injetadas com sucesso em $CONFIG_FILE"

echo "======================================================"
echo " Suporte ao Droidspaces integrado com sucesso!        "
echo "======================================================"
