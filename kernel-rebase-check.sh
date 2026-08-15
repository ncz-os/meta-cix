#!/bin/bash
# kernel-rebase-check.sh — dry-run the NCZ patch series onto an upstream tag.
#
# WHY: the series is 175 .patch files applied by the Yocto recipe on top of a
# pinned SRCREV. When a new upstream lands (e.g. v7.2 final) the only question
# that matters is "which of our patches no longer apply". Answering that by
# running a full bitbake takes ~40 minutes and stops at the FIRST failure, so a
# single early conflict hides the other 174 results.
#
# This applies each patch in recipe order against a scratch worktree and keeps
# going after a failure, so one run gives the complete conflict list.
#
# Usage: kernel-rebase-check.sh v7.2            # or any tag/commit in the mirror
set -uo pipefail

TAG="${1:?usage: kernel-rebase-check.sh <upstream-tag>}"
META="$(cd "$(dirname "$0")" && pwd)"
RECIPE="$META/recipes-kernel/linux-cix-sky1-ncz/linux-cix-sky1-ncz_7.2.bb"
PDIR="$META/recipes-kernel/linux-cix-sky1-ncz/linux-cix-sky1-ncz-7.2/patches-7.2"
MIRROR="${KERNEL_MIRROR:-/nfs-shared/downloads/git2/git.kernel.org.pub.scm.linux.kernel.git.torvalds.linux.git}"
WORK="${WORK:-/tmp/ncz-rebase-check}"

[ -f "$RECIPE" ] || { echo "no recipe at $RECIPE"; exit 2; }
[ -d "$MIRROR" ] || { echo "no kernel mirror at $MIRROR"; exit 2; }

# Patch order is the recipe's SRC_URI order, NOT `ls`. Numbering has duplicates
# (two 0146-*, two 0186-*), so sorting by filename would apply a different
# series than the build does.
mapfile -t PATCHES < <(grep -oE "patches-7\.2/[^ ]*\.patch" "$RECIPE" | sed 's|patches-7.2/||')
echo "=== ncz kernel rebase check ==="
echo "  target tag : $TAG"
echo "  patches    : ${#PATCHES[@]} (recipe order)"

git --git-dir="$MIRROR" rev-parse -q --verify "${TAG}^{commit}" >/dev/null 2>&1 || {
    echo "  FATAL: $TAG not in mirror. Fetch it first:"
    echo "    git --git-dir=$MIRROR fetch origin --tags"
    exit 2
}

rm -rf "$WORK"
git clone -q --shared --no-checkout "$MIRROR" "$WORK" 2>/dev/null
git -C "$WORK" checkout -q "$TAG" || { echo "  FATAL: checkout $TAG failed"; exit 2; }
echo "  worktree   : $WORK @ $(git -C "$WORK" describe --tags 2>/dev/null)"
echo

ok=0; fail=0; missing=0
declare -a FAILED
for p in "${PATCHES[@]}"; do
    f="$PDIR/$p"
    if [ ! -f "$f" ]; then
        echo "  MISSING  $p"; missing=$((missing+1)); FAILED+=("MISSING $p"); continue
    fi
    # --3way so a patch that merely moved context still counts as applying.
    if git -C "$WORK" apply --3way --whitespace=nowarn "$f" >/dev/null 2>&1; then
        ok=$((ok+1))
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
    echo "REBASE: CLEAN ✅  series applies to $TAG"
    exit 0
fi
echo "REBASE: NEEDS WORK ❌"
printf '  %s\n' "${FAILED[@]}"
exit 1
