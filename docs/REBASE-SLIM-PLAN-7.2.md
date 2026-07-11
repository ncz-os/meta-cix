# CIX Sky1 7.2 — upstream-DT-driver slim determination & plan

**Date:** 2026-07-11
**Author:** Jason Perlow <jperlow@gmail.com>
**Scope:** meta-cix `linux-cix-sky1-ncz_7.2.bb` (mainline v7.2-rc1 base +
132-patch NCZ ACPI series). Follow-up to the linux-next next-20260710 review
(MNEMOS `mem_1783793123123_5fa769`).

---

## TL;DR

- **The base already has the upstream CIX DT drivers.** All four
  (`reset-sky1`, `cix-mailbox`, `pinctrl-sky1*`, `pci-sky1`) are present in
  **v7.2-rc1** — the tree we already build against — not only in
  next-20260710. **No rebase is required to make the slim possible.**
- **2 of the 4 areas are ALREADY in the target "thin ACPI shim over the
  upstream DT driver" shape** (mailbox, reset). No slim work is needed there;
  the goal is already met.
- **2 of the 4 areas (pinctrl, PCIe) are genuine full-forks** that duplicate /
  replace the upstream driver. Slimming them is real ACPI driver-porting work
  and is **metal-gated** — a `NO-metal` build-green cannot validate it, and
  there is no green 7.2 baseline in front of us to regress against. Per the
  standing guardrail ("do not rip out working patches"), these are **deferred
  to a metal-enabled cycle** with the concrete plan recorded below.

## Do NOT rebase onto rc2/next — why

- `v7.2-rc2` does not exist in the torvalds mirror (unpublished); `linux-next`
  is a **separate** repo and a **moving integration tree**.
- The only reason to move base was to obtain the upstream CIX DT drivers —
  and **they are already in v7.2-rc1**. Rebasing onto next-20260710 would
  import unrelated cross-subsystem churn (breaking some of the other ~128
  patches) for **zero** benefit on driver availability. That is strictly added
  risk. Recommendation: **stay on v7.2-rc1**; do the slim in place, gated on
  metal, when a metal cycle is available.

---

## Base check — evidence

Build base = torvalds `v7.2-rc1`, SRCREV
`dc59e4fea9d83f03bad6bddf3fa2e52491777482`
(pinned in `linux-cix-sky1-ncz_7.2.bb`; mirror
`downloads/git2/git.kernel.org.pub.scm.linux.kernel.git.torvalds.linux.git`).

`git cat-file -e <SRCREV>:<path>` against that mirror:

| Upstream DT driver | In v7.2-rc1? |
|---|---|
| `drivers/reset/reset-sky1.c` | **PRESENT** |
| `drivers/mailbox/cix-mailbox.c` | **PRESENT** |
| `drivers/pinctrl/cix/pinctrl-sky1{-base,}.c`, `.h` | **PRESENT** |
| `drivers/pci/controller/cadence/pci-sky1.c` | **PRESENT** (OF glue, `compatible = "cix,sky1-pcie-host"`, ~200 lines over the shared Cadence HPA core) |

The recipe header already documented this correctly ("Upstream v7.2-rc1
already carries: … cix-mailbox, pci-sky1 …, pinctrl-sky1, reset-sky1"). The
next-20260710 review's premise that these were *only* in linux-next was wrong:
they landed in the v7.2 merge window and are in -rc1.

---

## Area-by-area determination

### 1. mailbox — ALREADY SLIM ✅ (no action)

- Our patch **0001** *modifies the in-base* `drivers/mailbox/cix-mailbox.c`
  (+34/-10): adds `#include <linux/acpi.h>`, an `acpi_device_id`
  (`CIXHA001`), `.acpi_match_table`, and an ACPI branch for the `cix,mbox_dir`
  property. This is exactly a thin ACPI delta over the upstream DT driver.
- **Nothing to slim.** Already the desired shape.

### 2. reset — ALREADY SLIM ✅ (no action)

- **0087** (reset: sky1: restore ACPI) *modifies in-base* `reset-sky1.c`
  (+50/-6): `device_get_match_data()`, ACPI `devm_ioremap`+`regmap_init_mmio`
  branch, `CIXHA020/CIXHA021` acpi match, `subsys_initcall`. Thin ACPI delta.
- **0111** (reset core fwnode fallback) *modifies in-base* `reset/core.c`
  (+19): falls back to the CIX lookup table only when the native fwnode reset
  returns `-ENOENT`. Thin, generic.
- **0005** (add cix reset driver) adds a **separate**, complementary
  `drivers/reset/reset-sky1-audss.c` (audio-subsystem reset — a different HW
  block than the SRC controller upstream `reset-sky1.c` handles) plus
  `include/dt-bindings/reset/sky1-reset{,-audss,-fch}.h` and reset-core
  plumbing. **Verified upstream v7.2-rc1 does NOT ship these files**
  (`sky1-reset.h`, `sky1-reset-audss.h`, `reset-sky1-audss.c` all ABSENT), so
  0005 is additive, not a duplicate.
- **Nothing to slim.** The SRC path is upstream + thin ACPI deltas; the audss
  driver is legitimately additional.

### 3. pinctrl — GENUINE FULL-FORK ⚠️ (slim DEFERRED, metal-gated)

- Patch **0039** *wholesale-rewrites* the in-base upstream pinctrl driver:
  `pinctrl-sky1-base.c` (upstream 587 lines) and `pinctrl-sky1.c` are replaced
  hunk-by-hunk (first hunk `@@ -1,503 +1,712 @@` = near-total file
  replacement), and it adds a generic `drivers/pinctrl/pinctrl-acpi.c/.h`
  layer plus `core.c`/`core.h` changes.
- This is the classic "downstream ACPI fork applied as one giant patch over the
  upstream OF driver." It is a real slim candidate, but:
  - pinctrl underpins essentially every other peripheral → **metal-critical**;
  - the upstream driver is **OF-only**; producing a minimal ACPI-delta means
    re-deriving the ACPI fwnode/pin-group glue that the fork currently
    provides — a from-scratch driver-porting effort, not a mechanical conflict
    resolution;
  - a `NO-metal` build-green cannot prove it boots correctly.

**Deferred slim plan (execute in a metal cycle):**
1. Start from upstream v7.2-rc1 `pinctrl-sky1*.c` as the base.
2. Diff the fork (`0039` result) vs upstream; classify hunks into
   (a) ACPI fwnode/property enablement, (b) pin-group/pinmux data that upstream
   already carries, (c) generic `pinctrl-acpi.c` helper.
3. Keep only (a) + (c) as a thin delta; drop (b) (now redundant with upstream).
4. Rebuild + **boot on metal**; verify pinmux for UART/I2C/SPI/USB/PCIe pins.
5. Only then replace 0039 with the slim delta on the release branch.

### 4. PCIe — GENUINE FULL-FORK / PARALLEL DRIVER ⚠️ (slim DEFERRED, metal-gated)

- Patch **0026** adds a **separate** vendor driver
  `drivers/pci/controller/cadence/pci-sky1-cix.c` (**2578 lines**) +
  `pci-sky1-cix.h` + `pci-sky1-debugfs.c` (1340 lines). **0032** adds a
  `PCI_SKY1_HOST_CIX` Kconfig knob selecting it. **0027/0029** fix/extend it.
  Verified: **0026/0027 do NOT touch the upstream `pci-sky1.c`** — the vendor
  driver runs *instead of*, in parallel with, the compact upstream OF glue
  driver.
- ACPI-side deltas **0099** (`sky1_pcie_native=off` ECAM knob) and **0101**
  (block CIXH2020 in standard mode) sit on top of the vendor driver.
- Slimming = switch the build to the upstream `pci-sky1.c` OF driver + a thin
  ACPI shim, dropping the 2.5K-line vendor driver. But:
  - PCIe is the **NVMe root** path → **metal-critical** (a mis-slim builds
    fine and fails to mount root / bricks boot);
  - upstream `pci-sky1.c` is **OF-only** (`of_device_id`,
    `compatible = "cix,sky1-pcie-host"`, no `acpi_match_table`) — it must be
    taught ACPI (ECAM/config-space, MSI, reset/clock via our SCMI+reset paths)
    before it can drive our BIOS platform;
  - no green 7.2 baseline to regress against.

**Deferred slim plan (execute in a metal cycle):**
1. Add an `acpi_match_table` (`CIXH2020`/ECAM HIDs) + ACPI resource/clk/reset
   handling to upstream `pci-sky1.c` (mirror the `0029/0099/0101` ACPI logic
   as a thin delta on the upstream driver rather than the vendor one).
2. Flip `PCI_SKY1_HOST_CIX` default off / drop `pci-sky1-cix.c` from the build.
3. Rebuild + **boot on metal**; verify NVMe root mounts, enumerate all PCIe
   endpoints (NIC RTL8127, USB, etc.), check MSI + AER.
4. Keep `pci-sky1-cix.c` available (Kconfig-guarded) until the upstream-driver
   path is metal-proven, then remove.

---

## What was done in this pass

- Base check (above) — decisive, no rebase.
- Confirmed mailbox + reset are already in target shape (no change needed).
- Recorded the concrete, metal-gated slim plans for pinctrl + PCIe.
- **Did not** modify the buildable patch series → no regression risk; the
  current metal-proven 132-patch series is untouched. A baseline ULTRA-pool
  build of the unchanged series was run to confirm the series is still green.
- Staged three upstream submissions under `upstream-submissions/` (VPU
  irq/reset → cixtech; SCMI-ACPI RFC → LKML/Sudeep Holla; NPU+VPU downstream
  fixes → cixtech/ArmChina).

## Open decision for the operator

If a **metal window** opens (a Sky1 board available for iterate-and-boot,
NOT `.66` which is off-limits), the pinctrl + PCIe slims become executable per
the plans above. Until then, deferring is the correct, low-regret choice:
the drivers being in-base means the slim is *ready whenever metal is*, with no
base move required.
