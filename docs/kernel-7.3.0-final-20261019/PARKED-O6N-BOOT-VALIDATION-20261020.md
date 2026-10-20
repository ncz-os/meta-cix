# Sky1 7.3.0 final: build/gate PASS, boot validation PARKED 2026-10-20

## Status

Build + overlay modversions gate: **PASS** (see README.md in this directory,
negative control proves the gate is live). Real hardware boot validation on
O6N (192.168.207.3, the designated Sky1 boot-test system): **started,
incomplete, parked** -- O6N is physically unreachable to the operator for
~1 week and the box is currently down/unresponsive (not pingable, no SSH,
no response on either serial adapter on PROTEUS -- the adapters themselves
are most likely not currently cabled to O6N's UART, same class of issue as
an earlier braille/installer serial mixup; nothing is holding the ports
open on the PROTEUS side, `brltty` isn't even installed there). No physical
access means no recovery and no further diagnosis until the operator
returns. **Do not attempt further remote reboots of O6N on this branch
until the operator confirms physical access.**

## A real packaging-pipeline bug found and fixed while staging this build

Installing this build's `.deb` set on O6N for the boot test surfaced a real
gap that would silently break *every* future Sky1 final-kernel promotion
through this exact path, independent of the kernel content itself:

- The Yocto-built kernel image package (`kernel-linux-cix-sky1-ncz-image-
  image-<KVER>`) installs `/boot/Image-<KVER>`, **not**
  `/boot/vmlinuz-<KVER>`.
- `/usr/local/sbin/ncz-refind-refresh`'s `find_newest()` only globs
  `/boot/vmlinuz-*` (copied from the amd64 refresh script's convention).
  It never sees `/boot/Image-*`, so after installing this package it kept
  re-selecting the OLD rc7 kernel as "newest" and silently re-staged that
  one to the ESP -- a false-positive boot test would have run the wrong
  kernel while believing it tested the final one.
- Separately, no `/boot/initrd.img-<KVER>` was generated automatically for
  this package either; `update-initramfs -c -k <KVER>` had to be run by
  hand.

**Fix applied manually on O6N for this one test** (not yet landed as a
script change): created `/boot/vmlinuz-7.3.0-sky1-ncz` as a symlink to the
existing `/boot/Image-7.3.0-sky1-ncz` (mirroring the convention the kernel
package itself already uses for its own `/boot/Image -> Image-<KVER>`
symlink), then ran `update-initramfs -c -k 7.3.0-sky1-ncz` to generate the
missing initrd. After that, re-running `zz-cixmini-bootloader` correctly
staged the final kernel and the dedicated `r289` rescue entry was
confirmed untouched throughout.

**Real fix still needed, not yet written**: either (a) have the Yocto
recipe/packaging also drop a `vmlinuz-<KVER>` symlink and trigger
`update-initramfs` itself (matching what a standard Debian kernel package's
`/etc/kernel/postinst.d/initramfs-tools` hook would normally do), or (b)
teach `ncz-refind-refresh`'s `find_newest()` to also glob `/boot/Image-*`
and fall back to calling `update-initramfs` itself when no matching initrd
exists. Whoever picks this branch back up should fix this FIRST, before
attempting another boot test, so the next attempt doesn't rediscover the
same gap by hand again.

## What's left when O6N is reachable again

1. Fix the packaging/refresh-script gap above (real code change, not a
   one-off manual fix).
2. Re-stage and boot-test the final kernel on O6N for real.
3. Full accelerator pass per kernel acceptance checklist: Mali/Panthor GPU,
   VPU, NPU overlays (all already modversions-gate-clean per the README,
   but that is not a substitute for the human-supervised hardware boot the
   checklist requires).
4. Only then promote `fix/sky1-kernel-7.3.0-final-pin-20261019` to meta-cix's
   default branch, matching what already happened for amd64-kernel-t2.

## Scratch left behind (for cleanup once O6N is reachable)

- O6N: `~/sky1-73final-validate-20261020/` (380 staged `.deb` files, ~25MB
  extracted) -- reap once the box is back and this is no longer needed as
  reference.
- STUDIO: `~/Projects/sky1-final-validate-20261020/` -- cleaned up as part
  of this parking (see cleanup receipt below).
