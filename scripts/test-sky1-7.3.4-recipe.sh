#!/bin/bash
# test-sky1-7.3.4-recipe.sh: the 7.3.4 Sky1 kernel recipe is the 7.3.3 recipe
# moved to linux-stable v7.3.4 and nothing else.
#
#   - SRCREV_kernel is the v7.3.4 peeled commit (7595a62d45ee), LINUX_VERSION/PV say 7.3.4
#   - the SRC_URI patch list is the 7.3.3 list (incl. 0034), in the same order
#   - every patch and the defconfig are byte-identical to the 7.3.3 copies
#     (the series replays on v7.3.4 with fuzz 0, so no patch was rewritten)
#   - R290_EXPECTED_PATCHES equals the number of SRC_URI patches
#   - with LINUX_STABLE_GIT set, that mirror's v7.3.4^{commit} equals SRCREV_kernel
#
# usage: scripts/test-sky1-7.3.4-recipe.sh   (from the meta-cix root or anywhere)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D="$ROOT/recipes-kernel/linux-cix-sky1-ncz"
NEW="$D/linux-cix-sky1-ncz_7.3.4.bb"; OLD="$D/linux-cix-sky1-ncz_7.3.3.bb"
NEWD="$D/linux-cix-sky1-ncz-7.3.4"; OLDD="$D/linux-cix-sky1-ncz-7.3.3"
WANT_REV=7595a62d45ee1a2297eafa5f2ef5d0a45142d84d
pass=0; fail=0
ok()  { echo "PASS  $1"; pass=$((pass+1)); }
bad() { echo "FAIL  $1"; fail=$((fail+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
patches() { grep -oE 'file://[^ ]+\.patch' "$1" | sed 's#file://##'; }

check "7.3.4 recipe exists" '[ -f "$NEW" ]'
check "7.3.4 patch dir exists" '[ -d "$NEWD" ]'
if [ -f "$NEW" ]; then
    check "SRCREV_kernel is v7.3.4 ($WANT_REV)" \
        'grep -qx "SRCREV_kernel = \"$WANT_REV\"" "$NEW"'
    check "LINUX_VERSION is 7.3.4" 'grep -qx "LINUX_VERSION = \"7.3.4\"" "$NEW"'
    check "PV is 7.3.4+ncz" 'grep -qx "PV = \"7.3.4+ncz\"" "$NEW"'
    check "FILESEXTRAPATHS points at the 7.3.4 dir" \
        'grep -q "linux-cix-sky1-ncz-7.3.4:" "$NEW"'
    check "do_configure copies the 7.3.4 defconfig" \
        'grep -q "config-7.3.4-sky1-ncz.defconfig .{B}/.config" "$NEW"'
    check "no 7.3.3 file reference left outside comments" \
        '! grep -vE "^\s*#" "$NEW" | grep -q "7\.3\.3"'
    # 7.3.4 is a verbatim move of the full 7.3.3 list (incl. 0034): no
    # 7.3.4-only patches, no exceptions; order and names stay identical.
    check "SRC_URI patch list = 7.3.3 list, same order, no 7.3.4-only patches" \
        '[ "$(patches "$NEW")" = "$(patches "$OLD")" ]'
    n=$(patches "$NEW" | grep -c .)   # grep -c: BSD wc -l pads its count
    check "R290_EXPECTED_PATCHES equals the $n SRC_URI patches" \
        'grep -qx "R290_EXPECTED_PATCHES = \"$n\"" "$NEW"'
fi
if [ -d "$NEWD" ]; then
    for p in $(patches "$OLD"); do
        check "patch $p byte-identical to 7.3.3" 'cmp -s "$NEWD/$p" "$OLDD/$p"'
    done
    check "defconfig byte-identical to 7.3.3" \
        'cmp -s "$NEWD/config-7.3.4-sky1-ncz.defconfig" "$OLDD/config-7.3.3-sky1-ncz.defconfig"'
fi
if [ -n "${LINUX_STABLE_GIT:-}" ]; then
    check "mirror v7.3.4^{commit} == SRCREV_kernel" \
        '[ "$(git -C "$LINUX_STABLE_GIT" rev-parse "v7.3.4^{commit}" 2>/dev/null)" = "$WANT_REV" ]'
fi
echo "=== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
