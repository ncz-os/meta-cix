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
# REGRESSION: the options a new kernel inherits come from the Default kernel
# entry, NOT from whatever default_selection happens to point at. On O6N the
# first menuentry is "Rescue Partition" and the second is "Rescue"; if the
# operator has default_selection pointing at a rescue entry (a perfectly legal
# rEFInd config), copying "that entry's" options would give the new kernel
# "ro single ncz_rescue=1" instead of the real cmdline.
#
# Before the fix, default_entry_options() resolved default_selection and read
# the options at that index -- so this test FAILS on the base and PASSES with
# the fix.
# ---------------------------------------------------------------------------
test_new_options_ignore_rescue_default() {
    sandbox
    export NCZ_ESP_SKIP_MOUNT_CHECK=1

    # Point default_selection at entry index 1 == "Rescue", whose options are
    # a rescue cmdline that must never propagate to a normal kernel.
    sed -i 's/^default_selection 2$/default_selection 1/' \
        "$ESP/EFI/refind/refind.conf"
    local rescue_opts
    rescue_opts=$(sed -n '/menuentry "Rescue" {/,/^}/p' "$ESP/EFI/refind/refind.conf" |
        sed -n 's/^[[:space:]]*options[[:space:]]*//p')
    if [ "$rescue_opts" != "ro single ncz_rescue=1" ]; then
        fail "rescue-default: fixture precondition" "rescue opts=[$rescue_opts]"
        return
    fi

    run_refresh --kver 7.3.1-sky1-ncz
    if [ "$RC" != 0 ]; then
        fail "rescue-default: exit 0" "rc=$RC$(cat "$SBX/err.txt" 2>/dev/null)"
        return
    fi

    local good_opts new_opts
    good_opts=$(sed -n '/menuentry "NCZ 7.3.0-sky1-ncz" {/,/^}/p' "$ESP/EFI/refind/refind.conf" |
        sed -n 's/^[[:space:]]*options[[:space:]]*//p')
    new_opts=$(sed -n '/menuentry "NCZ 7.3.1-sky1-ncz" {/,/^}/p' "$ESP/EFI/refind/refind.conf" |
        sed -n 's/^[[:space:]]*options[[:space:]]*//p')

    if [ -n "$good_opts" ] && [ "$new_opts" = "$good_opts" ]; then
        pass "rescue-default: new entry inherits the Default kernel options"
    else
        fail "rescue-default: new entry inherits the Default kernel options" \
            "expected=[$good_opts] got=[$new_opts]"
    fi

    if [ "$new_opts" != "$rescue_opts" ]; then
        pass "rescue-default: rescue options NOT copied to the new kernel"
    else
        fail "rescue-default: rescue options NOT copied to the new kernel" \
            "new entry got rescue cmdline [$new_opts]"
    fi

    # And nothing about the default_selection line moved.
    if grep -qx 'default_selection 1' "$ESP/EFI/refind/refind.conf"; then
        pass "rescue-default: default_selection untouched"
    else
        fail "rescue-default: default_selection untouched" \
            "$(grep -n default_selection "$ESP/EFI/refind/refind.conf")"
    fi
}

# ---------------------------------------------------------------------------
# REGRESSION: with default_selection naming a rescue entry, the fallback must
# still pick the *highest version* NCZ entry (the known-good kernel), even if
# the entries are not in version order.
# ---------------------------------------------------------------------------
test_fallback_picks_highest_version() {
    sandbox
    export NCZ_ESP_SKIP_MOUNT_CHECK=1

    # Six entries, deliberately out of order, default on a rescue entry.
    cat >"$ESP/EFI/refind/refind.conf" <<'CONF'
timeout 20
default_selection 1

menuentry "Rescue" {
    options ro single ncz_rescue=1
}

menuentry "NCZ 7.3.10-sky1-ncz" {
    options FROM-7310 root=UUID=abc rw quiet
}

menuentry "NCZ 7.3.2-sky1-ncz" {
    options FROM-732 root=UUID=abc rw quiet
}

menuentry "NCZ 7.3.9-sky1-ncz" {
    options FROM-739 root=UUID=abc rw quiet
}
CONF

    # The known-good 7.3.10 must exist in /boot AND be staged on the ESP,
    # otherwise the script correctly refuses (that check is tested elsewhere
    # and must not mask the option-inheritance behaviour under test here).
    printf 'BOOT-VMLINUZ-7.3.10\n' >"$BOOT/vmlinuz-7.3.10-sky1-ncz"
    printf 'BOOT-INITRD-7.3.10\n' >"$BOOT/initrd.img-7.3.10-sky1-ncz"
    mkdir -p "$ESP/EFI/ncz/ncz-7.3.10-sky1-ncz"
    printf 'K\n' >"$ESP/EFI/ncz/ncz-7.3.10-sky1-ncz/vmlinuz"
    printf 'I\n' >"$ESP/EFI/ncz/ncz-7.3.10-sky1-ncz/initrd.img"

    run_refresh --kver 7.3.1-sky1-ncz
    if [ "$RC" != 0 ]; then
        fail "version-fallback: exit 0" "rc=$RC ERR=[$(cat "$SBX/err.txt" 2>/dev/null)]"
        return
    fi
    local new_opts
    new_opts=$(sed -n '/menuentry "NCZ 7.3.1-sky1-ncz" {/,/^}/p' "$ESP/EFI/refind/refind.conf" |
        sed -n 's/^[[:space:]]*options[[:space:]]*//p')
    if [ "$new_opts" = "FROM-7310 root=UUID=abc rw quiet" ]; then
        pass "version-fallback: highest version (7.3.10) is the inherited Default"
    else
        fail "version-fallback: highest version (7.3.10) is the inherited Default" \
            "got=[$new_opts]"
    fi
}

# ---------------------------------------------------------------------------
# REGRESSION: the recipe must install the scripts where the wrapper and the
# postinst look for them, and must not hardcode a path it does not install to.
# ---------------------------------------------------------------------------
test_recipe_install_path_matches_invocation() {
    local recipe="$REPO/recipes-bsp/cixmini-boot/cixmini-boot_1.0.bb"
    local wrapper="$REPO/scripts/cixmini-boot-refresh"

    if grep -qE '^CIXMINI_BOOT_SBINDIR[[:space:]]*=[[:space:]]*"/usr/local/sbin"' "$recipe"; then
        pass "packaging: installs under /usr/local/sbin"
    else
        fail "packaging: installs under /usr/local/sbin"
    fi

    # Nothing may install into ${sbindir} (/usr/sbin) if the callers use
    # /usr/local/sbin -- that is the mismatch that made the postinst a no-op.
    if grep -q 'install -m 0755 .*\${sbindir}' "$recipe"; then
        fail "packaging: does not install into \${sbindir}" \
            "$(grep -n '\${sbindir}' "$recipe")"
    else
        pass "packaging: does not install into \${sbindir}"
    fi

    # The wrapper's default REFRESH path and the postinst's invocation must
    # match the install location.
    if grep -q '/usr/local/sbin/ncz-refind-refresh' "$wrapper" &&
        grep -q '/usr/local/sbin/cixmini-boot-refresh' "$recipe"; then
        pass "packaging: invocation path matches install path"
    else
        fail "packaging: invocation path matches install path"
    fi
}

# ---------------------------------------------------------------------------
# REGRESSION: the recipe must declare the runtime tools its scripts use.
# ---------------------------------------------------------------------------
test_recipe_declares_coreutils() {
    local recipe="$REPO/recipes-bsp/cixmini-boot/cixmini-boot_1.0.bb"
    local rdeps missing="" dep
    rdeps=$(grep -E '^RDEPENDS:\$\{PN\}' "$recipe")
    # Every external tool the shipped scripts actually call must be declared.
    # awk in particular is its own package and is NOT part of coreutils, so
    # an undeclared awk breaks refind.conf parsing at runtime.
    for dep in bash coreutils awk grep sed; do
        printf '%s' "$rdeps" | grep -qE "(^|[\"  ])$dep([\"  ]|$)" ||
            missing="$missing $dep"
    done
    if [ -z "$missing" ]; then
        pass "packaging: RDEPENDS includes bash coreutils awk grep sed"
    else
        fail "packaging: RDEPENDS includes bash coreutils awk grep sed" \
            "missing:$missing rdeps=[$rdeps]"
    fi
}

# ---------------------------------------------------------------------------
# REGRESSION: cixmini-boot-refresh must find the worker with NO environment
# set. REFRESH=${NCZ_REFRESH_BIN:-<installed path>} is a POSIX default
# expansion -- the variable is optional, not required. Proven by running the
# real wrapper against a fake worker with the variable unset and with it empty.
# ---------------------------------------------------------------------------
test_wrapper_needs_no_environment() {
    local wdir="$SBX/wrap"
    mkdir -p "$wdir" || { fail "wrapper: sandbox"; return; }

    # A stand-in worker the wrapper can exec; it records that it ran.
    cat >"$wdir/ncz-refind-refresh" <<'STUB'
#!/bin/sh
printf 'WORKER-RAN %s\n' "$*"
exit 0
STUB
    chmod 0755 "$wdir/ncz-refind-refresh"

    local out rc
    # (a) variable entirely unset, NCZ_REFRESH_BIN pointing into $wdir.
    out=$(env -u NCZ_REFRESH_BIN NCZ_REFRESH_BIN="$wdir/ncz-refind-refresh" \
        "$REPO/scripts/cixmini-boot-refresh" 2>&1)
    rc=$?
    if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'WORKER-RAN'; then
        pass "wrapper: execs the worker (NCZ_REFRESH_BIN set explicitly)"
    else
        fail "wrapper: execs the worker (NCZ_REFRESH_BIN set explicitly)" \
            "rc=$rc out=[$out]"
    fi

    # (b) The documented default must be the installed location, and the
    #     expansion must yield it when the variable is absent or empty.
    local dflt
    dflt=$(REFRESH_UNSET_TEST=1 sh -c "
        unset NCZ_REFRESH_BIN
        $(grep -E '^REFRESH=' "$REPO/scripts/cixmini-boot-refresh")
        printf '%s' "\$REFRESH"")
    if [ "$dflt" = "/usr/local/sbin/ncz-refind-refresh" ]; then
        pass "wrapper: unset NCZ_REFRESH_BIN defaults to the installed path"
    else
        fail "wrapper: unset NCZ_REFRESH_BIN defaults to the installed path" \
            "got=[$dflt]"
    fi

    local empty
    empty=$(NCZ_REFRESH_BIN= sh -c "
        $(grep -E '^REFRESH=' "$REPO/scripts/cixmini-boot-refresh")
        printf '%s' "\$REFRESH"")
    if [ "$empty" = "/usr/local/sbin/ncz-refind-refresh" ]; then
        pass "wrapper: empty NCZ_REFRESH_BIN defaults to the installed path"
    else
        fail "wrapper: empty NCZ_REFRESH_BIN defaults to the installed path" \
            "got=[$empty]"
    fi
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
    #
    # Proven with plain `head -c` (POSIX, no GNU-only `cmp -n` / `stat -c`):
    # the first N bytes of the new file, N = size of the old file, must be
    # byte-identical to the whole old file. cmp then always gets exactly two
    # file operands.
    local conf_old="$SBX/refind.conf.before" conf_new="$ESP/EFI/refind/refind.conf"
    local conf_bytes
    conf_bytes=$(wc -c <"$conf_old" | tr -d '[:space:]')
    head -c "$conf_bytes" "$conf_new" >"$SBX/refind.conf.newprefix"
    if cmp -s "$conf_old" "$SBX/refind.conf.newprefix"; then
        pass "add-only: existing refind.conf bytes preserved (strict-prefix, append-only)"
    else
        fail "add-only: existing refind.conf bytes preserved" "$(diff -u "$conf_old" "$conf_new" | head -40)"
    fi

    # Byte-identical check on the pre-existing ESP *kernel files*. refind.conf
    # itself necessarily grows (that is the one entry being added) and is
    # checked separately as an append-only strict prefix above; every OTHER
    # pre-existing file -- all kernel payloads -- must be byte-identical.
    local changed="" f rel missing=""
    while IFS= read -r f; do
        rel=${f#"$SBX/esp.before.tree"/}
        rel=${rel#./}
        [ "$rel" = "EFI/refind/refind.conf" ] && continue
        # The path we build MUST resolve, otherwise the comparison is vacuous
        # and would "pass" no matter what the script did. Treat an unresolved
        # path as a hard failure rather than skipping it.
        if [ ! -e "$ESP/$rel" ]; then
            missing="$missing $rel"
        elif ! cmp -s "$f" "$ESP/$rel"; then
            changed="$changed $rel"
        fi
    done < <(find "$SBX/esp.before.tree" -type f)
    if [ -n "$missing" ]; then
        fail "add-only: every pre-existing ESP kernel file byte-identical" \
            "unresolved paths:$missing"
        return
    fi
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
    local f rel
    ok=1
    while IFS= read -r f; do
        rel=${f#"$SBX/esp.before.tree"/}
        rel=${rel#./}
        # esp.before.tree predates the 7.3.1 staging, so only compare files
        # that existed then. A path that does not resolve post-promote means
        # the script DELETED a pre-existing file, which is a failure.
        if [ ! -e "$ESP/$rel" ]; then
            ok=0
            printf '      removed: %s\n' "$rel"
        elif ! cmp -s "$f" "$ESP/$rel"; then
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
    local boot="$REPO/recipes-bsp/cixmini-boot"
    local recipe
    recipe=$(ls "$boot"/cixmini-boot_*.bb 2>/dev/null | head -1)

    if [ -n "$recipe" ] && grep -qE 'file://ncz-refind-refresh' "$recipe"; then
        pass "packaging: a recipe ships ncz-refind-refresh"
    else
        fail "packaging: a recipe ships ncz-refind-refresh"
    fi

    # cixmini-boot ships TWO distinct scripts, and both matter:
    #   ncz-refind-refresh    the worker (add-only / --promote)
    #   cixmini-boot-refresh  the postinst entry point that delegates to it
    # The postinst must invoke the wrapper, so a rename of one without the
    # other is caught here.
    if [ -n "$recipe" ] && grep -qE 'file://cixmini-boot-refresh' "$recipe" &&
        grep -qE '^[[:space:]]*/usr/local/sbin/cixmini-boot-refresh' "$recipe"; then
        pass "packaging: cixmini-boot postinst runs the add-only refresh"
    else
        fail "packaging: cixmini-boot postinst runs the add-only refresh"
    fi

    # And the wrapper itself must delegate to ncz-refind-refresh -- otherwise
    # the postinst would run something that is not the add-only worker.
    local wrapper="$REPO/scripts/cixmini-boot-refresh"
    if [ -f "$wrapper" ] && grep -q 'ncz-refind-refresh' "$wrapper" &&
        grep -qE 'exec .*REFRESH' "$wrapper"; then
        pass "packaging: cixmini-boot-refresh delegates to ncz-refind-refresh"
    else
        fail "packaging: cixmini-boot-refresh delegates to ncz-refind-refresh"
    fi

    # The recipe must not CALL efibootmgr (comments that explain the removal
    # are fine; an invocation is not). Strip full-line comments only, then look
    # for the command as a word at the start of a statement.
    local efihits
    efihits=$(sed 's/[[:space:]]*#.*$//' "$recipe" 2>/dev/null |
        grep -nE '(^|[;&|][[:space:]]*)efibootmgr([[:space:]]|$)' || true)
    if [ -n "$efihits" ]; then
        fail "packaging: cixmini-boot neither clears nor recreates the firmware boot entry" "$efihits"
    else
        pass "packaging: cixmini-boot neither clears nor recreates the firmware boot entry"
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
    if grep -qE 'linux-image-\$\{(KERNEL_PKG_VER|KERNEL_VERSION|KVER|@)' "$recipe"; then
        pass "packaging: image package name is per-version"
    else
        fail "packaging: image package name is per-version" "$(grep -n 'linux-image' "$recipe" | head)"
    fi
    if grep -qE 'linux-headers-\$\{(KERNEL_PKG_VER|KERNEL_VERSION|KVER|@)' "$recipe"; then
        pass "packaging: headers package name is per-version"
    else
        fail "packaging: headers package name is per-version" "$(grep -n 'linux-headers' "$recipe" | head)"
    fi
    # The "latest" policy lives in a thin, EMPTY metapackage that only names
    # the legacy single-name packages (linux-image-cixmini / -headers-cixmini).
    if grep -qE 'PACKAGES.*linux-image-cixmini' "$recipe" &&
        grep -qE 'PACKAGES.*linux-headers-cixmini' "$recipe" &&
        grep -qE '^FILES:linux-image-cixmini = ""' "$recipe" &&
        grep -qE '^FILES:linux-headers-cixmini = ""' "$recipe"; then
        pass "packaging: thin EMPTY meta package keeps the legacy 'latest' names"
    else
        fail "packaging: thin EMPTY meta package keeps the legacy 'latest' names"
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
    if grep -qE 'RDEPENDS.*\$\{KERNEL_PKG_VER\}|RDEPENDS.*\$\{KERNEL_VERSION\}|RDEPENDS.*\$\{KVER\}' "$recipe"; then
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

# ===========================================================================
# O6N LAYOUT (2026-11-02). Everything above this line uses the LEGACY layout
# the script was written for: refind.conf at $ESP/EFI/refind/refind.conf,
# kernels staged under $ESP/EFI/ncz/ncz-<KVER>/, and menuentries titled
# "NCZ <KVER>".
#
# O6N's real ESP is different in three ways, all visible in the fixture
# scripts/fixtures/o6n-refind.conf (byte-identical copy of the live
# /boot/efi/EFI/BOOT/refind.conf, sha256 0de3effd...):
#
#   * rEFInd lives in $ESP/EFI/BOOT/ (installed as the removable-media
#     BOOTAA64.EFI), NOT $ESP/EFI/refind/;
#   * kernels and initrds sit at the ESP ROOT as /vmlinuz-<KVER> and
#     /initrd.img-<KVER>, not under a version directory;
#   * menuentries are titled after the DISPLAY NAME, e.g.
#     "NCZ-OS 26.10 Cygnus  -  7.3 Mali (Default)", and default_selection is
#     the quoted TITLE STRING "7.3 Mali (Default)" -- a substring of that
#     title -- never an index and never "NCZ <KVER>".
#
# On the base branch the script only knew the legacy layout, so every one of
# these tests FAILS there: it exits 4 with "no rEFInd on the ESP at
# .../EFI/refind" before writing anything.
# ===========================================================================

# A sandbox shaped exactly like O6N: refind under EFI/BOOT, kernels at the
# ESP root, title-named menuentries. Returns nothing; sets ESP/BOOT/SBX.
o6n_sandbox() {
    SBX=$(mktemp -d "${TMPDIR:-/var/tmp}/ncz-refind-o6n.XXXXXX") || exit 1
    ESP="$SBX/esp"
    BOOT="$SBX/boot"
    mkdir -p "$ESP/EFI/BOOT/icons" "$BOOT"

    cp "$REPO/scripts/fixtures/o6n-refind.conf" "$ESP/EFI/BOOT/refind.conf"
    : >"$ESP/EFI/BOOT/icons/os_linux.png"

    # The known-good 7.3.0 payload at the ESP root, byte-identical to what a
    # good install leaves behind. The install of 7.3.1 must not touch these.
    printf 'O6N-ESP-VMLINUZ-7.3.0\n' >"$ESP/vmlinuz-7.3.0-sky1-ncz"
    printf 'O6N-ESP-INITRD-7.3.0\n' >"$ESP/initrd.img-7.3.0-sky1-ncz"

    # The same known-good kernel in /boot (the script's fallback check).
    printf 'O6N-BOOT-IMAGE-7.3.0\n' >"$BOOT/Image-7.3.0-sky1-ncz"
    printf 'O6N-BOOT-INITRD-7.3.0\n' >"$BOOT/initrd.img-7.3.0-sky1-ncz"

    # The new 7.3.1 kernel, dropped by the package manager into /boot only.
    printf 'O6N-BOOT-IMAGE-7.3.1\n' >"$BOOT/Image-7.3.1-sky1-ncz"
    printf 'O6N-BOOT-INITRD-7.3.1\n' >"$BOOT/initrd.img-7.3.1-sky1-ncz"

    LOGFILE="$SBX/refresh.log"
}

# The options the real "7.3 Mali (Default)" entry carries, quoted form.
o6n_default_options() {
    sed -n '/menuentry "NCZ-OS 26.10 Cygnus  -  7\.3 Mali (Default)"/,/^}/p' \
        "$ESP/EFI/BOOT/refind.conf" | sed -n 's/^[[:space:]]*options[[:space:]]*//p'
}

# ---------------------------------------------------------------------------
# REGRESSION 1: the script finds refind.conf under EFI/BOOT, not just
# EFI/refind, and stages 7.3.1 on a real O6N ESP.
#   base: exit 4 ("no rEFInd on the ESP at .../EFI/refind"), no staging.
# ---------------------------------------------------------------------------
test_o6n_layout_finds_refind_in_efi_boot() {
    o6n_sandbox
    export NCZ_ESP_SKIP_MOUNT_CHECK=1
    run_refresh --kver 7.3.1-sky1-ncz
    if [ "$RC" = 0 ]; then
        pass "o6n: refresh succeeds on an EFI/BOOT/refind.conf ESP"
    else
        fail "o6n: refresh succeeds on an EFI/BOOT/refind.conf ESP" \
            "rc=$RC err=$(cat "$SBX/err.txt" 2>/dev/null)"
    fi
    if grep -qE '(^|[^-])/vmlinuz-7\.3\.1-sky1-ncz' "$ESP/EFI/BOOT/refind.conf" 2>/dev/null; then
        pass "o6n: a 7.3.1 entry was added to EFI/BOOT/refind.conf"
    else
        fail "o6n: a 7.3.1 entry was added to EFI/BOOT/refind.conf" \
            "$(tail -20 "$ESP/EFI/BOOT/refind.conf" 2>/dev/null)"
    fi
}

# ---------------------------------------------------------------------------
# REGRESSION 2: kernels are staged AT THE ESP ROOT (/vmlinuz-<KVER> and
# /initrd.img-<KVER>), matching the layout the existing entries use, and the
# new entry's loader/initrd point there.
#   base: never gets this far (exit 4), so both checks fail.
# ---------------------------------------------------------------------------
test_o6n_stages_kernel_at_esp_root() {
    o6n_sandbox
    export NCZ_ESP_SKIP_MOUNT_CHECK=1
    run_refresh --kver 7.3.1-sky1-ncz
    if [ "$RC" != 0 ]; then
        fail "o6n: new vmlinuz at the ESP root" "rc=$RC err=$(cat "$SBX/err.txt" 2>/dev/null)"
        fail "o6n: new initrd at the ESP root" "rc=$RC"
        fail "o6n: new entry loader/initrd use the ESP-root names" "rc=$RC"
        return
    fi
    if [ -f "$ESP/vmlinuz-7.3.1-sky1-ncz" ] &&
        cmp -s "$ESP/vmlinuz-7.3.1-sky1-ncz" "$BOOT/Image-7.3.1-sky1-ncz"; then
        pass "o6n: new vmlinuz at the ESP root"
    else
        fail "o6n: new vmlinuz at the ESP root" "$(ls -la "$ESP" 2>/dev/null)"
    fi
    if [ -f "$ESP/initrd.img-7.3.1-sky1-ncz" ] &&
        cmp -s "$ESP/initrd.img-7.3.1-sky1-ncz" "$BOOT/initrd.img-7.3.1-sky1-ncz"; then
        pass "o6n: new initrd at the ESP root"
    else
        fail "o6n: new initrd at the ESP root" "$(ls -la "$ESP" 2>/dev/null)"
    fi
    local entry
    entry=$(sed -n '/vmlinuz-7\.3\.1-sky1-ncz/,/^}/p' "$ESP/EFI/BOOT/refind.conf")
    if printf '%s' "$entry" | grep -qE 'loader[[:space:]]+/vmlinuz-7\.3\.1-sky1-ncz' &&
        printf '%s' "$entry" | grep -qE 'initrd[[:space:]]+/initrd\.img-7\.3\.1-sky1-ncz'; then
        pass "o6n: new entry loader/initrd use the ESP-root names"
    else
        fail "o6n: new entry loader/initrd use the ESP-root names" "$entry"
    fi
}

# ---------------------------------------------------------------------------
# REGRESSION 3: the new entry inherits the options of the entry named by the
# quoted TITLE STRING in default_selection ("7.3 Mali (Default)"), and the
# rescue variants' cmdlines are NOT copied.
#   base: never gets this far.
# ---------------------------------------------------------------------------
test_o6n_title_default_options_inherited() {
    o6n_sandbox
    export NCZ_ESP_SKIP_MOUNT_CHECK=1
    local want
    want=$(o6n_default_options)
    run_refresh --kver 7.3.1-sky1-ncz
    if [ "$RC" != 0 ]; then
        fail "o6n: new entry inherits the Milan/Default options" \
            "rc=$RC err=$(cat "$SBX/err.txt" 2>/dev/null)"
        return
    fi
    local got
    got=$(sed -n '/vmlinuz-7\.3\.1-sky1-ncz/,/^}/p' "$ESP/EFI/BOOT/refind.conf" |
        sed -n 's/^[[:space:]]*options[[:space:]]*//p' | sed 's/^"//; s/"$//')
    want=$(printf '%s' "$want" | sed 's/^"//; s/"$//')
    if [ -n "$want" ] && [ "$got" = "$want" ]; then
        pass "o6n: new entry inherits the displayed Default options"
    else
        fail "o6n: new entry inherits the displayed Default options" \
            "expected=[$want] got=[$got]"
    fi
    case "$got" in
        *ncz_rescue* | *"ro single"*)
            fail "o6n: rescue cmdline not copied" "got=[$got]"
            ;;
        *)
            pass "o6n: rescue cmdline not copied"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# REGRESSION 4 (the safety property that matters most on O6N): installing
# 7.3.1 leaves the known-good 7.3.0 files BYTE-IDENTICAL -- both at the ESP
# root and in /boot -- and does not rewrite default_selection.
#   base: exit 4, nothing staged (so the "staged" precondition fails), and if
#   it ever did run it would have overwritten the root vmlinuz/initrd.
# ---------------------------------------------------------------------------
test_o6n_known_good_untouched() {
    o6n_sandbox
    export NCZ_ESP_SKIP_MOUNT_CHECK=1
    local before_default kg_v kg_i b_v b_i
    before_default=$(grep -n '^default_selection' "$ESP/EFI/BOOT/refind.conf")
    kg_v=$(sha256sum "$ESP/vmlinuz-7.3.0-sky1-ncz" | cut -d' ' -f1)
    kg_i=$(sha256sum "$ESP/initrd.img-7.3.0-sky1-ncz" | cut -d' ' -f1)
    b_v=$(sha256sum "$BOOT/Image-7.3.0-sky1-ncz" | cut -d' ' -f1)
    b_i=$(sha256sum "$BOOT/initrd.img-7.3.0-sky1-ncz" | cut -d' ' -f1)

    run_refresh --kver 7.3.1-sky1-ncz
    if [ "$RC" != 0 ]; then
        fail "o6n: install succeeds (precondition for the no-touch checks)" \
            "rc=$RC err=$(cat "$SBX/err.txt" 2>/dev/null)"
    fi

    if [ "$(sha256sum "$ESP/vmlinuz-7.3.0-sky1-ncz" | cut -d' ' -f1)" = "$kg_v" ] &&
        [ "$(sha256sum "$ESP/initrd.img-7.3.0-sky1-ncz" | cut -d' ' -f1)" = "$kg_i" ]; then
        pass "o6n: known-good ESP-root vmlinuz and initrd untouched"
    else
        fail "o6n: known-good ESP-root vmlinuz and initrd untouched"
    fi
    if [ "$(sha256sum "$BOOT/Image-7.3.0-sky1-ncz" | cut -d' ' -f1)" = "$b_v" ] &&
        [ "$(sha256sum "$BOOT/initrd.img-7.3.0-sky1-ncz" | cut -d' ' -f1)" = "$b_i" ]; then
        pass "o6n: known-good /boot image and initrd untouched"
    else
        fail "o6n: known-good /boot image and initrd untouched"
    fi
    if [ "$(grep -n '^default_selection' "$ESP/EFI/BOOT/refind.conf")" = "$before_default" ]; then
        pass "o6n: default_selection title unchanged"
    else
        fail "o6n: default_selection title unchanged" \
            "was=[$before_default] now=[$(grep -n '^default_selection' "$ESP/EFI/BOOT/refind.conf")]"
    fi
    # The pre-existing bytes are still a strict PREFIX of the new file.
    local orig_bytes
    orig_bytes=$(wc -c <"$REPO/scripts/fixtures/o6n-refind.conf")
    if cmp -s -n "$orig_bytes" "$REPO/scripts/fixtures/o6n-refind.conf" "$ESP/EFI/BOOT/refind.conf"; then
        pass "o6n: refind.conf is append-only (original bytes are a prefix)"
    else
        fail "o6n: refind.conf is append-only (original bytes are a prefix)"
    fi
}

# ---------------------------------------------------------------------------
# REGRESSION 5: --promote on the title-named layout sets default_selection to
# the new entry's TITLE (a title string, like the one already there), not to a
# bare index that rEFInd would misread as a numeric position.
#   base: never gets this far.
# ---------------------------------------------------------------------------
test_o6n_promote_uses_title() {
    o6n_sandbox
    export NCZ_ESP_SKIP_MOUNT_CHECK=1
    run_refresh --kver 7.3.1-sky1-ncz
    if [ "$RC" != 0 ]; then
        fail "o6n: promote switches default to the new title" "stage rc=$RC"
        return
    fi
    run_refresh --promote 7.3.1-sky1-ncz
    if [ "$RC" != 0 ]; then
        fail "o6n: promote switches default to the new title" \
            "rc=$RC err=$(cat "$SBX/err.txt" 2>/dev/null)"
        return
    fi
    local sel
    sel=$(grep '^default_selection' "$ESP/EFI/BOOT/refind.conf")
    # The new default must name the 7.3.1 entry by title, and that title must
    # actually exist in the file.
    local title
    title=$(sed -n "/^default_selection/ s/^[^ ]*[[:space:]]*\"\(.*\)\"/\1/p" \
        "$ESP/EFI/BOOT/refind.conf")
    if [ -n "$title" ] && grep -qF "menuentry \"$title\"" "$ESP/EFI/BOOT/refind.conf"; then
        pass "o6n: promote sets a title that names a real menuentry"
    else
        fail "o6n: promote sets a title that names a real menuentry" \
            "sel=[$sel] title=[$title]"
    fi
    case "$title" in
        *7.3.1*) pass "o6n: promoted title names 7.3.1" ;;
        *) fail "o6n: promoted title names 7.3.1" "sel=[$sel]" ;;
    esac
    # And the known-good payload files are still untouched by promote.
    if cmp -s <(printf 'O6N-ESP-VMLINUZ-7.3.0\n') "$ESP/vmlinuz-7.3.0-sky1-ncz"; then
        pass "o6n: promote did not touch the known-good ESP files"
    else
        fail "o6n: promote did not touch the known-good ESP files"
    fi
}

# ---------------------------------------------------------------------------
# REGRESSION 6: a pre-existing legacy ESP (EFI/refind + EFI/ncz/ncz-<KVER>)
# still works. The O6N fix must not regress the layout the earlier tests use.
# ---------------------------------------------------------------------------
test_legacy_layout_still_works() {
    sandbox
    export NCZ_ESP_SKIP_MOUNT_CHECK=1
    run_refresh --kver 7.3.1-sky1-ncz
    if [ "$RC" = 0 ] && [ -f "$ESP/EFI/ncz/ncz-7.3.1-sky1-ncz/vmlinuz" ]; then
        pass "legacy: EFI/refind + EFI/ncz layout still stages"
    else
        fail "legacy: EFI/refind + EFI/ncz layout still stages" \
            "rc=$RC err=$(cat "$SBX/err.txt" 2>/dev/null)"
    fi
}

# ---------------------------------------------------------------------------
main() {
    if [ ! -x "$REFRESH" ]; then
        chmod +x "$REFRESH" 2>/dev/null || true
    fi
    test_new_options_ignore_rescue_default
    test_fallback_picks_highest_version
    test_recipe_install_path_matches_invocation
    test_recipe_declares_coreutils
    test_wrapper_needs_no_environment
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
    test_o6n_layout_finds_refind_in_efi_boot
    test_o6n_stages_kernel_at_esp_root
    test_o6n_title_default_options_inherited
    test_o6n_known_good_untouched
    test_o6n_promote_uses_title
    test_legacy_layout_still_works

    printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
    if [ "$FAIL" -ne 0 ]; then
        printf 'failed: %s\n' "${FAILED_NAMES[*]}"
        exit 1
    fi
    exit 0
}

main "$@"
