# Sky1 7.3.0 final (r291) — rebase verification, 2026-10-21

Independent re-derivation of the v7.3-rc7 → v7.3 rebase verdict. Every claim
below was re-measured on ULTRA against a pristine `v7.3` checkout; none of it is
carried over from the 2026-10-19 pass.

## Where the r290 series actually lives

The brief noted earlier jobs targeted a `kernel-73rc7-port-20261011` branch that
does not exist on the canonical origin. It does exist, but not where those jobs
looked:

| thing | where it actually is |
|---|---|
| recipe + 27 numbered patches | `meta-cix` `recipes-kernel/linux-cix-sky1-ncz/`, branch `fix/r290-patch-gate-20261017` @ `7263ec8` |
| port branch (git history form of the series) | `linux-cix-kernel-73final-port.git`, branch `kernel-73final-port-20261019` @ `0974edf1` |
| Debian packaging | `cix-installer` `build/build-kernel-debs.sh` (+ `extract-kernel-headers.sh`, `stage-kernel.sh`) |
| r290 artifacts | `~/ncz-assets/kernel-staging/r290-7.3.0-rc7-sky1-ncz-20261017/` |

`cix-installer/assets/kernel/sky1-manifest.json` on `release/preview3-20261017`
was the pin of record for r290 and pointed at these.

## Rebase verdict

Base tag `v7.3`, peel `c03c1a14507dfaf8b856c2608f9ac216021fc222` — which is
also the recipe's `SRCREV_kernel` and the HEAD of the built kernel source tree.

**28/28 patches applied, 0 conflicts, 0 rejects, 0 fuzz.** Order matters: the
series must be replayed in `SRC_URI` order (port patch first), not filename
order — replaying in filename order reports 21 spurious conflicts, which is how
an earlier ad-hoc check "found" conflicts that do not exist.

### Patches now upstream: none

Each of the 28 was tested three independent ways against the pristine v7.3 tree:

1. `git apply --check -R` — already present upstream? **no** for all 28.
2. Apply the preceding 27, then patch N, and compare each touched file against
   pristine v7.3 — a patch whose file is already byte-identical is a no-op.
   **0/28 are no-ops**; every patch is `EFFECTIVE`.
3. SRC_URI-order replay — clean.

So nothing was dropped. Had anything been upstream, its upstream commit is
recorded by checks 1–2 above.

### No upstream clobbering

The port patch shares exactly two files with what upstream changed between rc7
and v7.3. Both were checked explicitly:

- `drivers/gpu/drm/panthor/panthor_hw.c` — upstream `c347fef5f8f8`
  ("drm/panthor: fix immortalis condition"). The fix (`shader_core_count >= 10`)
  survives in the merged tree, alongside the port's Sky1 shader-harvesting block.
- `drivers/pci/quirks.c` — upstream `0f8b5d90d179` (Samsung 990 PRO / 990 EVO
  Plus Immediate Readiness) and `7209846a169f` (PCI/AER ANFE on Apple T2)
  survive; the port appends its CIX Sky1 ASPM quirks below them.

### Tree-equivalence cross-check

Replaying the identical series onto v7.3-rc7 and onto v7.3 gives two trees that
differ in **212 files**. Every one of the 212 was resolved (through the
`scripts/dtc/include-prefixes` symlinks, which otherwise alias to the real
`arch/*/boot/dts` paths) to a file upstream itself changed in the 289 commits
between the tags. **Zero unexplained differences**, so no Sky1 change was lost
or silently mangled by the rebase.

### Independent replay == shipped build

Replaying the series from scratch and diffing against the tree the r291 build
actually compiled produced **0 differing files**. The shipped kernel is exactly
what the recipe says it is.

## Config diff vs r290 (built `.config`, 5 lines)

| # | change | why |
|---|---|---|
| 1 | banner `7.3.0-rc7` → `7.3.0` | the base tag itself |
| 2 | `CONFIG_VIDEO_LINLON=m` → not set | deliberate: the in-tree VPU driver must not shadow the DKMS `amvx.ko` |
| 3 | `+CONFIG_VIDEO_LINLON_OOT=m` | patch 0022 + defconfig; supplies the videobuf2 helpers the DKMS module imports |
| 4 | `-CONFIG_VIDEO_LINLON_FTRACE`, `-_PRINT_FILE` | sub-options of `VIDEO_LINLON`, gone with their parent |
| 5 | `-# CONFIG_DRM_MSM_VALIDATE_XML is not set` | host probe only: its Kconfig is `depends on $(success,$(PYTHON3) -c "import lxml")`, and ULTRA's python3 has no lxml, so the symbol is never offered. Not enabled either way — the same benign host difference r290's own config-audit.log recorded on ARGOS. |

Net: no behavioural regression; items 2–3 strictly reduce the in-tree surface.
Verified consequences: 376 `.ko` with 0 `.ko.xz`, and no in-tree `amvx.ko`
(patch 0022 works as intended).

## Follow-ups from r290, both reproduced before fixing

**1. The headers postinst could never report a host tool usable.**
`tool_usable()` ran `"$1" --version >/dev/null 2>&1 || return 1`, which fires on
any non-zero exit — and both `fixdep` and `modpost` exit 1 on the bogus
`--version` (usage text on stderr). The `case $? in 126|127)` line after it was
therefore dead code. Measured against the real r290 headers tree: both tools
exec correctly, yet the function reported "unusable" for both, forcing a
pointless `modules_prepare` on every install and emitting the false
`fixdep/modpost still unusable; DKMS builds will fail` warning on boards where
DKMS was about to work. Fixed to `post-install/79-dkms-prep.sh`'s predicate
(only 126/127 mean *cannot exec*, which is the execve failure that a
uninative-linked Yocto binary produces), with stdin redirected from `/dev/null`.
`genksyms` was added to the tool list — it already was in 79-dkms-prep.sh, which
had been bitten by exactly this (r201: "genksyms: not found", no `aipu.ko`).

**2. `make modules_prepare` died on `kernel/bounds.s`.** The top-level `Kbuild`
derives `include/generated/bounds.h` from `kernel/bounds.s`, but `bounds.c` lives
outside `include/` so `extract-kernel-headers.sh`'s extension filters never
matched it and the tarball shipped 0 `*.c` files under `kernel/`. Reproduced on
ULTRA: `No rule to make target 'kernel/bounds.s', needed by
'include/generated/bounds.h'`. Fixed at the source (ship `kernel/bounds.c`), and
`-k` added to the postinst's make so other generated-source gaps — inherent to a
headers package built by extension filtering — cannot stop the host tools from
being built. After the fix the error is gone.

## Gates (all re-run by this pass)

| gate | result |
|---|---|
| `kvm-kernel-gate.sh` | PASS; r291 and r290 error-keyword histograms are **identical** → no new errors |
| `dkms-abi-gate.sh` | PASS (builder `oe-user@oe-host`, binutils 2.46.1, `CONFIG_MODVERSIONS=y`) |
| `verify-overlay-modversions.py` | PASS — 6 modules, 0 CRC mismatches, 0 unresolved |
| `acceptance.sh` | 28/28 |
| `.ko` uncompressed | PASS — 376 `.ko`, 0 `.ko.xz` |
| Debian deb reproducibility | byte-identical across two independent runs |

## Not done

Not published to apt; no hardware boot (O6N/cixmini untouched); not merged into
`release/preview3-20261017`.