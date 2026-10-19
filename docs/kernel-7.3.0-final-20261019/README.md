# Sky1 kernel 7.3.0 final pin -- 2026-10-19

Pin the NCZ Sky1 arm64 port from `v7.3-rc7` to the upstream **7.3.0 final** tag
(released 2026-10-18), with a full rebuild and the overlay modversions gate
passing.

## What changed

| item | before (r290) | after (r291) |
|---|---|---|
| `LINUX_VERSION` | `7.3-rc7` | `7.3` |
| `PV` | `7.3-rc7+ncz` | `7.3+ncz` |
| `SRCREV_kernel` | `e53244ff` (`v7.3-rc7` peel) | `0974edf1` (`v7.3` port tip) |
| `KBRANCH` | `kernel-73rc7-port-20261011` | `kernel-73final-port-20261019` |
| port patch | `sky1-ncz-v7.3-rc7-port.patch` | `sky1-ncz-v7.3-final-port.patch` |
| mirror | `linux-cix-kernel-73rc7-port.git` | `linux-cix-kernel-73final-port.git` |
| defconfig | `config-7.3-rc7.defconfig` | `config-7.3.0-sky1-ncz.defconfig` |
| base tag | `v7.3-rc7` | `v7.3` (`c03c1a14`) |

## Rebase result: clean, 0 conflicts

See [`rebase-replay.log`](rebase-replay.log). The full series (consolidated port
patch + 0001-0011 + 0013-0028) applied to a pristine `v7.3` checkout:

```
applied=28 conflicts=0
```

Cross-check: the same series replayed onto `v7.3-rc7` produces a tree differing
**only** in the 212 files upstream itself changed between those two tags.

## Build: PASS

Built in the `ncz-yocto-y6:trixie` container on ULTRA, against the local kernel
mirror, with `aarch64-nclawzero-linux-gcc 15.3.0`.

```
NOTE: recipe linux-cix-sky1-ncz-7.3+ncz-r1: task do_patch: Succeeded
NOTE: recipe linux-cix-sky1-ncz-7.3+ncz-r1: task do_configure: Succeeded
NOTE: recipe linux-cix-sky1-ncz-7.3+ncz-r1: task do_compile: Succeeded
NOTE: recipe linux-cix-sky1-ncz-7.3+ncz-r1: task do_compile_kernelmodules: Succeeded
NOTE: recipe linux-cix-sky1-ncz-7.3+ncz-r1: task do_install: Succeeded
NOTE: recipe linux-cix-sky1-ncz-7.3+ncz-r1: task do_package: Succeeded
NOTE: recipe linux-cix-sky1-ncz-7.3+ncz-r1: task do_deploy: Succeeded
```

KVER `7.3.0-sky1-ncz`, 376 modules (0 compressed), `CONFIG_MODVERSIONS=y`.
`Module.symvers`: 18771 CRCs, sha256 `55923d4c43ea993e...`.

Caveat, stated plainly: **six unrelated `do_create_(recipe_)spdx` tasks failed**
("Could not find a static SPDX document named static-bison-native" /
`static-pkgconf-native`). That is Yocto SPDX tooling, not the kernel; every
kernel task above succeeded and the image, modules and `Module.symvers` were
produced. It is a pre-existing build-dir issue, not caused by this pin.

## Overlay modversions gate: PASS (hard gate)

`7.3.0-sky1-ncz` is a **new KVER**, so the r290 overlays could not be reused.
All six were rebuilt from this build's headers via
`build/build-accel-overlays.sh` and verified:

```
OK mali_kbase.ko:                 versions=393 crc_mismatch=0 unresolved=0
OK memory_group_manager.ko:       versions=25  crc_mismatch=0 unresolved=0
OK protected_memory_allocator.ko: versions=21  crc_mismatch=0 unresolved=0
OK amvx.ko:                       versions=247 crc_mismatch=0 unresolved=0
OK aipu.ko:                       versions=123 crc_mismatch=0 unresolved=0
OK panthor.ko:                    versions=360 crc_mismatch=0 unresolved=0
verify-overlay-modversions: PASS
```

**Negative control** (proving the gate is live): perturbing a single CRC
(`kmalloc_caches`) fails 5 of the 6 modules. Full log:
`~/ncz-assets/kernel-staging/r291-7.3.0-sky1-ncz-20261019/overlay-modversions.log`.

## Code review fixes in this series

1. **`strcpy` in `get_cpuname_by_dmi` (`arch/arm64/kernel/cix_dmi.c`)** --
   **real defect, fixed.** Buffer sized with `strlen(bp) + 1` but filled with an
   unbounded `strcpy`. Now `strscpy(cpu_name, bp, strlen(bp) + 1)`.

2. **`acpi_clk_recalc_rate` (`drivers/clk/cix/acpi_clk.c`)** -- *no leak, but
   tightened.* Every exit path reaches `OUT` and the `kfree()` is guarded by
   `if (buffer.pointer)`. The genuine weakness is that `clk_rate` was
   uninitialised and only safe by way of the `ret ? 0 : clk_rate` ternary.
   `clk_rate` is now initialised to 0 with a plain `return clk_rate;`, making
   the invariant structural. Verified: the build compiles this file and the
   kernel links.

3. **`kzalloc_obj(*r)` in `acpi_scan_claim_resources` (`drivers/acpi/scan.c`)**
   -- **not a defect.** `kzalloc_obj(P,...)` expands to `typeof(P)`, so `*r`
   there is the *pointee type*, not a dereference -- upstream uses the same
   idiom in the same file (`dep = kzalloc_obj(*dep)`).

4. **`ncz_beacon` NULL handling** -- **not a defect.** `base` is a stack local
   re-validated on every call; `ncz_inited` never caches a pointer.

## Correction to an earlier note

An earlier draft of this document worried that `CONFIG_VIDEO_LINLON_OOT`
might not take effect. The real build settles it: `.config` has
`CONFIG_VIDEO_LINLON_OOT=m`, `CONFIG_VIDEO_LINLON is not set`, and `amvx.ko`
is **absent** from the in-tree modules tarball (376 modules, no amvx). Patch
0022 behaves correctly; the earlier concern was an artifact of my off-tree
replay test.

## Still outstanding (not claimed as done)

- **Debs not built** for r291 (`build/build-kernel-debs.sh`).
- **kvm_kernel_gate / dkms_abi_gate: NOT RUN** in this pass.
- **No hardware boot** on O6N/cixmini, no `validate-accelerators.sh`.
- **Not published** to the NCZ apt repo (publish-first rule).
