#!/bin/bash
# test-sky1-7.3.3-recipe.sh: the 7.3.3 Sky1 kernel recipe is the 7.3.1 recipe
# moved to linux-stable v7.3.3 and nothing else.
#
#   - SRCREV_kernel is the v7.3.3 commit (d50d994bffa3), LINUX_VERSION/PV say 7.3.3
#   - the SRC_URI patch list is the 7.3.1 list, in the same order
#   - every patch and the defconfig are byte-identical to the 7.3.1 copies
#     (the series replays on v7.3.3 with fuzz 0, so no patch was rewritten)
#   - R290_EXPECTED_PATCHES equals the number of SRC_URI patches
#   - with LINUX_STABLE_GIT set, that mirror's v7.3.3^{commit} equals SRCREV_kernel
#
# usage: scripts/test-sky1-7.3.3-recipe.sh   (from the meta-cix root or anywhere)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D="$ROOT/recipes-kernel/linux-cix-sky1-ncz"
NEW="$D/linux-cix-sky1-ncz_7.3.3.bb"; OLD="$D/linux-cix-sky1-ncz_7.3.1.bb"
NEWD="$D/linux-cix-sky1-ncz-7.3.3"; OLDD="$D/linux-cix-sky1-ncz-7.3.1"
WANT_REV=d50d994bffa3c7c6db2d8bc4c5f0c55e3f46b0cd
pass=0; fail=0
ok()  { echo "PASS  $1"; pass=$((pass+1)); }
bad() { echo "FAIL  $1"; fail=$((fail+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
patches() { grep -oE 'file://[^ ]+\.patch' "$1" | sed 's#file://##'; }

check "7.3.3 recipe exists" '[ -f "$NEW" ]'
check "7.3.3 patch dir exists" '[ -d "$NEWD" ]'
if [ -f "$NEW" ]; then
    check "SRCREV_kernel is v7.3.3 ($WANT_REV)" \
        'grep -qx "SRCREV_kernel = \"$WANT_REV\"" "$NEW"'
    check "LINUX_VERSION is 7.3.3" 'grep -qx "LINUX_VERSION = \"7.3.3\"" "$NEW"'
    check "PV is 7.3.3+ncz" 'grep -qx "PV = \"7.3.3+ncz\"" "$NEW"'
    check "FILESEXTRAPATHS points at the 7.3.3 dir" \
        'grep -q "linux-cix-sky1-ncz-7.3.3:" "$NEW"'
    check "do_configure copies the 7.3.3 defconfig" \
        'grep -q "config-7.3.3-sky1-ncz.defconfig .{B}/.config" "$NEW"'
    check "no 7.3.1 file reference left outside comments" \
        '! grep -vE "^\s*#" "$NEW" | grep -q "7\.3\.1"'
    check "SRC_URI patch list equals the 7.3.1 list, same order" \
        '[ "$(patches "$NEW")" = "$(patches "$OLD")" ]'
    n=$(patches "$NEW" | wc -l)
    check "R290_EXPECTED_PATCHES equals the $n SRC_URI patches" \
        'grep -qx "R290_EXPECTED_PATCHES = \"$n\"" "$NEW"'
fi
if [ -d "$NEWD" ]; then
    for p in $(patches "$OLD"); do
        check "patch $p byte-identical to 7.3.1" 'cmp -s "$NEWD/$p" "$OLDD/$p"'
    done
    check "defconfig byte-identical to 7.3.1" \
        'cmp -s "$NEWD/config-7.3.3-sky1-ncz.defconfig" "$OLDD/config-7.3.1-sky1-ncz.defconfig"'
fi
if [ -n "${LINUX_STABLE_GIT:-}" ]; then
    check "mirror v7.3.3^{commit} == SRCREV_kernel" \
        '[ "$(git -C "$LINUX_STABLE_GIT" rev-parse "v7.3.3^{commit}" 2>/dev/null)" = "$WANT_REV" ]'
fi
echo "=== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
