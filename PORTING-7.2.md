# Porting the NCZ kernel series to 7.2 final

The tree is **v7.2-rc7 + 175 NCZ commits**. The source of truth is the ordered
list of `.patch` files in `linux-cix-sky1-ncz_7.2.bb`, not the unpacked
`kernel-source` git (that is a build artifact, regenerated every build).

## The one command

```sh
git --git-dir=/nfs-shared/downloads/git2/git.kernel.org.pub.scm.linux.kernel.git.torvalds.linux.git \
    fetch origin --tags
cd meta-cix && ./kernel-rebase-check.sh v7.2
```

It applies all 175 patches in **recipe order** against a scratch worktree and
keeps going after a failure, so one run gives the complete conflict list.
A full `bitbake` stops at the first failure and takes ~40 minutes, which hides
the other 174 answers.

Exit 0 = `REBASE: CLEAN`. Exit 1 = per-patch `CONFLICT` lines to fix.

## Expected risk: low

Measured 2026-08-14:

| target | result |
|---|---|
| v7.2-rc7 (our base) | 175/175 clean |
| v7.2-rc1 | 175/175 clean |
| v7.0 | conflicts (0077, 0079, 0084, 0087, 0092, 0111, 0116, 0187, ...) |

The series survives the entire 7.2 rc cycle unchanged, so rc7 -> final (a much
smaller delta than rc1 -> rc7) should be clean. v7.0 conflicting confirms the
check actually detects breakage rather than always passing.

## After the check passes

1. Set `LINUX_VERSION = "7.2"` in the recipe. It currently reads `"7.2-rc6"`
   while the tree is actually rc7+175 — the string has been stale for a while
   and will mislead at port time.
2. Update `SRCREV_kernel` to the v7.2 commit.
3. Rebuild, then **KVM-gate it**: `cix-installer/build/kvm-kernel-gate.sh <Image> <config>`.
   The gate's PCI-ID lint matters more since BIOS 1.3.1 — every Sky1 root port
   now advertises 17cd:0100, the same ID the Cadence USB3 wrapper claims, so
   USB_CDNS3_PCI_WRAP / USB_CDNSP_PCI / USB_CDNS2_UDC must all stay unset.
4. Bump `BUILD_REV` past the installed rev and package with
   `sudo BUILD_REV=rNNN ./build/build-kernel-debs.sh` — note `sudo -E` does NOT
   pass the variable through (env_reset), which silently produced an r212
   downgrade once.

## Series hygiene, worth fixing before the port

- **196 .patch files on disk, 175 applied.** The other 21 are DIAG/DIAG2
  diagnostics, superseded VPU power/clock attempts, and the deferred panthor
  work. They are unreferenced by the recipe but sit in the same directory.
- **Duplicate numbers**: two `0146-*` and two `0186-*`. Since the apply order
  comes from the recipe rather than `ls`, this is not currently a build hazard,
  but any tooling that sorts by filename would apply a different series.
