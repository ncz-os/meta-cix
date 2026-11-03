#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# o6n-sim-in-container.sh -- runs INSIDE a throwaway Debian forky arm64
# container (see test-o6n-sidebyside-install.sh). Rebuilds the O6N 7.3.0 state
# from the real published r293 packages plus the hooks and ESP backed up from
# O6N, then installs the side-by-side 7.3.1 set with apt and checks that it
# was add-only.
#
# Mounts: /in/baseline (r293 debs, O6N backups: hooks tar, ESP tar, dpkg status)
#         /in/new      (the debs under test)       /out (evidence)
#         /boot/efi    (an empty host dir, so it is a real mount point)
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
NEWK="${NEWK:?}"
OLDK="${OLDK:-7.3.0-sky1-ncz}"
OUT=/out
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS  $*" | tee -a "$OUT/results.txt"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL  $*" | tee -a "$OUT/results.txt"; }
: >"$OUT/results.txt"

echo "== 0. tools"
apt-get update -qq >/dev/null 2>&1 || true
apt-get install -y -qq --no-install-recommends dkms dracut dracut-core build-essential flex bison bc \
    libelf-dev libssl-dev kmod zstd xz-utils systemd efibootmgr udev util-linux file \
    >"$OUT/apt-tools.log" 2>&1 || { tail -20 "$OUT/apt-tools.log"; echo "tool install failed"; exit 2; }
dpkg -l dkms dracut gcc | tail -3

echo "== 1. O6N 7.3.0 baseline from the published r293 packages"
cd /in/baseline
dpkg -i ncz-usb-recovery_1.3_arm64.deb >"$OUT/baseline-dpkg.log" 2>&1
dpkg -i cixmini-boot_1.6+r293_arm64.deb linux-headers-cixmini_7.3.0-sky1-ncz+r293_arm64.deb \
    linux-image-cixmini_7.3.0-sky1-ncz+r293_arm64.deb >>"$OUT/baseline-dpkg.log" 2>&1 ||
    { tail -30 "$OUT/baseline-dpkg.log"; echo "baseline kernel install failed"; exit 2; }
dpkg -i cix-gpu-kmd-dkms_1.0+ncz3_all.deb panthor-cix-dkms_7.2.0+ncz3_all.deb \
    cix-vpu-driver-dkms_1.0.2-ncz1+ncz3_all.deb cix-npu-driver-dkms_6.2.0-cixdeb13-260714+ncz3_all.deb \
    >>"$OUT/baseline-dpkg.log" 2>&1 || { tail -30 "$OUT/baseline-dpkg.log"; echo "baseline dkms install failed"; exit 2; }
# O6N: all four DKMS modules installed for 7.3.0 (dkms-status.txt). In the
# container `uname -r` is the build host's kernel, so build them for 7.3.0
# explicitly, then rebuild the 7.3.0 initramfs as O6N has it.
dkms autoinstall -k "$OLDK" >"$OUT/baseline-dkms.log" 2>&1 || true
dkms status | tee "$OUT/baseline-dkms-status.txt"
dracut --force --kver "$OLDK" "/boot/initrd.img-$OLDK" >"$OUT/baseline-dracut.log" 2>&1 ||
    { tail -20 "$OUT/baseline-dracut.log"; exit 2; }
# The O6N hooks as they are on the host (installer redirect wrapper, old
# regenerating ncz-refind-refresh, apt Post-Invoke hook) and its ESP.
tar -xf hooks-20261102.tar -C / --exclude='var/lib/dpkg/*'
tar -xf esp-20261102.tar -C /boot/efi
cp -a /boot/efi/EFI/BOOT/refind.conf "$OUT/refind.conf.before"
grep -q " /boot/efi " /proc/mounts && ok "ESP is a mount point in the sandbox" || no "ESP is a mount point"
[ "$(sha256sum < /boot/vmlinuz-$OLDK | cut -c1-64)" = "$(awk '/vmlinuz/{print $1}' boot-sha256.txt)" ] &&
    ok "baseline /boot/vmlinuz-$OLDK is byte-identical to O6N's" || no "baseline vmlinuz differs from O6N"

snap() {
    {
        sha256sum /boot/vmlinuz-"$OLDK" /boot/initrd.img-"$OLDK" /boot/config-"$OLDK"
        (cd /boot/efi && find . -type f -print0 | sort -z | xargs -0 sha256sum)
    } >"$OUT/$1-sha.txt"
    dpkg-query -W -f='${Package} ${Version} ${Status}\n' | sort >"$OUT/$1-dpkg.txt"
    dkms status | sort >"$OUT/$1-dkms.txt"
    find "/usr/lib/modules/$OLDK" -type f -print0 | sort -z | xargs -0 sha256sum >"$OUT/$1-oldmods-sha.txt"
}
snap before

echo "== 2. simulate"
cd /in/new
apt-get install -s ./cixmini-boot_*.deb ./linux-headers-"$NEWK"_*.deb ./linux-image-"$NEWK"_*.deb \
    >"$OUT/apt-simulate.txt" 2>&1
cat "$OUT/apt-simulate.txt" | grep -E "^(Inst|Remv|Conf)|newly installed|upgraded" | tee "$OUT/apt-simulate-summary.txt"
grep -qE "^Remv " "$OUT/apt-simulate.txt" && no "apt simulate shows removals" || ok "apt simulate: zero removals"
grep -qE " 0 to remove" "$OUT/apt-simulate.txt" && ok "apt simulate: '0 to remove'" || no "apt simulate summary lacks '0 to remove'"
if grep -E "^Inst " "$OUT/apt-simulate.txt" | grep -vE "^Inst (cixmini-boot|linux-headers-$NEWK|linux-image-$NEWK) " | grep -q .; then
    no "apt simulate pulls extra packages: $(grep -E '^Inst ' "$OUT/apt-simulate.txt" | tr '\n' ';')"
else
    ok "apt simulate installs only the three packages"
fi
if grep -E "^Inst cixmini-boot \[1\.6\+r293\] \(1\.[7-9]" "$OUT/apt-simulate.txt" >/dev/null; then
    ok "cixmini-boot is an upgrade from 1.6+r293"
else
    no "cixmini-boot is not a clean upgrade: $(grep '^Inst cixmini-boot' "$OUT/apt-simulate.txt")"
fi
grep -qE "^Inst linux-(image|headers)-cixmini" "$OUT/apt-simulate.txt" && no "cixmini metas touched" || ok "linux-image-cixmini/linux-headers-cixmini untouched"
dpkg --dry-run -i ./cixmini-boot_*.deb ./linux-headers-"$NEWK"_*.deb ./linux-image-"$NEWK"_*.deb \
    >"$OUT/dpkg-dry-run.txt" 2>&1 && ok "dpkg --dry-run -i accepts the set" || no "dpkg --dry-run -i: $(tail -3 "$OUT/dpkg-dry-run.txt")"

echo "== 3. real install (apt, so the O6N DPkg::Post-Invoke hook fires too)"
apt-get install -y ./cixmini-boot_*.deb ./linux-headers-"$NEWK"_*.deb ./linux-image-"$NEWK"_*.deb \
    >"$OUT/apt-install.log" 2>&1
rc=$?
[ "$rc" = 0 ] && ok "apt-get install exit 0" || { no "apt-get install exit $rc"; tail -40 "$OUT/apt-install.log"; }
snap after

echo "== 4. checks"
# compare every pre-existing file except refind.conf (checked separately)
if diff <(grep -v "EFI/BOOT/refind.conf$" "$OUT/before-sha.txt") \
        <(grep -v "EFI/BOOT/refind.conf$" "$OUT/after-sha.txt" | grep -v -- "-$NEWK\$") >"$OUT/sha-diff.txt"; then
    ok "every 7.3.0 /boot file and every pre-existing ESP file is byte-identical (incl. default initrd)"
else
    no "pre-existing boot/ESP files changed: $(cat "$OUT/sha-diff.txt")"
fi
diff -q "$OUT/before-oldmods-sha.txt" "$OUT/after-oldmods-sha.txt" >/dev/null &&
    ok "/usr/lib/modules/$OLDK unchanged (modules, DKMS builds, build tree)" || no "/usr/lib/modules/$OLDK changed"
CONF=/boot/efi/EFI/BOOT/refind.conf
cp -a "$CONF" "$OUT/refind.conf.after"
n=$(stat -c %s "$OUT/refind.conf.before")
cmp -s -n "$n" "$OUT/refind.conf.before" "$CONF" && ok "refind.conf: original bytes are an exact prefix (append-only)" ||
    no "refind.conf rewritten"
[ "$(grep -c '^menuentry' "$CONF")" = "$(($(grep -c '^menuentry' "$OUT/refind.conf.before") + 1))" ] &&
    ok "refind.conf: exactly one entry added" || no "refind.conf entry count wrong"
[ "$(grep '^default_selection' "$CONF")" = "$(grep '^default_selection' "$OUT/refind.conf.before")" ] &&
    ok "default_selection unchanged ($(grep '^default_selection' "$CONF"))" || no "default_selection changed"
NEWENT=$(sed -n "/kernel $NEWK, ADD-ONLY/,/^}/p" "$CONF")
echo "$NEWENT" >"$OUT/new-entry.txt"
echo "$NEWENT" | grep -qE "loader /vmlinuz-$NEWK" && echo "$NEWENT" | grep -qE "initrd /initrd.img-$NEWK" &&
    ok "new entry loads /vmlinuz-$NEWK + /initrd.img-$NEWK" || no "new entry wrong: $NEWENT"
echo "$NEWENT" | grep -qE "^[[:space:]]*(volume|devicetree)[[:space:]]" && no "new entry has volume/devicetree" ||
    ok "new entry has no volume/devicetree line (boots like the Default)"
DEFOPTS=$(sed -n '/7.3 Mali (Default)"/,/^}/p' "$OUT/refind.conf.before" | sed -n 's/^[[:space:]]*options[[:space:]]*//p')
echo "$NEWENT" | grep -qF "$DEFOPTS" && ok "new entry options == Default entry options" || no "new entry options differ"
cmp -s "/boot/vmlinuz-$NEWK" "/boot/efi/vmlinuz-$NEWK" && cmp -s "/boot/initrd.img-$NEWK" "/boot/efi/initrd.img-$NEWK" &&
    ok "ESP-root vmlinuz/initrd of $NEWK == /boot copies" || no "ESP copies of $NEWK missing or differ"
for m in mali_kbase memory_group_manager protected_memory_allocator amvx aipu panthor; do
    f=$(find "/usr/lib/modules/$NEWK/updates/dkms" -name "$m.ko*" | head -1)
    if [ -n "$f" ] && [ "$(modinfo -F vermagic "$f" | awk '{print $1}')" = "$NEWK" ]; then
        ok "DKMS $m built+installed for $NEWK (vermagic ok)"
    else
        no "DKMS $m missing for $NEWK"
    fi
done
dkms status | tee "$OUT/after-dkms-status.txt"
[ "$(grep -c "$NEWK.*installed" "$OUT/after-dkms-status.txt")" = 4 ] && ok "dkms status: 4 modules installed for $NEWK" ||
    no "dkms status for $NEWK: $(grep "$NEWK" "$OUT/after-dkms-status.txt" | tr '\n' ';')"
[ "$(grep -c "$OLDK.*installed" "$OUT/after-dkms-status.txt")" = 4 ] && ok "dkms status: 4 modules still installed for $OLDK" ||
    no "dkms status for $OLDK changed"
lsinitrd "/boot/initrd.img-$NEWK" >"$OUT/lsinitrd-new.txt" 2>&1 || true
grep -q "mali_kbase" "$OUT/lsinitrd-new.txt" && ok "new initrd contains mali_kbase" || echo "INFO  new initrd has no mali_kbase (dracut module selection)" | tee -a "$OUT/results.txt"
for p in "linux-image-cixmini 7.3.0-sky1-ncz+r293" "linux-headers-cixmini 7.3.0-sky1-ncz+r293"; do
    grep -q "^$p install ok installed" "$OUT/after-dpkg.txt" && ok "$p still installed" || no "$p not installed any more"
done
comm -23 <(awk '{print $1}' "$OUT/before-dpkg.txt") <(awk '{print $1}' "$OUT/after-dpkg.txt") >"$OUT/removed-pkgs.txt"
[ -s "$OUT/removed-pkgs.txt" ] && no "packages removed: $(cat "$OUT/removed-pkgs.txt")" || ok "no package removed by the real install"
cmp -s /usr/local/sbin/ncz-refind-refresh /usr/lib/cixmini/ncz-refind-refresh && ok "/usr/local/sbin/ncz-refind-refresh is the add-only tool" || no "old refresh tool still in place"
cmp -s /usr/local/sbin/.ncz-cixmini-update-bootloader /usr/lib/cixmini/cixmini-update-bootloader &&
    cmp -s /usr/lib/cixmini/cixmini-update-bootloader /usr/local/sbin/.ncz-cixmini-update-bootloader &&
    ok "Post-Invoke restore source is the add-only wrapper" || no "Post-Invoke restore source is not the add-only wrapper"
grep -q "already staged" /var/log/ncz-refind-refresh.log && ok "apt Post-Invoke re-run was a no-op (already staged)" ||
    echo "INFO  no 'already staged' line from the Post-Invoke run" | tee -a "$OUT/results.txt"

echo "== 5. idempotence: another apt run (Post-Invoke fires again) changes nothing"
cp -a "$CONF" "$OUT/refind.conf.after1"
apt-get install -y --reinstall ./cixmini-boot_*.deb >"$OUT/apt-reinstall.log" 2>&1
cmp -s "$OUT/refind.conf.after1" "$CONF" && ok "second apt run: refind.conf unchanged" || no "second apt run changed refind.conf"
/usr/local/sbin/ncz-refind-refresh --list >"$OUT/refresh-list.txt" 2>&1 || true

echo "== 6. the add-only tool accepts the layout (dry-run of the next kernel)"
/usr/local/sbin/ncz-refind-refresh --kver "$NEWK" >"$OUT/refresh-rerun.txt" 2>&1 && grep -q "already staged" "$OUT/refresh-rerun.txt" &&
    ok "ncz-refind-refresh --kver $NEWK: already staged, exit 0" || no "refresh re-run: $(cat "$OUT/refresh-rerun.txt")"

echo "== 7. removal of the new kernel leaves 7.3.0 alone"
apt-get remove -y "linux-image-$NEWK" "linux-headers-$NEWK" >"$OUT/apt-remove.log" 2>&1 && ok "apt remove of $NEWK packages exit 0" || no "apt remove failed"
sha256sum -c --quiet <(grep -E "/boot/(vmlinuz|initrd.img|config)-$OLDK" "$OUT/before-sha.txt") && ok "after removal: 7.3.0 /boot files intact" || no "7.3.0 /boot files changed by removal"
grep -q "^linux-image-cixmini 7.3.0-sky1-ncz+r293 install ok installed" <(dpkg-query -W -f='${Package} ${Version} ${Status}\n') &&
    ok "after removal: linux-image-cixmini 7.3.0 still installed" || no "linux-image-cixmini gone"

echo
echo "RESULT: $PASS passed, $FAIL failed" | tee -a "$OUT/results.txt"
[ "$FAIL" = 0 ]
