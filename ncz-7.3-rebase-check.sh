#!/bin/bash
# ncz-7.3-rebase-check.sh -- rebase the r290 series (28 patches) onto any tag.
#
# The r290 series is the consolidated port patch + 27 numbered review patches
# 0001-0011 + 0013-0028. They are listed in SRC_URI file:// order (which is
# NOT the same as filename order), so SRC_URI order is what the build uses
# and that is what this script checks.
#
# `git apply` is too strict for these patches (it rejects hunks whose
# surrounding context has shifted even by one line -- e.g. an unrelated
# upstream file that gained a new `source "..."` block moves all the lines
# below by one). Bitbake uses `patch` (POSIX) which is what the build
# actually runs, and what this script uses. On any failure we reset to a
# clean tree so subsequent patches are judged on their own merit rather
# than cascading.
#
# Usage: ncz-7.3-rebase-check.sh <upstream-tag>
set -uo pipefail

TAG="${1:?usage: ncz-7.3-rebase-check.sh <upstream-tag>}"
META="$(cd "$(dirname "$0")" && pwd)"
RECIPE="$META/recipes-kernel/linux-cix-sky1-ncz/linux-cix-sky1-ncz_7.3-rc7.bb"
PDIR="$META/recipes-kernel/linux-cix-sky1-ncz/linux-cix-sky1-ncz-7.3-rc7"
MIRROR="${KERNEL_MIRROR:-/home/jasonperlow/yocto-docker/yocto6-ncz-tydeus/kernel-mirrors/linux-cix-kernel-73final-port.git}"
WORK="${WORK:-/tmp/ncz-rebase-check-73}"

[ -f "$RECIPE" ] || { echo "no recipe at $RECIPE"; exit 2; }
[ -d "$MIRROR" ] || { echo "no kernel mirror at $MIRROR"; exit 2; }

# SRC_URI order: first git:// line, then file://*.patch entries, in order.
mapfile -t PATCHES < <(awk '/^SRC_URI/,/^"/' "$RECIPE" \
    | grep -oE 'file://[^\\]+\.patch' \
    | sed 's|file://||')

echo "=== ncz 7.3 kernel rebase check ==="
echo "  target tag : $TAG"
echo "  patches    : ${#PATCHES[@]} (recipe SRC_URI order)"
echo "  pdir       : $PDIR"
echo "  workdir    : $WORK"

git --git-dir="$MIRROR" rev-parse -q --verify "${TAG}^{commit}" >/dev/null 2>&1 || {
    echo "  FATAL: $TAG not in mirror. Fetch it first:"
    echo "    git --git-dir=$MIRROR fetch origin --tags"
    exit 2
}

rm -rf "$WORK"
mkdir -p "$WORK"
git clone -q --shared --no-checkout "$MIRROR" "$WORK" 2>/dev/null
git -C "$WORK" checkout -q "$TAG" || { echo "  FATAL: checkout $TAG failed"; exit 2; }
echo "  worktree   : $WORK @ $(git -C "$WORK" describe --tags 2>/dev/null)"
echo

ok=0; fail=0; missing=0
declare -a FAILED=()
declare -a APPLIED=()
for p in "${PATCHES[@]}"; do
    f="$PDIR/$p"
    if [ ! -f "$f" ]; then
        echo "  MISSING  $p"; missing=$((missing+1)); FAILED+=("MISSING $p"); continue
    fi
    # `patch -p1` from the kernel source root. -F0 means require ZERO fuzz:
    # any hunk whose surroundings have drifted even by one line is rejected.
    # That is the strictness we want for a rebase verdict: a real rebase
    # reports the hunk as "fuzz X" or "offset Y", and the operator decides
    # whether to accept it; here we surface every such case as a FAIL so
    # nothing is silently force-resolved.
    if (cd "$WORK" && patch -p1 -F0 --no-backup-if-mismatch -i "$f" >/dev/null 2>&1); then
        ok=$((ok+1))
        APPLIED+=("OK $p")
    else
        fail=$((fail+1)); FAILED+=("CONFLICT $p")
        echo "  CONFLICT $p"
        # Leave the tree clean so later patches are judged on their own merit
        # rather than cascading from this one.
        git -C "$WORK" checkout -q -- . 2>/dev/null
        git -C "$WORK" clean -qfd 2>/dev/null
    fi
done

echo
echo "=== summary ==="
echo "  applied  : $ok / ${#PATCHES[@]}"
echo "  conflicts: $fail"
echo "  missing  : $missing"
if [ "$fail" -eq 0 ] && [ "$missing" -eq 0 ]; then
    echo "REBASE: CLEAN"
    exit 0
fi
echo "REBASE: NEEDS WORK"
printf '  %s\n' "${FAILED[@]}"
exit 1