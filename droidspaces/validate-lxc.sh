#!/bin/sh
# Validate the kernel options required by nspawn.sh with --net.
# Usage: validate-lxc.sh <path-to-final-.config>
set -eu

CONFIG_FILE="${1:-}"
if [ -z "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ]; then
    echo "Usage: $0 <path-to-.config>" >&2
    exit 2
fi

# Namespaces, IPC, pseudo-filesystems, cgroup2 and networking primitives.
REQUIRED_SYMBOLS="
NAMESPACES
UTS_NS
IPC_NS
USER_NS
PID_NS
NET_NS
SYSVIPC
POSIX_MQUEUE
PROC_FS
SYSFS
TMPFS
SHMEM
CGROUPS
SYSCTL
NET
NETDEVICES
NET_CORE
INET
IPV6
VETH
BRIDGE
IP_ADVANCED_ROUTER
IP_MULTIPLE_TABLES
IPV6_MULTIPLE_TABLES
NETFILTER
NETFILTER_XTABLES
NF_CONNTRACK
NF_NAT
NF_NAT_IPV4
NF_NAT_IPV6
NETFILTER_XT_NAT
IP_NF_IPTABLES
IP_NF_FILTER
IP_NF_NAT
IP_NF_TARGET_MASQUERADE
IP6_NF_IPTABLES
IP6_NF_FILTER
IP6_NF_NAT
IP6_NF_TARGET_MASQUERADE
"

missing=0
for symbol in $REQUIRED_SYMBOLS; do
    if ! grep -q "^CONFIG_${symbol}=y$" "$CONFIG_FILE"; then
        echo "MISSING: CONFIG_${symbol}=y" >&2
        missing=1
    fi
done

if [ "$missing" -ne 0 ]; then
    echo "Perfil LXC/nspawn incompleto no .config final." >&2
    exit 1
fi

echo "Perfil LXC/nspawn validado no .config final."
