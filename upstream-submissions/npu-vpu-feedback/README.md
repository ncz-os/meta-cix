# Downstream NPU + VPU fixes on Linux 7.2 — feedback for cixtech / ArmChina

**From:** Jason Perlow <jperlow@gmail.com>
**Context:** NCZ 7.2 kernel track = mainline **v7.2-rc1** base + the cixtech
2026q2 vendor driver set, forward-ported. The ArmChina Zhouyi NPU driver and
the Linlon/amvx VPU driver are carried **out-of-tree** (neither is upstream).
This note indexes the fixes we had to make on top of the vendor sources so
that Sky1 NPU/VPU boot and run on a 7.2 / ACPI(BIOS) kernel, as feedback to
fold back into the vendor trees.

Nothing here is a mainline submission — these are whole out-of-tree drivers.
The intent is to hand the delta back to the driver owners.

---

## NPU — ArmChina Zhouyi V3/V3_1 (CONFIG_ARMCHINA_NPU), CIX Sky1 CRE0-2

Base import: `0119` (Entrpi v7.1 sky1-next armchina-npu, 46 files ~12K lines,
forward-ported onto v7.2-rc1). Downstream fixes on top:

| Patch | Theme | What / why |
|------|-------|-----------|
| `0120` | **7.2 API drift** | `pm_runtime_put()` now returns void in 7.2 — drop the return-value use. |
| `0125` | **7.2 API drift** | `platform_driver::remove` converted to `void` return in 7.1/7.2 — update the callback signature. |
| `0121` | **genpd NULL guard** | Sky1 BIOS v1.0 does not expose `_HID` for CRE0-2 power-domain cores, so `pd_core[]` entries are NULL — guard every deref. |
| `0123` | **ACPI power** | When all `pd_core[]` are missing, force the device to ACPI D0 before probe so the NPU is powered without genpd. |
| `0122` | **ACPI SSDT overlay** | `_STA` quirk to add the CIXH4010 NPU CRE child devices the base DSDT omits (SSDT-overlay-style enablement). |
| `0124` | **ACPI match tightening** | Tighten the hidden Sky1 SCMI/NPU child match (parent HID + child ACPI name + uid) so the NPU child does not mis-bind to the SCMI parent. |

**Feedback for ArmChina/cixtech:**
- The `pm_runtime_put`/`platform_driver::remove` void-return churn is pure
  kernel-version drift — please bump the vendor tree to the current callback
  signatures (or `#if LINUX_VERSION_CODE` guard) so it builds on >=7.1.
- The NULL `pd_core[]` guards + force-D0 fallback are needed on any BIOS that
  doesn't expose the CRE power-domain `_HID`s. Consider making genpd optional
  in the driver rather than assumed-present.
- The SSDT-overlay `_STA` quirks (`0122`/`0124`) are our workaround for an
  incomplete DSDT; the cleaner fix is on the firmware/ACPI-tables side.

---

## VPU — Linlon/amvx (VIDEO_LINLON / drivers/media/platform/cix), ACPI HID CIXH3010

Base import: `0126` (Entrpi v7.1 sky1-next Linlon VPU, 63 files ~39K lines,
forward-ported onto v7.2-rc1). Downstream fixes on top:

| Patch | Theme | What / why |
|------|-------|-----------|
| `0127` | **Kconfig deps** | Add `select VIDEOBUF2_DMA_SG` / `select VIDEOBUF2_MEMOPS` so the dep chain resolves when no other driver enables videobuf2-dma-sg. |
| `0128` | **7.2 build fix** | Add explicit `#include <linux/string.h>` + `strncpy`->`strscpy` in three cix files where the 7.2 include chain no longer drags string.h primitives in transitively. |
| `0129` | **firmware robustness** | Missing VPU firmware now fails as `-ENOENT` without leaving later waiters stuck on a completed-failed cache entry, and no hardware session is registered after firmware has already failed. |
| `0130` | **irq/reset race** | Sync of upstream v1.0.1 `mvx_pm_runtime_resume()` irq/reset ordering fix (deassert reset before enabling IRQ) — fixes a silent boot-hang. See `../vpu-irq-reset/`. Also folds `del_timer`->`timer_delete()` for 7.2. |

**Feedback for cixtech (Linlon/amvx):**
- `0130` is already in your v1.0.1 — the standalone submission with metal
  confirmation is in `../vpu-irq-reset/`.
- `0127`/`0128` are trivial build-hygiene items (explicit Kconfig `select`s and
  `#include`s) that should be folded into the vendor tree so it builds against
  a stock >=7.2 kernel without relying on transitive includes.
- `0129` (firmware-absent robustness) is a real correctness fix independent of
  kernel version — worth taking regardless.
- Biggest blocker to any eventual mainline VPU submission: the driver's
  dependence on vendor-only compat headers (`<linux/string_compat.h>`,
  `<linux/v4l2_compat.h>`) and CIX-specific SCMI OPP/freq helpers. Guarding or
  upstreaming those shims is the prerequisite for the deferred v1.0.1 feature
  hunks (rrc_dqp, memory-stats debugfs, sw_core_mask) to land.
