#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# test-o6n-sidebyside-install.sh -- prove the side-by-side Sky1 kernel debs are
# add-only on an O6N-shaped system WITHOUT touching O6N.
#
#   A. apt-get -s against O6N's REAL dpkg status file (captured 2026-11-02):
#      zero removals, no downgrade, only the three packages.
#   B. a throwaway Debian forky arm64 container rebuilt to O6N's 7.3.0 state
#      from the published r293 packages + O6N's hooks + O6N's ESP, then a real
#      apt install (o6n-sim-in-container.sh): default initrd/ESP untouched,
#      refind.conf append-only, DKMS built for the new kernel.
#
# usage: test-o6n-sidebyside-install.sh NEWDEBS_DIR BASELINE_DIR EVIDENCE_DIR
#   BASELINE_DIR holds the r293 debs (cixmini-boot 1.6+r293, linux-image/
#   headers-cixmini 7.3.0-sky1-ncz+r293, the four DKMS debs, ncz-usb-recovery
#   1.3) and the O6N backups hooks-20261102.tar, esp-20261102.tar,
#   dpkg-status.orig, boot-sha256.txt.
# Needs rootless podman with debian:forky (arm64 host). Never run it on O6N.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
NEW=$(cd "$1" && pwd)
BASE=$(cd "$2" && pwd)
EVID=$3
NEWK=${NEWK:-7.3.1-sky1-ncz}
IMG=${IMG:-docker.io/library/debian:forky}
mkdir -p "$EVID"
EVID=$(cd "$EVID" && pwd)
[ "$(uname -m)" = aarch64 ] || { echo "needs an arm64 host" >&2; exit 2; }
[ -r /proc/device-tree/model ] && grep -qi orion /proc/device-tree/model && { echo "refusing to run on a Sky1 board" >&2; exit 2; }

echo "== A. apt-get -s against O6N's dpkg status"
mkdir -p "$EVID/sim-o6n-status"
podman run --rm --network=host --cpus=2 \
    -v "$NEW:/in/new:ro" -v "$BASE:/in/baseline:ro" -v "$EVID/sim-o6n-status:/out" \
    "$IMG" bash -c '
set -u
mkdir -p /var/tmp/o6n/lists/partial /var/tmp/o6n/cache/archives/partial
cp /in/baseline/dpkg-status.orig /var/tmp/o6n/status
apt-get update -qq >/dev/null 2>&1
cd /in/new
apt-get -s -o Dir::State::status=/var/tmp/o6n/status \
    install ./cixmini-boot_*.deb ./linux-headers-'"$NEWK"'_*.deb ./linux-image-'"$NEWK"'_*.deb \
    >/out/apt-simulate-o6n-status.txt 2>&1
echo "apt rc=$?" >>/out/apt-simulate-o6n-status.txt
grep -E "^(Inst|Remv|Conf)| upgraded,|^E:" /out/apt-simulate-o6n-status.txt
'
S="$EVID/sim-o6n-status/apt-simulate-o6n-status.txt"
fail=0
grep -q "^Remv " "$S" && { echo "FAIL  O6N-status simulate shows removals"; fail=1; } || echo "PASS  O6N-status simulate: no Remv lines"
grep -q " 0 to remove" "$S" && echo "PASS  O6N-status simulate: 0 to remove" || { echo "FAIL  O6N-status simulate summary"; fail=1; }
grep -qE "^Inst cixmini-boot \[1\.6\+r293\] \(1\.[7-9]" "$S" && echo "PASS  O6N-status simulate: cixmini-boot 1.6+r293 -> 1.7 upgrade" || { echo "FAIL  cixmini-boot line: $(grep '^Inst cixmini-boot' "$S")"; fail=1; }
extra=$(grep -E "^Inst " "$S" | grep -vE "^Inst (cixmini-boot|linux-headers-$NEWK|linux-image-$NEWK) " || true)
[ -z "$extra" ] && echo "PASS  O6N-status simulate: only the three packages" || { echo "FAIL  extra packages: $extra"; fail=1; }

echo "== B. throwaway O6N-shaped container, real install"
mkdir -p "$EVID/container" "$EVID/esp-mnt"
set +e
podman run --rm --network=host --cpus=4 \
    -e NEWK="$NEWK" \
    -v "$NEW:/in/new:ro" -v "$BASE:/in/baseline:ro" -v "$EVID/container:/out" \
    -v "$EVID/esp-mnt:/boot/efi" -v "$HERE/o6n-sim-in-container.sh:/in/run.sh:ro" \
    "$IMG" bash /in/run.sh 2>&1 | tee "$EVID/container/console.log"
rc=${PIPESTATUS[0]}
set -e
podman unshare rm -rf "$EVID/esp-mnt"
echo "container rc=$rc, O6N-status simulate fail=$fail"
[ "$rc" = 0 ] && [ "$fail" = 0 ]
