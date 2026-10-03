# Kernel 7.2.9 mechanical port — ARM64 (Sky1) leg

Branch: `feat/kernel-7.2.9-port-2026-10-03`
Recipe: `recipes-kernel/linux-cix-sky1-ncz/linux-cix-sky1-ncz_7.2.bb`
Date: 2026-10-03
Scope: **port only.** No kernel build, no image build, no flashing, no reboot.
Build and the KVM boot gate are separate steps the orchestrator runs afterwards.

## Port result for this tag: 205/205 applied, 0 failed

No patch needed adaptation, so there is no adaptation log to publish this cycle.
See "Why a clean pass" below for why that is a real result and not a skipped step.

## 1. SRCREV — resolved, not assumed

The task quoted a candidate SHA. It was re-checked against kernel.org before use:

```
$ git ls-remote https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git \
      'refs/tags/v7.2.9' 'refs/tags/v7.2.9^{}'
bd50482a9c7a6eb91468f1064a346a75e677e692	refs/tags/v7.2.9
5fce161649b4d779d1b76d9fcd52dc77779774b8	refs/tags/v7.2.9^{}
```

`5fce161649b4d779d1b76d9fcd52dc77779774b8` is the **dereferenced commit** and is
what the recipe now pins. The bare annotated tag object is
`bd50482a9c7a6eb91468f1064a346a75e677e692` — the recipe pins the commit, matching
the convention of every prior pin (v7.2, rc4/rc5/rc6/rc7, 7.2.4–7.2.8).
The candidate in the task text matched what kernel.org actually reports.

## 2. Recipe bump — exactly the shape of 4ebad66

| field | before | after |
|---|---|---|
| `LINUX_VERSION` | `7.2.8` | `7.2.9` |
| `PV` | `7.2.8+ncz` | `7.2.9+ncz` |
| `SRCREV_kernel` | `9a66fdc0d7fd…` | `5fce161649b4…` |

`KBRANCH` stays `linux-7.2.y` and `SRC_URI` stays on the **stable** tree — that
mechanics change landed back in the 7.2.4 cycle and is correct for 7.2.9.

Nothing else was touched. Verified with `git diff --name-only`: exactly one file.
The **7.3-rc5 recipe, the edge entry, and every other recipe are unmodified.**

## 3. Patch-series replay

Method — mechanical, on a clean tree, per the standing rules:

```
git init k729 && git remote add origin https://git.kernel.org/.../stable/linux.git
git fetch --depth 1 origin tag v7.2.9 && git checkout v7.2.9
# HEAD == 5fce161649b4d779d1b76d9fcd52dc77779774b8, worktree clean

# patch list taken from the recipe itself, in SRC_URI order (not from a
# directory glob), so a stray .patch on disk could not sneak into the run
grep -o 'file://patches-7\.2/[^ ]*\.patch' ..._7.2.bb | sed 's|file://||' > wired.txt
#   -> 205 entries; all 205 confirmed present on disk

git am --3way <each patch>   # abort+record on failure
```

Results:

* base `Makefile` after replay: `PATCHLEVEL = 2`, `SUBLEVEL = 9`
* `git rev-list --count HEAD ^5fce1616` = **205** (205 real commits on top of the tag)
* failures: **0**
* worktree clean afterwards

Series inventory note: `linux-cix-sky1-ncz-7.2/patches-7.2/` holds 231 files but the
recipe **wires 205**. The 26 unwired files are not part of the port; replaying the
205 the recipe actually consumes is the correct scope, matching the 7.2.8 cycle
("205 wired").

### Why a clean pass is a real result, not a skipped step

Each `git am` was checked for a genuine commit, not just a zero exit code, and the
expected CIX payload was spot-verified in the resulting tree
(`drivers/soc/cix/`, `drivers/media/platform/cix/`, `drivers/misc/armchina-npu/`
all populated). The 7.2.8 → 7.2.9 delta is smaller than the cycles immediately
before it, so a clean pass is expected rather than surprising:

* no `arm_scmi` bus.c/driver.c refcount churn — that is what forced **0075/0085**
  to be hand-resolved in the 7.2.6 cycle;
* no cdnsp context-loss commit — that is what made **0114/0221** need regeneration
  in the 7.2.5 cycle.

Both prior cycles are documented in this recipe's header comment; the header now
also carries the 7.2.9 entry so the cycle history stays continuous.

## 4. ⚠️ ULTRA carries two meta-cix trees, and they disagree

This bit the 7.2.8 cycle and is repeated here because it will bite the next one:

| path | state | role |
|---|---|---|
| `~/yocto-work/meta-cix` | tracks the current recipe | **this is the one the build reads** |
| `~/yocto-docker/yocto6-ncz-tydeus/meta-cix` | stale (lagging a version behind) | TYDEUS's layout, not the build's |

The kernel-build checklist names the **yocto-docker** path authoritative, but that
reflects TYDEUS's layout. On ULTRA the build consumes **yocto-work**. The consequence
is concrete: anyone who reads a recipe value off the wrong tree will pin a stale
SRCREV and build the wrong kernel while every on-disk check appears to pass.

**The build step must read `~/yocto-work/meta-cix`.** Confirm the consuming tree
before trusting any recipe value read from disk.

## 5. MNEMOS

`zoder mnemos --search kernelwatch` was attempted before starting and **could not
run**: `zoder: error: MNEMOS_URL is required: environment variable not found`.
The 7.2.8 port notes were therefore read from git instead — commit `4ebad66`
("linux-cix-sky1-ncz 7.2: bump to v7.2.8"), whose message and diff were the
reference for the bump shape reproduced in §2. No MNEMOS content is claimed here,
because none was retrieved.

## 6. What is NOT done

Build, package, KVM boot gate, and install on hardware remain outstanding and are
the orchestrator's to run. This report asserts only that the port is mechanically
clean and the recipe now points at the verified v7.2.9 commit.
