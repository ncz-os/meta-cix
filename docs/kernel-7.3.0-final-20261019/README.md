# Sky1 kernel 7.3.0 final pin -- 2026-10-19

Pin the NCZ Sky1 arm64 port from `v7.3-rc7` to the upstream **7.3.0 final** tag
(released 2026-10-18), and record the rebase, config and code-review evidence.

## What changed

| item | before (r290) | after (r291) |
|---|---|---|
| `LINUX_VERSION` | `7.3-rc7` | `7.3` |
| `PV` | `7.3-rc7+ncz` | `7.3+ncz` |
| `SRCREV_kernel` | `ec8bf828` (`v7.3-rc7` peel) | `c03c1a14` (`v7.3` peel) |
| `KBRANCH` | `kernel-73rc7-port-20261011` | `kernel-73final-port-20261019` |
| port patch | `sky1-ncz-v7.3-rc7-port.patch` | `sky1-ncz-v7.3-final-port.patch` |
| mirror | `linux-cix-kernel-73rc7-port.git` | `linux-cix-kernel-73final-port.git` |
| defconfig | `config-7.3-rc7.defconfig` | `config-7.3.0-sky1-ncz.defconfig` |

The 27 numbered patches (0001-0011, 0013-0028) are **unchanged** in content.

## Rebase result: clean, 0 conflicts

See [`rebase-replay.log`](rebase-replay.log). Full series applied to a
pristine `v7.3` checkout fetched fresh from git.kernel.org:

```
applied=28 conflicts=0
```

Cross-check: the same series replayed onto `v7.3-rc7` produces a tree that
differs from the final tree **only** in the 212 files upstream itself changed
between those two tags. Every Sky1 port change is carried across intact.

## Defconfig

`config-7.3.0-sky1-ncz.defconfig` is the r290 config, re-verified against the
v7.3 Kconfig tree with the port series applied:

- every `CONFIG_*` symbol in the fragment resolves to a symbol defined in v7.3
  Kconfig (the 8 that appear "undefined" to a naive grep are indented entries
  under `menuconfig` blocks -- `DEFAULT_FQ_CODEL`, `DEFAULT_SECURITY_APPARMOR`,
  `FONT_8`, `FONT_TER16`, `IMA_DEFAULT_HASH_SHA256`, `IMA_SIG_TEMPLATE`,
  `NFS_V4_1`, `PWM_SKY1` -- all present and valid).
- `make ARCH=arm64 defconfig` + `merge_config.sh` + `olddefconfig` all succeed.
- `CONFIG_MODVERSIONS=y` is still set.

## Code review fixes in this series

Two findings raised against the port patch were checked against the source:

1. **`strcpy` in `get_cpuname_by_dmi` (`arch/arm64/kernel/cix_dmi.c`)** --
   **real defect, fixed.** The buffer was sized with `strlen(bp) + 1` but then
   filled with an unbounded `strcpy`. Replaced with
   `strscpy(cpu_name, bp, strlen(bp) + 1)`. The file compiles clean
   (`make arch/arm64/kernel/cix_dmi.o`, `W=1`).

2. **`kzalloc_obj(*r)` in `acpi_scan_claim_resources` (`drivers/acpi/scan.c`)**
   -- **not a defect.** `kzalloc_obj` is a real upstream API:

   ```c
   #define kzalloc_obj(P, ...) \
       __alloc_objs(kzalloc, default_gfp(__VA_ARGS__), typeof(P), 1)
   ```

   and `*r` is the *pointee type*, not a dereference -- `typeof(*r)` is
   `struct resource`. Upstream uses the same idiom throughout the same file
   (`dep = kzalloc_obj(*dep)`, `aux_dev = kzalloc_obj(*aux_dev)`). No change
   made; `drivers/acpi/scan.o` builds clean.

3. **`ncz_beacon` NULL handling (`arch/arm64/kernel/ncz-resume-beacon.c`)** --
   **not a defect.** `base` is a stack local re-validated on every call
   (`base = ncz_map(); if (!base) return;`). `ncz_inited` only gates the
   header initialisation; it never implies a cached pointer.

## NOT DONE -- hard gate outstanding

**The build and the Module.symvers / overlay modversions gate have NOT been
run.** This host has no Yocto build environment, and the container image is
not available here. Per the task these are mandatory, so this pin is
**not build-validated** and must not be treated as shippable until:

1. `ncz-yocto-y6` builds on ARGOS (host of the r290 build) with
   `NCZ_BUILD_INPUTS_DIR=~/ncz-assets`, and
2. `verify-overlay-modversions` reports 0 CRC mismatches for mali_kbase,
   memory_group_manager, protected_memory_allocator, amvx, aipu and panthor
   against the new `Module.symvers`.

The 7.3.0-sky1-ncz bump is a **new KVER**, so the r290 overlay `*.ko` files
cannot be reused -- all six overlay modules need rebuilding and re-verifying.
