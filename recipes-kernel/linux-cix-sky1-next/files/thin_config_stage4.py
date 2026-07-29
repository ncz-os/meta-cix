#!/usr/bin/env python3
"""
Stage 4 thinning of config.sky1-next -- zero-risk cuts found by inspecting
the actual built .ko module tree (not just Kconfig audit): foreign-SoC GPU
vendor DRM drivers (nouveau/msm/etnaviv/meson/exynos/lima/tidss/komeda/
hisi_hibmc/rcar_du/sun4i/sun8i/imagination), the dead Greybus (Project Ara)
subsystem, and md/dm software RAID + device-mapper (no RAID hardware on any
board, preseed explicitly disables home-dir encryption so no dm-crypt need).

Real CIX modules (panthor, linlon-dp, trilin-dpsub, drm_kms_helper, ttm,
drm_display_helper, drm_gpuvm, drm_shmem_helper, gpu-sched, bridge/panel
helpers) are NOT in PROTECT_EXACT because none of the cut patterns below
can match them -- they don't share a vendor prefix with anything cut here.

Dry-run by default. Pass --apply to write in place.
"""
import re
import sys

PATH = "config.sky1-next"

PROTECT_EXACT = set()  # nothing cut here comes close to a real symbol

STAGE4 = [
    ("Foreign GPU vendor DRM drivers (verified via built .ko tree: nouveau 23M, msm 11M, etc)", [
        r"^CONFIG_DRM_NOUVEAU",
        r"^CONFIG_DRM_MSM",
        r"^CONFIG_DRM_ETNAVIV",
        r"^CONFIG_DRM_MESON",
        r"^CONFIG_DRM_EXYNOS",
        r"^CONFIG_DRM_LIMA",
        r"^CONFIG_DRM_TIDSS",
        r"^CONFIG_DRM_KOMEDA",
        r"^CONFIG_DRM_HISI_HIBMC",
        r"^CONFIG_DRM_RCAR_DU",
        r"^CONFIG_DRM_IMX_DCSS",
        r"^CONFIG_DRM_SUN4I",
        r"^CONFIG_DRM_SUN8I",
        r"^CONFIG_DRM_MALI_DISPLAY",  # legacy ARM HDLCD/Mali-DP, superseded by komeda/linlon on real SoCs -- not Sky1's
        r"^CONFIG_DRM_IMAGINATION",
        r"^CONFIG_POWERVR",
    ], []),

    ("Greybus (Project Ara mobile-phone modular hardware -- dead framework, no SBC uses it)", [
        r"^CONFIG_GREYBUS",
    ], []),

    ("md/dm software RAID + device-mapper (no RAID hardware any board; preseed disables encrypt-home so no dm-crypt need)", [], [
        "CONFIG_BLK_DEV_MD", "CONFIG_MD_BITMAP", "CONFIG_MD_BITMAP_FILE",
        "CONFIG_MD_RAID0", "CONFIG_MD_RAID1", "CONFIG_MD_RAID10", "CONFIG_MD_RAID456",
        "CONFIG_BLK_DEV_DM", "CONFIG_DM_CRYPT", "CONFIG_DM_SNAPSHOT",
        "CONFIG_DM_THIN_PROVISIONING", "CONFIG_DM_MIRROR", "CONFIG_DM_ZERO",
    ]),
]

def load(path):
    with open(path) as f:
        return f.readlines()

def symbol_of(line):
    m = re.match(r"^(CONFIG_[A-Za-z0-9_]+)=(y|m)\s*$", line)
    if m:
        return m.group(1), True
    m = re.match(r"^# (CONFIG_[A-Za-z0-9_]+) is not set\s*$", line)
    if m:
        return m.group(1), False
    return None, None

def main():
    apply_changes = "--apply" in sys.argv
    lines = load(PATH)
    changes = []
    for i, line in enumerate(lines):
        sym, enabled = symbol_of(line)
        if not sym or not enabled:
            continue
        if sym in PROTECT_EXACT:
            continue
        for label, patterns, explicit in STAGE4:
            hit = sym in explicit or any(re.match(p, sym) for p in patterns)
            if hit:
                changes.append((i, sym, line.rstrip("\n"), label))
                break

    by_label = {}
    for i, sym, old, label in changes:
        by_label.setdefault(label, []).append(sym)

    print(f"=== Stage 4 dry-run: {len(changes)} symbols would be disabled ===\n")
    for label, syms in by_label.items():
        print(f"[{label}] {len(syms)} symbols:")
        print("  " + ", ".join(syms))
        print()

    if apply_changes:
        for i, sym, old, label in changes:
            lines[i] = f"# {sym} is not set\n"
        with open(PATH, "w") as f:
            f.writelines(lines)
        print(f"APPLIED: {len(changes)} lines changed in {PATH}")
    else:
        print("(dry run only -- pass --apply to write changes)")

if __name__ == "__main__":
    main()
