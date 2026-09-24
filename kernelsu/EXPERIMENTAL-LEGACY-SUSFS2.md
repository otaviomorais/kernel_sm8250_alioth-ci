# Experimental: KernelSU-Next legacy + SUSFS v2.3

This path is isolated from the known-good `kernelsu/apply_e404.sh` integration.
Do not use it for the recovery baseline until the image has booted and passed
an ADB smoke test.

## Pinned inputs

- KernelSU-Next non-GKI legacy commit: `f6a1570cc7857141b8acef9b3073840f59539359`
  (`legacy: non-GKI update — execveat (new bionic), hardening fixes, syscall table hooking scheme`).
- SUSFS source: GitLab `simonpunk/susfs4ksu`, branch line `gki-android12-5.10`,
  commit `b1de873fff29c3e1eebe643d6cab94af91f07217`, with
  `SUSFS_VERSION "v2.3.0"`.
- The KernelSU bridge patch is based on the public
  `ksun-legacy-susfs-v2.3.0.patch` port and is adapted only for the f6a1570c
  Kconfig layout.
- `e404-ksu-legacy-manual-hooks.patch` supplies the small non-GKI syscall/manual
  hook set required by the f6a legacy source. It is not the old Kowsu patch.
- The integration copies the KSU sibling `uapi/` directory as well as
  `kernel/`; f6a1570c uses a relative `kernel/include/uapi` link that would
  otherwise break after relocation into `drivers/kernelsu`.
- The CI sets `KSU_VERSION_OVERRIDE=33194`, the version calculated from the
  pinned f6a1570c source. This is above the v3.4.0 manager's minimum UAPI
  kernel version (`33188`) while keeping the source commit itself pinned.

## Intentional differences from the functional build

- `CONFIG_KSU_MANUAL_HOOK=y`.
- `CONFIG_KSU_KPROBES_HOOK` and `CONFIG_KSU_SYSCALL_TABLE_HOOK` are disabled.
- SUSFS v2.3 command bridge, zygote unmount integration, SUSFS initialization,
  and sdcard monitor are enabled.
- The manager is expected to be the matching KernelSU-Next v3.4.0 manager. Do
  not install that manager on the current functional v1.x kernel.

The original experimental workflow option is `legacy-susfs2-experimental`
(KSU UAPI 2, the build already validated on the device). The updated option
`legacy-susfs2-uapi4-experimental` uses KSU commit `65571d43`, which is the
legacy non-GKI UAPI synchronization to version 4, while retaining the same
manual-hook and SUSFS v2.3 bridge. It is the candidate to pair with manager
v3.4.0 without the "kernel update required" UAPI warning.

The UAPI 4 workflow sets `KSU_VERSION_OVERRIDE=33197`, the count-derived
version for the pinned source, and validates the actual UAPI header before
building. It is not a blind version-number override.

Both experimental options should first be dispatched with DroidSpaces disabled
(or the `minimal` profile) so a failure is attributable to the root stack
rather than MEMCG/NAT changes.
