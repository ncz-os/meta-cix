# meta-cix

`meta-cix` is the first-pass Yocto BSP layer for the nclawzero `cixmini`
target: Cix Sky1 / CP8180 on the Minisforum MS-R1 edge device platform.

The hardware is not in hand yet, so this repository is intentionally a
bootstrap scaffold. It is meant to parse cleanly, document the known upstream
inputs, and give the fleet a stable place to land the real board fixes once the
MS-R1 arrives.

## Target

- Machine: `cixmini`
- SoC family: Cix Sky1 / CP8180
- Reference platform: Minisforum MS-R1
- Architecture: `aarch64`
- Firmware model: UEFI + ACPI
- Yocto series: Scarthgap
- Image recipe: `nclawzero-image-cixmini`

The Cix mainline notes currently require `clk_ignore_unused` on the kernel
command line. The machine config appends it through `APPEND`.

## Upstream Survey

No public Cix Yocto/OpenEmbedded BSP layer was found during bootstrap under the
expected names `meta-cix`, `cix-sky1`, or `cixtech-yocto`.

Relevant upstream inputs found:

- Cix manifest: <https://github.com/cixtech/cix-manifest>
- Cix Linux mainline patch stack: <https://github.com/cixtech/cix-linux-main>
- Cix developer docs: <https://github.com/cixtech/cix-developer-docs>
- Existing fleet pattern: <https://gitlab.com/perlowja/meta-nclawzero>
- Base fleet layer pattern: <https://gitlab.com/perlowja/meta-nclawzero-base>

The Cix public manifest is Debian/BSP oriented rather than Yocto oriented. The
kernel recipe here therefore starts from Torvalds Linux `v7.0-rc4` and applies
the pinned `cix-linux-main` `patches-7.0` stack, matching the ULTRA survey build
shape.

## Kernel Source

ULTRA already has a successful Debian-packaged kernel survey build:

```text
~/cixtech-survey/kernel-build/deb-out/
```

That output contains `linux-image-7.0.0-rc4-cix-ncz`, headers, libc headers,
debug symbols, `.changes`, and `.buildinfo`. Those `.deb` artifacts are useful
for inspection and emergency bootstrapping, but they are not a clean Yocto
kernel source. The useful source inputs are:

```text
~/cixtech-survey/kernel-build/linux
~/cixtech-survey/cix-linux-main
```

`recipes-kernel/linux-cix-ncz/linux-cix-ncz_7.0.bb` encodes that flow
reproducibly from public git sources instead of pointing at the local `.deb`
directory.

## Build Environment

The layer is expected at this path on ULTRA:

```text
~/build-env/workspace/meta-cix
```

There was no pre-existing Poky checkout under `~/build-env` during bootstrap.
Use Scarthgap to match `meta-nclawzero` and `meta-nclawzero-base`.

Minimal setup:

```bash
mkdir -p ~/build-env/workspace
cd ~/build-env/workspace
git clone --depth=1 --branch=scarthgap https://git.yoctoproject.org/poky
git clone https://gitlab.com/nclawzero/meta-cix.git

cd poky
source oe-init-build-env build-cixmini
bitbake-layers add-layer ../../meta-cix
cat >> conf/local.conf <<'EOF'
MACHINE = "cixmini"
DISTRO = "nclawzero"
EOF
bitbake -p
```

When hardware blockers are resolved, the image entry point is:

```bash
bitbake nclawzero-image-cixmini
```

## Layer Contents

- `conf/machine/cixmini.conf`: generic arm64 UEFI/ACPI machine config for Sky1
- `conf/distro/nclawzero.conf`: Scarthgap distro config derived from Poky
- `recipes-bsp/cix-sky1-firmware`: platform firmware placeholders and DSP blob
- `recipes-kernel/linux-cix-ncz`: Sky1 kernel recipe scaffold
- `recipes-core/images/nclawzero-image-cixmini.bb`: headless first-pass image
- `conf/templates/cixmini`: sample `bblayers.conf` and `local.conf` snippets

## Investigate Further

- Confirm Minisforum MS-R1 ACPI tables, UEFI defaults, and boot order on real
  hardware.
- Confirm whether MS-R1 needs board-specific Wi-Fi, Bluetooth, Ethernet, NPU,
  VPU, or display firmware beyond the Cix DSP blob.
- Decide whether VPU/NPU support should stay as DKMS-style external drivers or
  become Yocto recipes in this layer.
- Replace genericarm64 WIC assumptions with a board-tested partition layout.
- Re-run `yocto-check-layer` after the kernel and firmware recipes are promoted
  from scaffold to production-ready recipes.

## Maintainer

Jason Perlow <jperlow@gmail.com>

Embedded-Linux background traces back to **Sharp Electronics' Software Developer Liaison for the Zaurus PDA platform, December 2002 – February 2003**. The community fork born from that platform — OpenZaurus (2003-2007) — became OpenEmbedded → Ångström → Yocto. Public postmortem of the Zaurus platform's developer-relations failures, written in February 2006, is at [computingunplugged.com](https://computingunplugged.com/article/the-future-of-the-palm-platform-lessons-learned-from-the-sharp-zaurus/) — many of those lessons (free/near-free tools, breadth-before-launch documentation, in-timezone English-speaking support, full-environment rebuildability, no SDK fragmentation) shape this layer's design today.

Lineage:

```
Sharp Zaurus (2002)         — closed SharpROM, broken developer relations
  ↓
OpenZaurus (2003-2007)      — community fork
  ↓
OpenEmbedded                — generalized framework
  ↓
Ångström                    — distribution
  ↓
Yocto                       — what meta-cix and meta-tegra both build on
```

Linux Foundation involvement includes prior LF Editorial Director role and ongoing participation in the Yocto Project and OpenEmbedded community.

Adjacent active work in the wider claw-family ecosystem:

- [`meta-nclawzero`](https://gitlab.com/perlowja/meta-nclawzero), [`meta-nclawzero-base`](https://gitlab.com/perlowja/meta-nclawzero-base) — sister Yocto BSP layers for the parent nclawzero distro this layer serves
- [`nclawzero/*`](https://gitlab.com/nclawzero) — distro maintainership
- [`openclaw/openclaw`](https://github.com/openclaw/openclaw), [`zeroclaw-labs/zeroclaw`](https://github.com/zeroclaw-labs/zeroclaw) — upstream contributions in the agent runtime layer that consumes this BSP

Patches and BSP feedback welcome via GitLab MRs or GitHub PRs.


## Build infrastructure & partners

Continuous integration and package distribution for this project are generously
supported by our open-source infrastructure partners:

- **[GitLab](https://gitlab.com/)** — canonical source hosting and CI pipelines
  (format / lint / test gates), via the
  [GitLab for Open Source](https://about.gitlab.com/solutions/open-source/) program.
- **[Buildkite](https://buildkite.com/)** — CI/CD orchestration with hosted macOS
  and Linux agents, and our APT package registry host
  (`packages.buildkite.com/ncz-os/ncz`), via the
  [Buildkite Open Source](https://buildkite.com/pricing) program.

Thank you to both for backing open-source software.
