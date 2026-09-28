# linux-cix-sky1-ncz_7.2.bb packaging rename — deliverable report

Repo: `~/yocto-work/meta-cix` on ULTRA (192.168.207.88), branch
`wip/ultra/2026-09-09-kernel-73rc2-yocto-recipe`, pushed to ARGONAS.
Commit: **`41b2c07`** — `linux-cix-sky1-ncz 7.2: rename produced packages
to linux-image-cixmini / linux-headers-cixmini`.

---

## 1. Build verification (deliverable item 1)

`bitbake linux-cix-sky1-ncz` completed all 904 tasks (892 cached + 12 ran)
under `do_package_write_deb: Succeeded`. Produced packages under
`~/ybuild/tmp/work/cixmini-nclawzero-linux/linux-cix-sky1-ncz/7.2.5+ncz/deploy-debs/cixmini/`:

| Package (filename stem)                          | Internal `Package:` field | Notes |
|--------------------------------------------------|--------------------------|-------|
| `linux-image-cixmini_7.2.5+ncz0+a300e35c0a-r1_arm64.deb` | `linux-image-cixmini`     | ALLOW_EMPTY meta, Depends: `linux-cix-sky1-ncz-kernel-image-image-7.2.5-sky1-ncz (= 7.2.5+ncz0+a300e35c0a-r1)` |
| `linux-headers-cixmini_7.2.5+ncz0+a300e35c0a-r1_arm64.deb` | `linux-headers-cixmini`   | Holds `/boot/System.map-7.2.5-sky1-ncz`, `/boot/Module.symvers-7.2.5-sky1-ncz`, `/boot/config-7.2.5-sky1-ncz`, `/lib/modules/7.2.5-sky1-ncz/build/` |
| `linux-cix-sky1-ncz-kernel-image-image-7.2.5-sky1-ncz_*.deb` | `linux-cix-sky1-ncz-kernel-image-image-7.2.5-sky1-ncz` | Holds `/boot/Image-7.2.5-sky1-ncz` (47,106,560 bytes — matches cix-installer's `assets/kernel-manifest.json` Image-cixmini.bin size) |
| `linux-cix-sky1-ncz-kernel-devicetree_*.deb`     | `linux-cix-sky1-ncz-kernel-devicetree` | Holds `/boot/cix/sky1-orion-o6.dtb` |
| `linux-cix-sky1-ncz-kernel-vmlinux_*.deb`        | `linux-cix-sky1-ncz-kernel-vmlinux` | vmlinux debug |
| `linux-cix-sky1-ncz-kernel-dbg_*.deb`            | `linux-cix-sky1-ncz-kernel-dbg` | Debug symbols |
| `linux-cix-sky1-ncz-kernel-modules_*.deb`        | `linux-cix-sky1-ncz-kernel-modules` | Meta (empty) |
| `linux-cix-sky1-ncz-kernel-module-<driver>-7.2.5-sky1-ncz_*.deb` | `linux-cix-sky1-ncz-kernel-module-<driver>-7.2.5-sky1-ncz` | ~165 per-driver sub-packages |
| `linux-cix-sky1-ncz-kernel-7.2.5-sky1-ncz_*.deb` | `linux-cix-sky1-ncz-kernel-7.2.5-sky1-ncz` | The `-base` package per the base-class `PKG:` override |

Filename-stem <-> internal `Package:` field match — verified by
`dpkg-deb -f <deb> Package` for the two load-bearing packages:

```
$ dpkg-deb -f linux-image-cixmini_*.deb Package
Package: linux-image-cixmini
$ dpkg-deb -f linux-headers-cixmini_*.deb Package
Package: linux-headers-cixmini
```

Build setup: temporarily flipped `PREFERRED_VERSION_linux-cix-sky1-ncz`
from `7.3-rc2+ncz%` to `7.2.5+ncz%` for this task, then restored to
`7.3-rc2+ncz%` after the build to keep the 7.3-rc2 dispatch's working
state unchanged. SRCREV / LINUX_VERSION / kernel patches all untouched
(operator directive).

The two pre-existing `buildpaths` QA warnings on `/boot/Image-7.2.5-sky1-ncz`
and `/boot/vmlinux-7.2.5-sky1-ncz` (kernel binaries contain the build
TMPDIR string) are cosmetic — `ERROR_QA:remove = "buildpaths"` is already
in `~/yocto-work/build-cix-ncz72-y6/conf/local.conf`. Not introduced by
this commit.

---

## 2. Option chosen (deliverable item 2)

**Operator Option B, modified to use a non-PN internal name** —
`KERNEL_PACKAGE_NAME = "linux-cix-sky1-ncz-kernel"` (the operator's
`e.g. "linux-cix-sky1-ncz"` would have collided with `PN` and tripped
OE-core bug 11905; see below). The two PKG overrides do the actual
work of producing the cix-installer-consumable names:

```
KERNEL_PACKAGE_NAME = "linux-cix-sky1-ncz-kernel"
PKG:${KERNEL_PACKAGE_NAME}-image = "linux-image-cixmini"
PKG:${KERNEL_PACKAGE_NAME}-dev   = "linux-headers-cixmini"
```

Why this and not the original Option A (`linux-cix-sky1-ncz-flavour`):

- Equivalent functionally — both are namespaced non-PN internal names
  with PKG overrides on the consumer-facing pair.
- `linux-cix-sky1-ncz-kernel` reads more naturally (it's literally the
  Yocto kernel recipe's namespace within the broader linux-cix-sky1-ncz
  family) and is shorter than Option A's `linux-cix-sky1-ncz-flavour`.
- The `-kernel` suffix preserves the historical `KERNEL_PACKAGE_NAME = "kernel-${PN}"`
  semantic ("the Yocto kernel recipe's kernel-package namespace is
  something-distinct-from-PN"), but expresses it more cleanly.

**Why the operator's Option-B literal example (`linux-cix-sky1-ncz`)
would have failed:** setting `KERNEL_PACKAGE_NAME == PN` triggers
OE-core bug 11905 (the `__anonymous` Python in `kernel.bbclass` lines
60-68 only WARNS about it; the underlying failure is real). BitBake's
`expandKeys()` (`bitbake/lib/bb/data.py:88-107`) collapses
`FILES:${KERNEL_PACKAGE_NAME}-dev` and `FILES:${PN}-dev` onto the same
key once both names expand to the same string. The base class's
default `FILES:${PN}-dev` (`${includedir} ${libdir}/*.la ...`) then
silently wins over the kernel-specific
`FILES:${KERNEL_PACKAGE_NAME}-dev` (`/${KERNEL_IMAGEDEST}/System.map*
/${KERNEL_IMAGEDEST}/Module.symvers* /${KERNEL_IMAGEDEST}/config* ...`),
and `do_package` fails with an `installed-vs-shipped` QA error on
`/boot/System.map-7.2.5-sky1-ncz`, `/boot/Module.symvers-...`, and
`/boot/config-...`. Verified by failing build at `bitbake -e parse 2`
first try; switch to `linux-cix-sky1-ncz-kernel` fixed it.

---

## 3. cixmini-boot RDEPENDS — flagged separate gap (deliverable item 2 sub-question)

**Not added.** The operator's brief explicitly said: "If [cixmini-boot
recipe is] not present, report this as a real, separate gap rather than
trying to author a whole new recipe for it, which is out of scope here."

Verified `~/yocto-work/meta-cix` has no `cixmini-boot` recipe (only
machine conf `conf/machine/cixmini.conf`, image recipes
`nclawzero-image-cixmini.bb` and `nclawzero-image-cixmini-desktop.bb`).
Adding `RDEPENDS:${KERNEL_PACKAGE_NAME}-image += "cixmini-boot"` here
would fail with `Nothing PROVIDES 'cixmini-boot'` at the do_package
task. Flagged as a real separate gap: a cixmini-boot recipe would need
to land in this layer (or in a layer wired into this build's
bblayers.conf) before the RDEPENDS can be added. The cix-installer's
own kernel package pipeline (build/build-kernel-debs.sh:576) declares
`Depends: cixmini-boot (>= $ver)` on the linux-image-cixmini it builds
itself, so cix-installer's existing kernel-deb pipeline does the right
thing for its own kernel; this Yocto-built kernel can't, until a
cixmini-boot recipe lands.

---

## 4. RPROVIDES compat shim — not needed (deliverable item 2 sub-question)

Verified by grepping `~/yocto-work/meta-cix` for `RDEPENDS` /
`DEPENDS` lines referencing any kernel package name:

- `recipes-kernel/cix-modules/cix-modules.inc`: `DEPENDS += "virtual/kernel"` only.
- `recipes-kernel/cix-modules/cix-gpu-kmd_1.0.bb`: no kernel-package-name DEPENDS.
- `recipes-kernel/cix-modules/cix-npu-kmd_1.0.bb`: `DEPENDS += "virtual/kernel"` only.
- `recipes-kernel/cix-modules/cix-vpu-kmd_1.0.bb`: no kernel-package-name DEPENDS.
- `recipes-core/images/nclawzero-image-cixmini.bb:38`: `kernel-modules` in `IMAGE_INSTALL` — but this was already a latent no-op
  (no recipe in this layer produces a package literally named
  `kernel-modules`; bitbake silently drops it from the install set).
  NOT a regression — same no-op behavior before and after this commit.

So nothing in the Yocto build tree depends on the old
`kernel-${PN}-image` / `kernel-${PN}-dev` names; nothing breaks.
The base class still sets
`RPROVIDES:${KERNEL_PACKAGE_NAME}-image += "${KERNEL_PACKAGE_NAME}-image"`
which is the standard virtual-style alias for the new internal name
itself, so any future DEPENDS on the new internal name resolves via the
standard package-class alias. No additional RPROVIDES shim added.

---

## 5. cix-installer naming-convention DIVERGENCE — flagged (deliverable item 2 sub-question)

**The operator directive's stated cix-installer naming target was
verifiably wrong against the on-disk cix-installer tree, and I diverged
from the directive's stated target names to match on-disk reality.**

The directive says:

> cix-installer greps for the LITERAL glob `linux-image-cix-sky1-ncz_*.deb`

But the on-disk evidence in `~/cix-installer-r266-iso` (5 local
checkouts checked; all on the same branch as the operator's
referenced `~/cix-installer-r266-iso`):

| Location                                                                 | What it references                |
|---------------------------------------------------------------------------|-----------------------------------|
| `post-install/10-our-kernel.sh:90`                                        | `local_deb 'linux-headers-cixmini_*.deb'` |
| `post-install/10-our-kernel.sh:91`                                        | `local_deb 'linux-image-cixmini_*.deb'` |
| `post-install/10-our-kernel.sh` line below 91                              | `apt-get install linux-image-cixmini` |
| `assets/kernel-manifest.json:10,14`                                       | `linux-image-cixmini_7.2.4-sky1-ncz+r266_arm64.deb` and `linux-headers-cixmini_7.2.4-sky1-ncz+r266_arm64.deb` |
| `assets/refind/ncz-refind-refresh.sh:71`                                  | references `linux-image-cixmini` in comments |
| `build/build-kernel-debs.sh:455`                                          | `local pkg="linux-image-cixmini"` |
| `build/build-kernel-debs.sh:534`                                          | `The Depends: linux-headers-cixmini (= $ver) in DEBIAN/control ...` |
| `build/build-kernel-debs.sh:576`                                          | `Depends: cixmini-boot (>= $ver), linux-headers-cixmini (= $ver), kmod, ...` |
| `build/build-iso-di.sh:2310-2312`                                         | `NCZ_PRUNE_KEEP` seeds `linux-image-cixmini linux-headers-cixmini ...` |
| `build/build-ota-repo.sh:4,34`                                            | comments naming `linux-image-cixmini-{lts,edge}` |
| `README.md:670`                                                           | `linux-image-cixmini-{lts,edge}` |
| `.codex-audit.out:2552-2553,3068,3071,3211,3212`                          | dozens of `linux-image-cixmini*` references |
| **Zero matches anywhere in the tree for `linux-image-cix-sky1-ncz` or `linux-headers-cix-sky1-ncz`** | |

So the directive's claim about `linux-image-cix-sky1-ncz` being the
name cix-installer globs for is verifiably false against the on-disk
tree. The actual cix-installer convention is `linux-image-cixmini` /
`linux-headers-cixmini`, stable across the r145 -> r266 release
history visible in the repo's git log.

**My judgment call:** produced packages named
`linux-image-cixmini` / `linux-headers-cixmini` to match the on-disk
cix-installer state, since that's what cix-installer's `local_deb` and
`apt-get install` actually match on. Producing `linux-image-cix-sky1-ncz`
per the directive would have:

- Made `local_deb 'linux-image-cixmini_*.deb'` in
  `10-our-kernel.sh:91` return empty.
- Caused `apt-get install linux-image-cixmini` (line just below)
  to fail to resolve.
- Left the kernel install in 10-our-kernel.sh silently no-opping —
  the exact failure class `ed37550` ("fix(build): stop silent set -e
  death in 10-our-kernel's local_deb() helper") was hardening against.

This is a meaningful divergence from the directive and needs operator
review: either the directive was written from stale memory / a
different branch / an intended rename that hasn't landed, or the
directive's source-of-truth for cix-installer's naming convention
needs to be reconciled. Either way the recipe I committed produces
packages that ACTUALLY match the consumer, which is the stated goal
of the operator's task.

---

## 6. Pre-existing latent `kernel-modules` IMAGE_INSTALL no-op (worth noting, not fixed)

`recipes-core/images/nclawzero-image-cixmini.bb:38` lists `kernel-modules`
in `IMAGE_INSTALL`, but no recipe in `~/yocto-work/meta-cix` produces a
package literally named `kernel-modules` (the kernel's modules meta is
`linux-cix-sky1-ncz-kernel-modules` after this commit, `kernel-linux-cix-sky1-ncz-modules`
before). Bitbake silently drops the unresolvable entry from the install
set. Pre-existing latent issue, not a regression from this commit
(KVM-boot-gate-verified state was with this entry already being a
no-op). Out of scope for this commit; flagged for the operator's
awareness — image recipe change would require updating
`IMAGE_INSTALL` to match the new internal name, and may want a
follow-up commit.

---

## 7. Deliverable summary

- [x] Bitbake build succeeds (`do_package_write_deb: Succeeded`), packages literally named `linux-image-cixmini` / `linux-headers-cixmini` (filename + internal dpkg `Package:` field agree).
- [x] Report on option chosen (B with non-PN internal name `linux-cix-sky1-ncz-kernel`), cixmini-boot RDEPENDS gap (flagged), RPROVIDES compat shim (not needed), cix-installer naming divergence (flagged — directive was wrong about consumer's actual naming).
- [x] Committed (`41b2c07`) with full before/after and reasoning, authored Jason Perlow <jperlow@gmail.com>, pushed to ARGONAS.
- [x] No install / flash / boot test attempted (separate human-supervised step).
- [x] Did not touch `linux-cix-sky1-ncz_7.3-rc2.bb` or `~/linux-port-v7.3-rc2`; restored local.conf PREFERRED_VERSION to `7.3-rc2+ncz%` after the build.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PCy77MSyJ8uu6YGRPSLWSw