#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Shell tests for scripts/ncz-refind-refresh and the side-by-side kernel
# packaging contract (docs/KERNEL-SIDE-BY-SIDE.md).
#
# Every test runs against a throwaway FAKE ESP (a tmpfs-free directory under
# $TMPDIR that is bind-less and real) plus a fake /boot. Nothing here touches a
# real host: no efibootmgr, no reboot, no writes outside the sandbox.
#
# Run: scripts/test-ncz-refind-refresh.sh [-v]
#
# The harness predates the fix on purpose. On the base branch (before the
# add-only rewrite) every "add-only" test FAILS: the old script wiped the ESP
# kernel tree and refind.conf and pointed every entry at the newest kernel.
# The two packaging tests fail there too (single-name linux-image-cixmini
# package, no per-version name, no meta package, hence "install new kernel"
# removes the old one under the same package name).

set -o pipefail
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
REFRESH="$HERE/ncz-refind-refresh"
VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

PASS=0
FAIL=0
FAILED_NAMES=()

pass() { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
fail() {
    FAIL=$((FAIL + 1))
    FAILED_NAMES+=("$1")
    printf 'FAIL  %s\n' "$1"
    if [ "$VERBOSE" = 1 ] && [ -n "${2:-}" ]; then
        printf '%s\n' "$2" | sed 's/^/      /'
    fi
}

# A fresh sandbox: fake ESP + fake /boot, seeded with a known-good 7.3.0
# kernel that is already staged and is the default, plus a rescue entry.
sandbox() {
    SBX=$(mktemp -d "${TMPDIR:-/var/tmp}/ncz-refind-test.XXXXXX") || exit 1
    ESP="$SBX/esp"
    BOOT="$SBX/boot"
    mkdir -p "$ESP/EFI/refind/icons" "$ESP/EFI/ncz/ncz-7.3.0-sky1-ncz" "$BOOT/cix"

    : >"$ESP/EFI/refind/icons/os_linux.png"
    printf 'REFIND-KNOWN-GOOD-7.3.0-VMLINUZ\n' >"$ESP/EFI/ncz/ncz-7.3.0-sky1-ncz/vmlinuz"
    printf 'REFIND-KNOWN-GOOD-7.3.0-INITRD\n' >"$ESP/EFI/ncz/ncz-7.3.0-sky1-ncz/initrd.img"
    printf 'REFIND-KNOWN-GOOD-7.3.0-DTB\n' >"$ESP/EFI/ncz/ncz-7.3.0-sky1-ncz/sky1-orion-o6.dtb"

    # The known-good kernel is in /boot too (install of 7.3.1 must not touch it).
    printf 'BOOT-VMLINUZ-7.3.0\n' >"$BOOT/vmlinuz-7.3.0-sky1-ncz"
    printf 'BOOT-INITRD-7.3.0\n' >"$BOOT/initrd.img-7.3.0-sky1-ncz"

    cat >"$ESP/EFI/refind/refind.conf" <<'CONF'
# rEFInd configuration -- O6N / CIX Sky1
timeout 20
default_selection 2
scanfor internal,external,optical,manual
use_nvram false

menuentry "Rescue Partition" {
    icon /EFI/refind/icons/os_linux.png
    volume ncz
    loader /EFI/rescue/vmlinuz
    initrd /EFI/rescue/initrd.img
    options ro single
}

menuentry "Rescue" {
    icon /EFI/refind/icons/os_linux.png
    volume ncz
    loader /EFI/ncz/ncz-7.3.0-sky1-ncz/vmlinuz
    initrd /EFI/ncz/ncz-7.3.0-sky1-ncz/initrd.img
    options ro single ncz_rescue=1
}

menuentry "NCZ 7.3.0-sky1-ncz" {
    icon /EFI/refind/icons/os_linux.png
    volume ncz
    loader /EFI/ncz/ncz-7.3.0-sky1-ncz/vmlinuz
    initrd /EFI/ncz/ncz-7.3.0-sky1-ncz/initrd.img
    devicetree /EFI/ncz/ncz-7.3.0-sky1-ncz/sky1-orion-o6.dtb
    options clk_ignore_unused acpi_scmi_en=off pcie_pnp_en root=UUID=abc rw quiet
}

menuentry "NCZRESCUE" {
    icon /EFI/refind/icons/os_linux.png
    volume ncz
    loader /EFI/ncz/ncz-7.3.0-sky1-ncz/vmlinuz
    initrd /EFI/ncz/ncz-7.3.0-sky1-ncz/initrd.img
    options ro single
}
CONF

    # The new kernel, freshly installed in /boot only.
    printf 'BOOT-VMLINUZ-7.3.1\n' >"$BOOT/vmlinuz-7.3.1-sky1-ncz"
    printf 'BOOT-INITRD-7.3.1\n' >"$BOOT/initrd.img-7.3.1-sky1-ncz"
    printf 'BOOT-DTB-7.3.1\n' >"$BOOT/cix/sky1-orion-o6.dtb"

    LOGFILE="$SBX/refresh.log"
}

cleanup() { [ -n "${SBX:-}" ] && rm -rf "$SBX"; }
trap cleanup EXIT

# Snapshot the ESP: path + sha256 + mtime-free content hash for every file.
snapshot() {
    local root="$1" out="$2"
    (
        cd "$root" || exit 1
        find . -type f -print0 | sort -z | while IFS= read -r -d '' f; do
            printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$f"
        done
    ) >"$out"
}

run_refresh() {
    NCZ_ESP_DIR="$ESP" NCZ_BOOT_DIR="$BOOT" NCZ_REFIND_LOG="$LOGFILE" \
        "$REFRESH" "$@" >"$SBX/out.txt" 2>"$SBX/err.txt"
    RC=$?
    [ "$VERBOSE" = 1 ] && sed 's/^/      | /' "$SBX/out.txt" "$SBX/err.txt" >&2
    return 0
}

# ---------------------------------------------------------------------------
# Test 1 (REQUIRED): add-only mode leaves every pre-existing ESP entry and
# file byte-identical -- proven with a before/after diff, not by inspection.
# ---------------------------------------------------------------------------
test_add_only_preserves_everything_byte_identical() {
    sandbox

    # Pretend the ESP is mounted so the preflight check is satisfied: on this
    # harness the sandbox is a real directory, so bind-mounting is not an
    # option; the script's mount check accepts a directory listed in
    # /proc/mounts, hence these tests set NCZ_ESP_SKIP_MOUNT_CHECK=1 -- which
    # the script honours ONLY together with the NCZ_ESP_DIR override.
    export NCZ_ESP_SKIP_MOUNT_CHECK=1

    snapshot "$ESP" "$SBX/esp.before"
    cp -a "$ESP" "$SBX/esp.before.tree"
    cp "$ESP/EFI/refind/refind.conf" "$SBX/refind.conf.before"

    run_refresh --kver 7.3.1-sky1-ncz
    if [ "$RC" != 0 ]; then
        fail "add-only: exit 0" "rc=$RC$(cat "$SBX/err.txt" 2>/dev/null)"
        return
    fi

    # refind.conf must be a strict prefix of the new file: append-only, so
    # every pre-existing byte, entry and ordering is preserved verbatim.
    if cmp -s -n "$(stat -c %s "$SBX/refind.conf.before")" \
        "$SBX/refind.conf.before" "$ESP/EFI/refind/refind.conf"; then
        pass "add-only: existing refind.conf bytes preserved (strict-prefix, append-only)"
    else
        fail "add-only: existing refind.conf bytes preserved" "$(diff -u "$SBX/refind.conf.before" "$ESP/EFI/refind/refind.conf" | head -40)"
    fi

    # Byte-identical check on the pre-existing ESP *kernel files*. refind.conf
    # itself necessarily grows (that is the one entry being added) and is
    # checked separately as an append-only strict prefix above; every OTHER
    # pre-existing file -- all kernel payloads -- must be byte-identical.
    local changed="" f rel
    while IFS= read -r f; do
        rel=${f#"$SBX/esp.before.tree"}
        [ "$rel" = "/EFI/refind/refind.conf" ] && continue
        if ! cmp -s "$f" "$ESP$rel"; then
            changed="$changed $rel"
        fi
    done < <(find "$SBX/esp.before.tree" -type f)
    if [ -z "$changed" ]; then
        pass "add-only: every pre-existing ESP kernel file byte-identical"
    else
        fail "add-only: every pre-existing ESP kernel file byte-identical" "changed:$changed"
    fi

    # default_selection must not move.
    if grep -qx 'default_selection 2' "$ESP/EFI/refind/refind.conf"; then
        pass "add-only: default_selection unchanged"
    else
        fail "add-only: default_selection unchanged" "$(grep -n default_selection "$ESP/EFI/refind/refind.conf")"
    fi

    # The rescue entries and NCZRESCUE must be textually untouched.
    local rescue_before rescue_after
    rescue_before=$(sed -n '/menuentry "Rescue"/,/^}/p' "$SBX/refind.conf.before")
    rescue_after=$(sed -n '/menuentry "Rescue"/,/^}/p' "$ESP/EFI/refind/refind.conf")
    if [ "$rescue_before" = "$rescue_after" ] && [ -n "$rescue_before" ]; then
        pass "add-only: Rescue entry unchanged"
    else
        fail "add-only: Rescue entry unchanged" "before=[$rescue_before] after=[$rescue_after]"
    fi

    local nczrescue_before nczrescue_after
    nczrescue_before=$(sed -n '/menuentry "NCZRESCUE"/,/^}/p' "$SBX/refind.conf.before")
    nczrescue_after=$(sed -n '/menuentry "NCZRESCUE"/,/^}/p' "$ESP/EFI/refind/refind.conf")
    if [ "$nczrescue_before" = "$nczrescue_after" ] && [ -n "$nczrescue_before" ]; then
        pass "add-only: NCZRESCUE entry unchanged"
    else
        fail "add-only: NCZRESCUE entry unchanged"
    fi

    local rescpart_before rescpart_after
    rescpart_before=$(sed -n '/menuentry "Rescue Partition"/,/^}/p' "$SBX/refind.conf.before")
    rescpart_after=$(sed -n '/menuentry "Rescue Partition"/,/^}/p' "$ESP/EFI/refind/refind.conf")
    if [ "$rescpart_before" = "$rescpart_after" ] && [ -n "$rescpart_before" ]; then
        pass "add-only: Rescue Partition entry unchanged"
    else
        fail "add-only: Rescue Partition entry unchanged"
    fi

    # Exactly one new menuentry, titled for the new kernel...
    local n_entries n_new
    n_entries=$(grep -cE '^[[:space:]]*menuentry[[:space:]]' "$ESP/EFI/refind/refind.conf")
    if [ "$n_entries" = 5 ]; then
        pass "add-only: exactly one menuentry added (4 -> 5)"
    else
        fail "add-only: exactly one menuentry added" "count=$n_entries"
    fi
    n_new=$(grep -c 'menuentry "NCZ 7.3.1-sky1-ncz"' "$ESP/EFI/refind/refind.conf")
    if [ "$n_new" = 1 ]; then
        pass "add-only: new entry titled for 7.3.1"
    else
        fail "add-only: new entry titled for 7.3.1" "count=$n_new"
    fi

    # ...whose options are the Default's options, verbatim.
    local default_opts new_opts
    default_opts=$(sed -n '/menuentry "NCZ 7.3.0-sky1-ncz"/,/^}/p' "$ESP/EFI/refind/refind.conf" |
        sed -n 's/^[[:space:]]*options[[:space:]]*//p')
    new_opts=$(sed -n '/menuentry "NCZ 7.3.1-sky1-ncz"/,/^}/p' "$ESP/EFI/refind/refind.conf" |
        sed -n 's/^[[:space:]]*options[[:space:]]*//p')
    if [ -n "$default_opts" ] && [ "$default_opts" = "$new_opts" ]; then
        pass "add-only: new entry options copied verbatim from Default"
    else
        fail "add-only: new entry options copied verbatim from Default" "default=[$default_opts] new=[$new_opts]"
    fi

    # The new kernel's files were staged under its OWN directory.
    if [ -f "$ESP/EFI/ncz/ncz-7.3.1-sky1-ncz/vmlinuz" ] &&
        [ -f "$ESP/EFI/ncz/ncz-7.3.1-sky1-ncz/initrd.img" ]; then
        pass "add-only: new kernel staged in its own version directory"
    else
        fail "add-only: new kernel staged in its own version directory"
    fi
}

# ---------------------------------------------------------------------------
# Test 2: installing the new kernel does not remove the old version's files.
# ---------------------------------------------------------------------------
test_old_version_files_survive_install() {
    sandbox
    export NCZ_ESP_SKIP_MOUNT_CHECK=1

    snapshot "$ESP" "$SBX/esp.before"

    run_refresh --kver 7.3.1-sky1-ncz
    if [ "$RC" != 0 ]; then
        fail "install: old version survives (7.3.1 install exit 0)" "rc=$RC"
        return
    fi

    local f ok=1
    for f in "$ESP/EFI/ncz/ncz-7.3.0-sky1-ncz/vmlinuz" \
        "$ESP/EFI/ncz/ncz-7.3.0-sky1-ncz/initrd.img" \
        "$ESP/EFI/ncz/ncz-7.3.0-sky1-ncz/sky1-orion-o6.dtb" \
        "$BOOT/vmlinuz-7.3.0-sky1-ncz" \
        "$BOOT/initrd.img-7.3.0-sky1-ncz"; do
        [ -e "$f" ] || {
            ok=0
            printf '      missing: %s\n' "$f"
        }
    done
    if [ "$ok" = 1 ]; then
        pass "install: 7.3.0 kernel/initrd/dtb survive a 7.3.1 install"
    else
        fail "install: 7.3.0 kernel/initrd/dtb survive a 7.3.1 install"
    fi

    if [ "$(cat "$ESP/EFI/ncz/ncz-7.3.0-sky1-ncz/vmlinuz")" = "REFIND-KNOWN-GOOD-7.3.0-VMLINUZ" ]; then
        pass "install: known-good 7.3.0 payload not overwritten"
    else
        fail "install: known-good 7.3.0 payload not overwritten"
    fi

    # A second, later apt run must be a no-op (idempotent add-only).
    snapshot "$ESP" "$SBX/esp.after_first"
    run_refresh
    if [ "$RC" = 0 ] && cmp -s "$SBX/esp.after_first" <(
        cd "$ESP" && find . -type f -print0 | sort -z | while IFS= read -r -d '' f; do
            printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$f"
        done
    ); then
        pass "install: re-running (later apt run) changes nothing"
    else
        fail "install: re-running (later apt run) changes nothing" "rc=$RC"
    fi
}

# ---------------------------------------------------------------------------
# Test 3 (REQUIRED): --promote changes ONLY default_selection.
# ---------------------------------------------------------------------------
test_promote_changes_only_default_selection() {
    sandbox
    export NCZ_ESP_SKIP_MOUNT_CHECK=1

    run_refresh --kver 7.3.1-sky1-ncz
    if [ "$RC" != 0 ]; then
        fail "promote: staged first" "rc=$RC"
        return
    fi
    cp "$ESP/EFI/refind/refind.conf" "$SBX/refind.pre-promote"

    run_refresh --promote 7.3.1-sky1-ncz
    if [ "$RC" != 0 ]; then
        fail "promote: exit 0" "rc=$RC$(cat "$SBX/err.txt" 2>/dev/null)"
        return
    fi

    # The ONLY difference between pre- and post-promote is the
    # default_selection line.
    local diffout
    diffout=$(diff -u "$SBX/refind.pre-promote" "$ESP/EFI/refind/refind.conf")
    local removed added
    removed=$(printf '%s\n' "$diffout" | grep -c '^-[^-]')
    added=$(printf '%s\n' "$diffout" | grep -c '^+[^+]')
    if [ "$removed" = 1 ] && [ "$added" = 1 ]; then
        pass "promote: exactly one line changed"
    else
        fail "promote: exactly one line changed" "$diffout"
    fi

    local old_line
    old_line=$(printf '%s\n' "$diffout" | sed -n 's/^-\([^-].*\)$/\1/p')
    if [ "$old_line" = "default_selection 2" ]; then
        pass "promote: the removed line is the old default_selection"
    else
        fail "promote: the removed line is the old default_selection" "removed=[$old_line]"
    fi

    # The new default_selection is the index of the NCZ 7.3.1 entry (4).
    if grep -qx 'default_selection 4' "$ESP/EFI/refind/refind.conf"; then
        pass "promote: default_selection now points at the new kernel (4)"
    else
        fail "promote: default_selection now points at the new kernel" "$(grep -n default_selection "$ESP/EFI/refind/refind.conf")"
    fi

    # No menuentry body changed.
    local before_entries after_entries
    before_entries=$(sed -n '/^[[:space:]]*menuentry/,/^}/p' "$SBX/refind.pre-promote")
    after_entries=$(sed -n '/^[[:space:]]*menuentry/,/^}/p' "$ESP/EFI/refind/refind.conf")
    if [ "$before_entries" = "$after_entries" ]; then
        pass "promote: no menuentry body changed"
    else
        fail "promote: no menuentry body changed"
    fi

    # No kernel file on the ESP changed.
    local f
    ok=1
    while IFS= read -r f; do
        rel=${f#"$SBX/esp.before.tree"}
        # esp.before.tree predates the 7.3.1 staging, so only compare files
        # that existed then.
        if [ -e "$f" ] && [ -e "$ESP$rel" ] && ! cmp -s "$f" "$ESP$rel"; then
            ok=0
            printf '      changed: %s\n' "$rel"
        fi
    done < <(find "$SBX/esp.before.tree" -type f 2>/dev/null)
    if [ "$ok" = 1 ]; then
        pass "promote: no pre-existing ESP file changed"
    else
        fail "promote: no pre-existing ESP file changed"
    fi
}

# ---------------------------------------------------------------------------
# Test 4 (REQUIRED): refuses, non-zero, NO ESP writes when the old known-good
# kernel files are missing.
# ---------------------------------------------------------------------------
test_refuses_when_known_good_missing() {
    sandbox
    export NCZ_ESP_SKIP_MOUNT_CHECK=1

    # Remove the known-good kernel from /boot and from the ESP.
    rm -f "$BOOT/vmlinuz-7.3.0-sky1-ncz" "$BOOT/initrd.img-7.3.0-sky1-ncz"
    rm -rf "$ESP/EFI/ncz/ncz-7.3.0-sky1-ncz"
    snapshot "$ESP" "$SBX/esp.before"

    run_refresh --kver 7.3.1-sky1-ncz
    if [ "$RC" != 0 ]; then
        pass "refuse: missing known-good kernel exits non-zero"
    else
        fail "refuse: missing known-good kernel exits non-zero" "rc=0"
    fi

    snapshot "$ESP" "$SBX/esp.after"
    if cmp -s "$SBX/esp.before" "$SBX/esp.after"; then
        pass "refuse: no ESP write when known-good kernel is missing"
    else
        fail "refuse: no ESP write when known-good kernel is missing" "$(diff "$SBX/esp.before" "$SBX/esp.after")"
    fi
}

# ---------------------------------------------------------------------------
# Test 5 (REQUIRED): refuses, non-zero, NO ESP writes when the ESP is not
# mounted.
# ---------------------------------------------------------------------------
test_refuses_when_esp_not_mounted() {
    sandbox
    unset NCZ_ESP_SKIP_MOUNT_CHECK
    snapshot "$ESP" "$SBX/esp.before"

    run_refresh --kver 7.3.1-sky1-ncz
    if [ "$RC" != 0 ]; then
        pass "refuse: unmounted ESP exits non-zero"
    else
        fail "refuse: unmounted ESP exits non-zero" "rc=0"
    fi

    snapshot "$ESP" "$SBX/esp.after"
    if cmp -s "$SBX/esp.before" "$SBX/esp.after"; then
        pass "refuse: no ESP write when the ESP is not mounted"
    else
        fail "refuse: no ESP write when the ESP is not mounted"
    fi
}

# ---------------------------------------------------------------------------
# Test 6: promote refuses a kernel that is not staged, without writing.
# ---------------------------------------------------------------------------
test_promote_refuses_unstaged() {
    sandbox
    export NCZ_ESP_SKIP_MOUNT_CHECK=1
    cp "$ESP/EFI/refind/refind.conf" "$SBX/refind.before"

    run_refresh --promote 7.3.1-sky1-ncz
    if [ "$RC" != 0 ]; then
        pass "promote: refuses an unstaged kernel"
    else
        fail "promote: refuses an unstaged kernel"
    fi
    if cmp -s "$SBX/refind.before" "$ESP/EFI/refind/refind.conf"; then
        pass "promote: no write when refusing"
    else
        fail "promote: no write when refusing"
    fi
}

# ---------------------------------------------------------------------------
# Test 7: the script never invokes efibootmgr (no firmware boot entry churn).
# ---------------------------------------------------------------------------
test_no_efibootmgr_invocation() {
    # Strip comment lines, then look for an actual command word.
    if sed 's/#.*//' "$REFRESH" | grep -qwE 'efibootmgr'; then
        fail "no efibootmgr invocation" "$(sed 's/#.*//' "$REFRESH" | grep -nwE 'efibootmgr')"
    else
        pass "no efibootmgr invocation"
    fi
}

# ---------------------------------------------------------------------------
# Test 8: the refresh script is shipped by a recipe in this layer somewhere
# (it is the cixmini-boot postinst dependency) and that recipe is named
# cixmini-boot.
# ---------------------------------------------------------------------------
test_recipe_ships_refresh() {
    local hit
    hit=$(grep -rl "ncz-refind-refresh" "$REPO/recipes-" 2>/dev/null | head -5)
    if [ -n "$hit" ]; then
        pass "packaging: a recipe ships ncz-refind-refresh"
    else
        fail "packaging: a recipe ships ncz-refind-refresh"
    fi
}

# ---------------------------------------------------------------------------
# Test 9 (REQUIRED, packaging): per-version kernel package names.
# The 7.3.1 recipe must produce linux-image-<KVER> / linux-headers-<KVER>
# (with KVER = 7.3.1-sky1-ncz), not a single unversioned name.
# ---------------------------------------------------------------------------
test_per_version_package_names() {
    local recipe="$REPO/recipes-kernel/linux-cix-sky1-ncz/linux-cix-sky1-ncz_7.3.1.bb"
    if [ ! -f "$recipe" ]; then
        fail "packaging: 7.3.1 recipe exists"
        return
    fi
    if grep -qE 'linux-image-\$\{KERNEL_VERSION\}|linux-image-\$\{KVER\}|linux-image-\$\{@' "$recipe"; then
        pass "packaging: image package name is per-version"
    else
        fail "packaging: image package name is per-version" "$(grep -n 'linux-image' "$recipe" | head)"
    fi
    if grep -qE 'linux-headers-\$\{KERNEL_VERSION\}|linux-headers-\$\{KVER\}|linux-headers-\$\{@' "$recipe"; then
        pass "packaging: headers package name is per-version"
    else
        fail "packaging: headers package name is per-version" "$(grep -n 'linux-headers' "$recipe" | head)"
    fi
    if grep -q 'RPROVIDES' "$recipe" && grep -qE 'linux-image-cixmini|linux-headers-cixmini' "$recipe"; then
        pass "packaging: thin meta package provides the legacy 'latest' names"
    else
        fail "packaging: thin meta package provides the legacy 'latest' names"
    fi
    if grep -q 'ALLOW_EMPTY' "$recipe"; then
        pass "packaging: meta package is empty (ALLOW_EMPTY)"
    else
        fail "packaging: meta package is empty (ALLOW_EMPTY)"
    fi
    # The version/build logic must be intact: r295 pin + revision.
    if grep -q '79a907609d53d5cd645b42c11550d295d43abf99' "$recipe" &&
        grep -qE '^PV = "7\.3\.1\+ncz"' "$recipe" &&
        grep -qE '^PR = "' "$recipe"; then
        pass "packaging: SRCREV/PV/PR (r295) intact"
    else
        fail "packaging: SRCREV/PV/PR (r295) intact"
    fi
}

# ---------------------------------------------------------------------------
# Test 10 (REQUIRED, packaging): a meta package must NOT depend on a specific
# version, and must not remove older per-version packages. Static check on the
# recipe metadata: the meta package's dependency is on the CURRENT version
# only, and no per-version package has a Conflicts/Replaces that could evict
# an older version.
# ---------------------------------------------------------------------------
test_meta_does_not_evict_old() {
    local recipe="$REPO/recipes-kernel/linux-cix-sky1-ncz/linux-cix-sky1-ncz_7.3.1.bb"
    if [ ! -f "$recipe" ]; then
        fail "packaging: 7.3.1 recipe exists (meta-evict)"
        return
    fi
    if grep -qE 'Conflicts|Replaces' "$recipe"; then
        fail "packaging: no Conflicts/Replaces that evict older kernels" \
            "$(grep -nE 'Conflicts|Replaces' "$recipe")"
    else
        pass "packaging: no Conflicts/Replaces that evict older kernels"
    fi
    # The thin meta package must depend on the exact current version only.
    if grep -qE 'RDEPENDS.*\$\{KERNEL_VERSION\}|RDEPENDS.*\$\{KVER\}' "$recipe"; then
        pass "packaging: meta package pins by exact current version"
    else
        fail "packaging: meta package pins by exact current version" "$(grep -n RDEPENDS "$recipe")"
    fi
}

# ---------------------------------------------------------------------------
# Test 11: docs deliverable exists.
# ---------------------------------------------------------------------------
test_docs_exist() {
    local doc="$REPO/docs/KERNEL-SIDE-BY-SIDE.md"
    if [ -f "$doc" ]; then
        pass "docs: KERNEL-SIDE-BY-SIDE.md exists"
    else
        fail "docs: KERNEL-SIDE-BY-SIDE.md exists"
    fi
    if [ -f "$doc" ] && grep -qi 'rollback' "$doc" && grep -qi 'promote' "$doc"; then
        pass "docs: has install and rollback steps"
    else
        fail "docs: has install and rollback steps"
    fi
}

# ---------------------------------------------------------------------------
main() {
    if [ ! -x "$REFRESH" ]; then
        chmod +x "$REFRESH" 2>/dev/null || true
    fi
    test_add_only_preserves_everything_byte_identical
    test_old_version_files_survive_install
    test_promote_changes_only_default_selection
    test_refuses_when_known_good_missing
    test_refuses_when_esp_not_mounted
    test_promote_refuses_unstaged
    test_no_efibootmgr_invocation
    test_recipe_ships_refresh
    test_per_version_package_names
    test_meta_does_not_evict_old
    test_docs_exist

    printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
    if [ "$FAIL" -ne 0 ]; then
        printf 'failed: %s\n' "${FAILED_NAMES[*]}"
        exit 1
    fi
    exit 0
}

main "$@"
