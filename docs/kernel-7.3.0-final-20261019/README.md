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

1. **DMI string walk in `get_cpuname_by_dmi` (`arch/arm64/kernel/cix_dmi.c`)**
   -- **real defect, rewritten.** The original opened with an unbounded
   `strcpy`; the first attempt at fixing it only swapped in `strscpy()` while
   still computing the length with `strlen()` over DMI table data whose upper
   bound was never established. `strscpy()` prevents the *write* overflow but
   does nothing about the *read*: if the record's string area is malformed or
   not NUL-terminated, `strlen(bp)` walks off the allocated DMI block.

   The deeper finding: the helper was a hand-copied duplicate of upstream's
   `dmi_string_nosave()`, which lives in `drivers/firmware/dmi_scan.c` and is
   exported via `<linux/dmi.h>`. Rather than re-derive a safe bound here, the
   copy is deleted and the real helper called:

   ```c
   bp = dmi_string_nosave(dm, ((const u8 *)dm)[0x10]);
   if (!bp || !bp[0])
           return;
   cpu_name = dmi_alloc(strlen(bp) + 1);
   if (!cpu_name)
           return;
   strscpy(cpu_name, bp, strlen(bp) + 1);
   get_cpu_flag = true;
   ```

   `dmi_string_nosave()` performs the identical offset-0x10 walk, applies the
   same "whitespace-only means empty" rule, and returns a safe empty string --
   so this also removes the duplicated space-scan loop. The remaining
   `strlen(bp)` is now on a pointer the core helper has already validated.

2. **`acpi_cix_clk_recalc_rate` (`drivers/clk/cix/acpi_clk.c`)** -- **real
   defect, fixed: out-of-bounds read.** The function read three u32s out of
   the returned ACPI buffer with no length check at all. A firmware returning
   a short `GClK` buffer would be over-read by 12 bytes. Now:

   ```c
   if (package->buffer.length < sizeof(buf_val)) {
           dev_err(dev, "ACPI clk[%u] returned short buffer (%u bytes)\n",
                           aclk_hw->clk_id, package->buffer.length);
           goto OUT;
   }
   ```

   Separate from the bounds issue, `ret` was provably dead: set on every error
   path and then never read (`-Wunused-but-set-variable` reproduced it), which
   means all failures were silently reporting rate 0 with no way for a caller
   to distinguish that from a real 0 Hz. `ret` is removed; `clk_rate` is
   initialised to 0 and returned directly. `AE_NOT_FOUND` and every other
   failure now take the same `goto OUT` path with a per-clock `dev_err`, and
   the buffer is released on all of them.

3. **`kzalloc_obj(*r)` in `acpi_scan_claim_resources` (`drivers/acpi/scan.c`)**
   -- **not a defect; disproved by compiling it.** `kzalloc_obj(P)` is a
   macro, not a function; `P` appears only in `typeof(P)` and in a cast, both
   of which are compile-time constructs. `*r` therefore names the pointee
   *type* and is never evaluated, so there is no dereference of an
   uninitialised pointer.

   Reproduced standalone and inspected the emitted code -- the only argument
   passed to `kzalloc` is the constant size, with no load from `r`:

   ```
   8:  mov x0, #0x20        // sizeof(struct resource)
   18: bl  kzalloc
   ```

   Upstream already uses the same idiom in the same function
   (`dep = kzalloc_obj(*dep)`), so changing it would diverge from upstream
   style for no benefit. No edit made.

4. **`ncz_beacon` NULL handling** -- **not a defect.** `base` is a stack local
   re-validated on every call (`base = ncz_map(); if (!base) return;`);
   `ncz_inited` only gates header initialisation and never caches a pointer.

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
