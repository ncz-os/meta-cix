# VPU: v1.0.1 pm_runtime irq/reset ordering — confirmed on Linux 7.2 + Sky1 metal

**Target repo:** `cixtech/cix_opensource__vpu_driver` (branch `cix_mainline_dev`)
**From:** Jason Perlow <jperlow@gmail.com>
**Relates to:** upstream v1.0.1 commit `4080a85` (irq/reset ordering fix)

## Summary

This is a downstream confirmation + small forward-port of your **v1.0.1**
`mvx_pm_runtime_resume()` irq/reset ordering fix, applied to the Linlon/amvx
VPU driver running on **Linux 7.2 (mainline v7.2-rc1 base)** on CIX Sky1
hardware (Orange Pi 6 Plus class board).

We independently root-caused the same boot-hang v1.0.1 addresses, and the fix
resolves it on metal. We are sending this back so the metal confirmation on a
7.2 kernel is on record, and to flag one 7.2-mainline build-compat item that
belongs with the same change.

## The bug (matches v1.0.1)

`mvx_pm_runtime_resume()` called `enable_irq(ctx->irq)` **before**
`reset_control_deassert(ctx->rstc)`. With the IRQ enabled while the block is
still in reset, the interrupt can fire mid-reset, land in a non-functional
state, and the probe error path then deadlocks in the IRQ bottom half before
any printk is emitted — a silent boot-hang. Reproduced on Sky1 metal and on
the prior 7.0.x NEXT kernels.

The fix reverses the order (deassert reset, then enable IRQ) and makes the
suspend path symmetric (assert reset before gating the clock), exactly as in
your v1.0.1.

## What this patch contains

1. The v1.0.1 irq/reset ordering fix in `mvx_pm_runtime_resume()` /
   `mvx_pm_runtime_suspend()` (`drivers/media/platform/cix/dev/mvx_dev.c`).
2. A Linux 7.2 build-compat fold-in in `mvx_log_group.c`:
   `del_timer()` → `timer_delete()` (the old wrapper is gone in 7.2 mainline).

## What was intentionally left OUT (and why it matters to you)

The remainder of the prepared v1.0.1 sync was **not** portable to 7.2
mainline as-is and is deferred:

- `rrc_dqp` feature work,
- debugfs session memory tracking (`mvx_session_update_memory_stats`),
- the `sw_core_mask` rewrite of `mvx_hwreg.{c,h}`.

These depend on **vendor-only CIX compat headers** (`<linux/string_compat.h>`,
`<linux/v4l2_compat.h>`) and **CIX-specific SCMI helpers**
(`scmi_device_get_freq()`, `scmi_device_opp_table_parse()`, …) that do not
exist in Linux 7.2 mainline. **Request:** if these helpers could be guarded
(`#if IS_ENABLED(...)` / `__weak` / a small compat shim upstreamed alongside
the driver), the driver would build against a stock mainline tree without the
private compat headers — which is what a mainline submission will need.

## Validation

- Metal: Sky1 board, VPU (amvx.ko) boots and decodes with the fix; hangs
  without it. (H.264/H.265/AV1 firmware staged separately at /lib/firmware.)
- Build: clean against Linux v7.2-rc1 + our CIX 2026q2 driver set.

Not opening a PR from here — staged for maintainer review first.
