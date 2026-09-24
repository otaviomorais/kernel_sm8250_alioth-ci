# KernelSU-Next legacy + SUSFS v2.3 (UAPI 2)

This is the pinned non-GKI KernelSU-Next/SUSFS path used by the recovery
baseline. It is intentionally separate from the older `kernelsu/apply_e404.sh`
path. The UAPI 2 image has booted and passed the device smoke test; keep the
known-good UAPI 2 release as the recovery baseline until a replacement has
passed the same test.

## Pinned inputs

- KernelSU-Next non-GKI legacy commit:
  `f6a1570cc7857141b8acef9b3073840f59539359`.
- SUSFS source: `simonpunk/susfs4ksu`, commit
  `b1de873fff29c3e1eebe643d6cab94af91f07217`, with
  `SUSFS_VERSION "v2.3.0"`.
- The bridge copies the KSU sibling `uapi/` directory as well as `kernel/`;
  the legacy source uses a relative `kernel/include/uapi` link.
- The CI validates the actual UAPI header and uses `KSU_VERSION_OVERRIDE=33194`.
  The matching manager line for this recovery stack is v3.3.0. Do not replace
  it with the UAPI 4 manager experiment.

## Intentional differences from the legacy-v1 baseline

- `CONFIG_KSU_MANUAL_HOOK=y`.
- `CONFIG_KSU_KPROBES_HOOK` and `CONFIG_KSU_SYSCALL_TABLE_HOOK` are disabled.
- SUSFS v2.3 command bridge, zygote unmount integration, SUSFS initialization,
  and sdcard monitor are enabled.
- The source and manager line are pinned; do not accept a different checkout
  silently.

## DroidSpaces final build

Use the `full` DroidSpaces profile for the one-shot final integration. It
contains the complete cumulative chain that was previously validated in
separate builds:

`MEMCG -> CGROUP_PIDS -> CGROUP_DEVICE -> POSIX_MQUEUE -> BINFMT_MISC -> NAT`

The profile also declares the E404 namespace and Netfilter prerequisites
explicitly and intentionally excludes unvalidated extras such as NF_TABLES,
MACVLAN/IPVLAN and CFS bandwidth scheduling. The historical `minimal`,
`memcg-safe`, and incremental `memcg-full-*` profiles remain available for
bisecting a regression.

The failed UAPI 4 path and its source-compatibility patch are not part of this
integration and must not be reintroduced into the workflow.
