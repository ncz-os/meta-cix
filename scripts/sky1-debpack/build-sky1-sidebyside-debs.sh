#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# build-sky1-sidebyside-debs.sh -- package a bitbake-built Sky1 kernel as
# Debian packages that install NEXT TO the running kernel (add-only).
#
# WHY
# O6N (the Sky1 kernel test host) runs 7.3.0 from the single-name packages
# linux-image-cixmini / linux-headers-cixmini (r293). The bitbake output of the
# 7.3.1 build cannot be installed there as-is (O6N install stop, 2026-11-02):
#   1. the linux-image-cixmini / linux-headers-cixmini metas would UPGRADE the
#      installed 7.3.0 packages and so remove the 7.3.0 kernel files;
#   2. the Yocto debs ship only /boot/Image-<KVER>: no /boot/vmlinuz-<KVER>,
#      no initramfs step, so the add-only rEFInd tool refuses;
#   3. the Yocto headers deb has no build tree, so DKMS cannot build;
#   4. the DKMS debs' postinst runs dracut for `uname -r`, i.e. it rewrites the
#      RUNNING (default entry) kernel's initramfs;
#   5. the Yocto cixmini-boot is 1.0-r0 (installed: 1.6+r293), a downgrade.
#
# WHAT IT BUILDS (no kernel is compiled here; every input comes from ONE
# bitbake build of one SRCREV, see --yocto-debs and --headers-tar):
#   linux-image-<KVER>     /boot/vmlinuz-<KVER> (the bitbake Image), config,
#                          System.map, the full module tree, and the prebuilt
#                          GPU modules in updates/ (as r293 does). postinst:
#                          depmod, DKMS build+install for <KVER> only, dracut
#                          for <KVER> only (never the running kernel), then the
#                          add-only rEFInd stage. It never runs
#                          /etc/kernel/postinst.d, so no legacy hook can fire.
#   linux-headers-<KVER>   /usr/lib/modules/<KVER>/build: the full DKMS build
#                          tree from the same build (scripts/, Makefile,
#                          .config, Module.symvers); postinst rebuilds the host
#                          tools natively.
#   cixmini-boot           <CIXMINI_BOOT_VER> (> installed 1.6+r293): ships the
#                          add-only ncz-refind-refresh and replaces the old
#                          wipe-and-regenerate wrapper/hooks, including the
#                          copy the apt DPkg::Post-Invoke hook restores.
# No DKMS source packages are shipped: the ones on O6N are already at these
# versions (re-installing them would run their uname -r dracut postinst), and
# the installed NPU package (cix-npu-driver-dkms) is rebuilt for <KVER> by the
# image postinst, so cix-npu-kmd-dkms (same aipu module) is not shipped.
#
# Names are per kernel release with no Provides/Conflicts/Replaces on the
# cixmini names, so apt never removes or upgrades the 7.3.0 packages.
#
# usage: build-sky1-sidebyside-debs.sh --kver KVER --rev rNNN \
#          --yocto-debs DIR --headers-tar FILE --gpu-ko DIR --out DIR
#
# Runs on any Debian/Fedora host with dpkg-deb, tar, zstd and modinfo.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

KVER=
REV=
YOCTO=
HDR_TAR=
GPU_KO=
OUT=
CIXMINI_BOOT_VER=${CIXMINI_BOOT_VER:-1.7}
MAINT="Jason Perlow <jperlow@gmail.com>"

die() { echo "build-sky1-sidebyside-debs: ERROR: $*" >&2; exit 1; }
log() { echo "build-sky1-sidebyside-debs: $*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --kver) KVER="$2"; shift 2 ;;
        --rev) REV="$2"; shift 2 ;;
        --yocto-debs) YOCTO="$2"; shift 2 ;;
        --headers-tar) HDR_TAR="$2"; shift 2 ;;
        --gpu-ko) GPU_KO="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        -h|--help) sed -n '2,50p' "$0"; exit 0 ;;
        *) die "unknown argument $1" ;;
    esac
done
[ -n "$KVER" ] && [ -n "$REV" ] && [ -n "$YOCTO" ] && [ -n "$HDR_TAR" ] &&
    [ -n "$GPU_KO" ] && [ -n "$OUT" ] || die "missing argument (see --help)"
case "$KVER" in *-sky1-ncz) ;; *) die "KVER $KVER is not a -sky1-ncz release" ;; esac
case "$REV" in r[0-9]*) ;; *) die "--rev must look like r295" ;; esac
for t in dpkg-deb tar zstd modinfo sha256sum find; do
    command -v "$t" >/dev/null || die "$t not found"
done

PKGVER="$KVER+$REV"
BOOTVER="$CIXMINI_BOOT_VER+$REV"
IMG_PKG="linux-image-$KVER"
HDR_PKG="linux-headers-$KVER"

# Reproducible timestamps: the bitbake build's source epoch, recorded in the
# Image deb; fall back to the Image's own mtime inside that deb.
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
WORK="$OUT/.work"
rm -rf "$WORK"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

one() {
    # exactly one file matching the glob, else die
    local n
    n=$(find "$YOCTO" -maxdepth 1 -name "$1" | wc -l)
    [ "$n" = 1 ] || die "expected exactly one $1 in $YOCTO, found $n"
    find "$YOCTO" -maxdepth 1 -name "$1"
}

IMAGE_DEB=$(one "kernel-linux-cix-sky1-ncz-image-image-${KVER}_*_arm64.deb")
BASE_DEB=$(one "kernel-linux-cix-sky1-ncz-${KVER}_*_arm64.deb")
YHDR_DEB=$(one "linux-headers-${KVER}_*_arm64.deb")
DTB_DEB=$(one "kernel-linux-cix-sky1-ncz-devicetree_*_arm64.deb")

# --- 1. inputs, unpacked -----------------------------------------------------
X="$WORK/x"
mkdir -p "$X"
dpkg-deb -x "$IMAGE_DEB" "$X"
dpkg-deb -x "$BASE_DEB" "$X"
dpkg-deb -x "$YHDR_DEB" "$X"
dpkg-deb -x "$DTB_DEB" "$X"
nmod=0
for d in "$YOCTO"/kernel-linux-cix-sky1-ncz-module-*-"${KVER}"_*_arm64.deb; do
    [ -e "$d" ] || continue
    dpkg-deb -x "$d" "$X"
    nmod=$((nmod + 1))
done
[ "$nmod" -ge 300 ] || die "only $nmod module debs for $KVER in $YOCTO"

[ -s "$X/boot/Image-$KVER" ] || die "no /boot/Image-$KVER in $IMAGE_DEB"
[ -s "$X/boot/config-$KVER" ] || die "no /boot/config-$KVER in $YHDR_DEB"
[ -s "$X/boot/System.map-$KVER" ] || die "no /boot/System.map-$KVER in $YHDR_DEB"
[ -s "$X/boot/Module.symvers-$KVER" ] || die "no /boot/Module.symvers-$KVER in $YHDR_DEB"
MODDIR="$X/usr/lib/modules/$KVER"
[ -d "$MODDIR/kernel" ] || die "no module tree for $KVER"

H="$WORK/h"
mkdir -p "$H"
tar --zstd -xf "$HDR_TAR" -C "$H"
B="$H/lib/modules/$KVER/build"
for f in Makefile .config Module.symvers include/config/kernel.release scripts/Makefile; do
    [ -e "$B/$f" ] || die "headers tarball has no build/$f"
done

# --- 2. same-build gates -----------------------------------------------------
# Every part must come from the one bitbake build: Image, modules and the
# headers tree. Fail rather than ship a mixed set.
grep -aq "Linux version $KVER " "$X/boot/Image-$KVER" || die "Image does not say 'Linux version $KVER'"
[ "$(cat "$B/include/config/kernel.release")" = "$KVER" ] || die "headers kernel.release != $KVER"
cmp -s "$B/.config" "$X/boot/config-$KVER" || die "headers .config differs from /boot/config-$KVER"
cmp -s "$B/Module.symvers" "$X/boot/Module.symvers-$KVER" || die "headers Module.symvers differs from the image build"
nko=$(find "$MODDIR" -name '*.ko' | wc -l)
[ "$nko" -ge 300 ] || die "only $nko modules in the tree"
bad=0
while IFS= read -r ko; do
    vm=$(modinfo -F vermagic "$ko" | awk '{print $1}')
    [ "$vm" = "$KVER" ] || { echo "vermagic $vm != $KVER: $ko" >&2; bad=1; }
done < <(find "$MODDIR" -name '*.ko' | sort | awk 'NR % 25 == 1')
[ "$bad" = 0 ] || die "module vermagic mismatch"
ngpu=0
for ko in mali_kbase memory_group_manager protected_memory_allocator; do
    [ -s "$GPU_KO/$ko.ko" ] || die "no prebuilt $ko.ko in $GPU_KO"
    vm=$(modinfo -F vermagic "$GPU_KO/$ko.ko" | awk '{print $1}')
    [ "$vm" = "$KVER" ] || die "$ko.ko vermagic $vm != $KVER"
    ngpu=$((ngpu + 1))
done
log "inputs OK: Image + $nko modules + headers tree + $ngpu GPU modules, all $KVER"

EPOCH=$(stat -c %Y "$X/boot/Image-$KVER")
# dpkg-deb clamps member and archive timestamps to SOURCE_DATE_EPOCH, which
# makes two runs over the same inputs byte-identical.
export SOURCE_DATE_EPOCH=$EPOCH

finalize() {
    # deterministic modes/mtimes; dpkg-deb --root-owner-group sets root:root
    find "$1" -exec touch -h -d "@$EPOCH" {} +
}
isize() { du -sk --exclude=DEBIAN "$1" | awk '{print $1}'; }

# --- 3. linux-image-<KVER> ---------------------------------------------------
R="$WORK/$IMG_PKG"
install -d "$R/DEBIAN" "$R/boot" "$R/usr/lib/modules" "$R/usr/lib/$IMG_PKG/cix"
install -m 0644 "$X/boot/Image-$KVER" "$R/boot/vmlinuz-$KVER"
install -m 0644 "$X/boot/config-$KVER" "$R/boot/config-$KVER"
install -m 0644 "$X/boot/System.map-$KVER" "$R/boot/System.map-$KVER"
cp -a "$MODDIR" "$R/usr/lib/modules/$KVER"
rm -f "$R/usr/lib/modules/$KVER"/modules.dep* "$R/usr/lib/modules/$KVER"/modules.alias* \
      "$R/usr/lib/modules/$KVER"/modules.symbols* "$R/usr/lib/modules/$KVER"/modules.devname \
      "$R/usr/lib/modules/$KVER"/modules.softdep "$R/usr/lib/modules/$KVER"/modules.weakdep
install -d "$R/usr/lib/modules/$KVER/updates"
for ko in mali_kbase memory_group_manager protected_memory_allocator; do
    install -m 0644 "$GPU_KO/$ko.ko" "$R/usr/lib/modules/$KVER/updates/$ko.ko"
done
# The device tree is shipped for reference only, outside /boot: O6N boots
# ACPI (acpi=force) and its entries load no device tree.
if [ -s "$X/boot/sky1-orion-o6.dtb" ]; then
    install -m 0644 "$X/boot/sky1-orion-o6.dtb" "$R/usr/lib/$IMG_PKG/cix/sky1-orion-o6.dtb"
fi
sed "s|__KVER__|$KVER|g" "$HERE/linux-image.postinst" >"$R/DEBIAN/postinst"
sed "s|__KVER__|$KVER|g" "$HERE/linux-image.prerm" >"$R/DEBIAN/prerm"
sed "s|__KVER__|$KVER|g" "$HERE/linux-image.postrm" >"$R/DEBIAN/postrm"
chmod 0755 "$R/DEBIAN/postinst" "$R/DEBIAN/prerm" "$R/DEBIAN/postrm"
cat >"$R/DEBIAN/control" <<EOF
Package: $IMG_PKG
Version: $PKGVER
Architecture: arm64
Maintainer: $MAINT
Section: kernel
Priority: optional
Installed-Size: $(isize "$R")
Depends: $HDR_PKG (= $PKGVER), cixmini-boot (>= $BOOTVER), kmod, dracut | linux-initramfs-tool
Recommends: dkms
Description: NCZ Sky1 kernel $KVER (side-by-side)
 Kernel image, modules and the prebuilt GPU modules for $KVER. Installs next
 to any other kernel: it does not replace or remove linux-image-cixmini or
 another release. The postinst builds the registered DKMS modules and the
 initramfs for $KVER only, then stages $KVER as one extra rEFInd entry; the
 default boot entry is not changed (promote with
 'ncz-refind-refresh --promote $KVER').
EOF
finalize "$R"
dpkg-deb --root-owner-group -Zxz --build "$R" "$OUT/${IMG_PKG}_${PKGVER}_arm64.deb" >/dev/null

# --- 4. linux-headers-<KVER> -------------------------------------------------
R="$WORK/$HDR_PKG"
install -d "$R/DEBIAN" "$R/usr/lib/modules/$KVER"
cp -a "$B" "$R/usr/lib/modules/$KVER/build"
sed "s|__KVER__|$KVER|g" "$HERE/linux-headers.postinst" >"$R/DEBIAN/postinst"
sed "s|__KVER__|$KVER|g" "$HERE/linux-headers.postrm" >"$R/DEBIAN/postrm"
chmod 0755 "$R/DEBIAN/postinst" "$R/DEBIAN/postrm"
cat >"$R/DEBIAN/control" <<EOF
Package: $HDR_PKG
Version: $PKGVER
Architecture: arm64
Maintainer: $MAINT
Section: kernel
Priority: optional
Installed-Size: $(isize "$R")
Depends: kmod, make, gcc
Recommends: dkms, flex, bison, bc, libelf-dev, libssl-dev
Description: NCZ Sky1 kernel headers $KVER (side-by-side, DKMS build tree)
 The full external-module build tree for $KVER at
 /usr/lib/modules/$KVER/build (Makefile, .config, Module.symvers, scripts/).
 The postinst rebuilds the host tools natively. Installs next to any other
 headers package.
EOF
finalize "$R"
dpkg-deb --root-owner-group -Zxz --build "$R" "$OUT/${HDR_PKG}_${PKGVER}_arm64.deb" >/dev/null

# --- 5. cixmini-boot ---------------------------------------------------------
R="$WORK/cixmini-boot"
install -d "$R/DEBIAN" "$R/usr/lib/cixmini" "$R/etc/kernel/postinst.d" "$R/etc/kernel/postrm.d"
install -m 0755 "$REPO/scripts/ncz-refind-refresh" "$R/usr/lib/cixmini/ncz-refind-refresh"
install -m 0755 "$REPO/scripts/cixmini-boot-refresh" "$R/usr/lib/cixmini/cixmini-boot-refresh"
install -m 0755 "$HERE/cixmini-update-bootloader" "$R/usr/lib/cixmini/cixmini-update-bootloader"
install -m 0755 "$HERE/zz-cixmini-bootloader.postinst.d" "$R/etc/kernel/postinst.d/zz-cixmini-bootloader"
install -m 0755 "$HERE/zz-cixmini-bootloader.postrm.d" "$R/etc/kernel/postrm.d/zz-cixmini-bootloader"
install -m 0755 "$HERE/cixmini-boot.postinst" "$R/DEBIAN/postinst"
cat >"$R/DEBIAN/control" <<EOF
Package: cixmini-boot
Version: $BOOTVER
Architecture: arm64
Maintainer: $MAINT
Section: admin
Priority: optional
Installed-Size: $(isize "$R")
Depends: systemd, efibootmgr, util-linux, kmod, ncz-usb-recovery, bash, coreutils, mawk | awk, grep, sed
Description: NCZ cixmini boot policy: add-only rEFInd kernel staging
 Installing a kernel adds ONE rEFInd menuentry for it and never removes,
 repoints or re-stages an existing kernel, never changes default_selection
 and never calls efibootmgr. Promotion is the separate command
 'ncz-refind-refresh --promote KVER'. Replaces the wipe-and-regenerate
 generator of cixmini-boot 1.6 and earlier, including the wrapper copy that
 the installer's apt DPkg::Post-Invoke hook restores.
EOF
finalize "$R"
dpkg-deb --root-owner-group --build "$R" "$OUT/cixmini-boot_${BOOTVER}_arm64.deb" >/dev/null

# --- 6. record -----------------------------------------------------------------
(
    cd "$OUT"
    sha256sum ./*.deb | sed 's| \./| |' >SHA256SUMS
)
{
    echo "kver=$KVER"
    echo "pkgver=$PKGVER"
    echo "cixmini_boot=$BOOTVER"
    echo "image_deb_input=$(basename "$IMAGE_DEB") $(sha256sum "$IMAGE_DEB" | awk '{print $1}')"
    echo "base_deb_input=$(basename "$BASE_DEB") $(sha256sum "$BASE_DEB" | awk '{print $1}')"
    echo "yocto_headers_deb_input=$(basename "$YHDR_DEB") $(sha256sum "$YHDR_DEB" | awk '{print $1}')"
    echo "dtb_deb_input=$(basename "$DTB_DEB") $(sha256sum "$DTB_DEB" | awk '{print $1}')"
    echo "module_debs_input=$nmod"
    echo "headers_tar_input=$(basename "$HDR_TAR") $(sha256sum "$HDR_TAR" | awk '{print $1}')"
    echo "image_sha256=$(sha256sum "$X/boot/Image-$KVER" | awk '{print $1}')"
    echo "config_sha256=$(sha256sum "$X/boot/config-$KVER" | awk '{print $1}')"
    echo "module_symvers_sha256=$(sha256sum "$X/boot/Module.symvers-$KVER" | awk '{print $1}')"
    for ko in mali_kbase memory_group_manager protected_memory_allocator; do
        echo "gpu_ko_$ko=$(sha256sum "$GPU_KO/$ko.ko" | awk '{print $1}')"
    done
    echo "modules=$nko"
    echo "source_epoch=$EPOCH"
    echo "packer_commit=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "packer_dirty=$(git -C "$REPO" status --porcelain 2>/dev/null | grep -c . || true)"
} >"$OUT/PACK-PROVENANCE.txt"
log "built: $(cd "$OUT" && ls ./*.deb | tr '\n' ' ')"
