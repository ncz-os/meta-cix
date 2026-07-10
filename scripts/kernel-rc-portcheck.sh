#!/usr/bin/env bash
# scripts/kernel-rc-portcheck.sh
# Dry-run forward-port checker. Takes a target kernel.org tag/commit (e.g.
# v7.2-rc2) and applies the current meta-cix patches-7.2/ series one patch
# at a time against it, emitting a per-patch PASS/FAIL report with hunk-reject
# capture and rough classification of why. CI-style REPORT TOOL; does NOT
# auto-commit or auto-merge anything. Real forward-ports still need a
# human/zoder to resolve conflicts.
#
# Output: stdout human-readable summary + JSON report + per-patch reject
# files at $REJECTS_DIR/<patch>__<subdir>_<file>.rej (only for FAILs).
#
# Usage:
#   scripts/kernel-rc-portcheck.sh <tag-or-commit> [options]
#       --patches-dir DIR    --start NNNN    --end NNNN
#       --from-series DIR    --repo URL      --keep-workdir
#
# Exit codes: 0 = full pass, 1 = some failed (PARTIAL is the expected case
# for a real rc-tag forward-port), 2 = invocation/setup error.
#
# Implementation: `git mailinfo` strips mbox headers (matching what `git am`
# does in PATCHTOOL=git mode) followed by `git apply --check --reject -p1`
# against a single shared stage directory. This faithfully reproduces what
# `bitbake -c patch` does for each .patch file, including tolerant handling
# of patches whose last diff line lacks a trailing newline (raw `git apply`
# rejects them; git am silently tolerates them; we follow git am).

set -o pipefail

usage() {
    sed -n '2,30p' "$0"
    exit 2
}

TARGET="${1:-}"
shift || true
if [[ -z "$TARGET" || "$TARGET" == "-h" || "$TARGET" == "--help" ]]; then
    usage
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
META_CIX_ROOT="$SCRIPT_DIR"
for _ in 1 2 3 4 5; do
    if [[ -d "$META_CIX_ROOT/recipes-kernel/linux-cix-sky1-ncz" ]]; then
        break
    fi
    META_CIX_ROOT="$(dirname "$META_CIX_ROOT")"
done
if [[ ! -d "$META_CIX_ROOT/recipes-kernel/linux-cix-sky1-ncz" ]]; then
    echo "ERROR: could not locate meta-cix repo root from $SCRIPT_DIR" >&2
    exit 2
fi

DEFAULT_PATCHES_DIR="$META_CIX_ROOT/recipes-kernel/linux-cix-sky1-ncz/linux-cix-sky1-ncz-7.2/patches-7.2"
DEFAULT_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"
START_GLOB="0000"
END_GLOB="9999"
KEEP_WORKDIR=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --patches-dir)    PATCHES_DIR="$2"; shift 2;;
        --start)          START_GLOB="$2"; shift 2;;
        --end)            END_GLOB="$2"; shift 2;;
        --from-series)    PATCHES_DIR="$META_CIX_ROOT/$2"; shift 2;;
        --repo)           DEFAULT_REPO="$2"; shift 2;;
        --keep-workdir)   KEEP_WORKDIR=1; shift;;
        *) echo "ERROR: unknown arg: $1" >&2; exit 2;;
    esac
done

PATCHES_DIR="${PATCHES_DIR:-$DEFAULT_PATCHES_DIR}"
REPO="${REPO:-$DEFAULT_REPO}"
if [[ ! -d "$PATCHES_DIR" ]]; then
    echo "ERROR: patches dir not found: $PATCHES_DIR" >&2
    exit 2
fi

for cmd in git patch; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: missing dependency: $cmd" >&2
        exit 2
    fi
done

WORKDIR="$(mktemp -d -t rc-portcheck.XXXXXX)"
INFO_OUT="$(mktemp)"
BODY_OUT="$(mktemp)"
REPORT_JSON="$WORKDIR/report.json"
REPORT_TXT="$WORKDIR/report.txt"
REJECTS_DIR="$WORKDIR/rejects"
mkdir -p "$REJECTS_DIR"
trap '[[ $KEEP_WORKDIR -eq 0 ]] && rm -rf "$WORKDIR"; rm -f "$INFO_OUT" "$BODY_OUT"' EXIT
echo "Workdir: $WORKDIR  (use --keep-workdir to preserve)" >&2

echo "==> Cloning $REPO (shallow, target=$TARGET) ..." >&2
if ! git clone --quiet --filter=blob:none --no-checkout "$REPO" "$WORKDIR/linux" 2>"$WORKDIR/clone.err"; then
    echo "ERROR: clone failed; see $WORKDIR/clone.err" >&2
    exit 2
fi
cd "$WORKDIR/linux" || exit 2

echo "==> Resolving target '$TARGET' to commit SHA ..." >&2
SHA="$(git rev-parse --verify --quiet "${TARGET}^{commit}" 2>/dev/null || true)"
if [[ -z "$SHA" ]]; then
    if git fetch --quiet --depth=1 origin "refs/tags/${TARGET}:refs/tags/${TARGET}" 2>/dev/null; then
        SHA="$(git rev-parse --verify --quiet "${TARGET}^{commit}" 2>/dev/null || true)"
    fi
fi
if [[ -z "$SHA" ]]; then
    echo "    -- tag-fetch failed; trying full fetch (this may take a minute) ..." >&2
    git fetch --quiet origin "$TARGET" 2>"$WORKDIR/fetch.err" || true
    SHA="$(git rev-parse --verify --quiet "${TARGET}^{commit}" 2>/dev/null || true)"
fi
if [[ -z "$SHA" ]]; then
    echo "ERROR: could not resolve target '$TARGET' to a commit" >&2
    exit 2
fi
SHORT_SHA="${SHA:0:12}"
echo "    resolved: $SHORT_SHA" >&2

if ! git checkout --quiet "$SHA" 2>"$WORKDIR/co.err"; then
    echo "ERROR: checkout $SHORT_SHA failed; see $WORKDIR/co.err" >&2
    exit 2
fi

mapfile -t ALL_PATCHES < <(find "$PATCHES_DIR" -maxdepth 1 -type f -name '[0-9]*.patch' \
    | sed "s|$PATCHES_DIR/||" | sort)

PATCHES=()
for p in "${ALL_PATCHES[@]}"; do
    prefix="${p:0:4}"
    if [[ "$prefix" > "$START_GLOB" || "$prefix" == "$START_GLOB" ]] \
       && [[ "$prefix" < "$END_GLOB" || "$prefix" == "$END_GLOB" ]]; then
        PATCHES+=("$p")
    fi
done

if [[ ${#PATCHES[@]} -eq 0 ]]; then
    echo "ERROR: no patches matched start=$START_GLOB end=$END_GLOB in $PATCHES_DIR" >&2
    exit 2
fi

echo "==> Applying ${#PATCHES[@]} patches one at a time against $SHORT_SHA ..." >&2
echo "" >&2

classify() {
    local r="$1"
    local rej_count="${2:-0}"
    r="$(echo "$r" | tr '[:upper:]' '[:lower:]')"
    if echo "$r" | grep -qE 'no such file or directory|does not exist in'; then
        echo "file-missing-or-removed"
    elif echo "$r" | grep -qE 'corrupt patch|malformed|garbage'; then
        echo "malformed-patch"
    elif echo "$r" | grep -qE 'binary patch|no binary'; then
        echo "binary-patch"
    elif echo "$r" | grep -qE 'already applied|previously applied'; then
        echo "already-applied"
    elif echo "$r" | grep -qE 'hunk .* failed|context'; then
        echo "context-drift"
    else
        if [[ "$rej_count" -gt 0 ]]; then
            echo "context-drift"
        else
            echo "no-target-files"
        fi
    fi
}

PASS=0
FAIL=0
SKIP=0
RESULTS_JSON_ITEMS=()
STAGE_DIR="$WORKDIR/linux"

for p in "${PATCHES[@]}"; do
    PF="$PATCHES_DIR/$p"

    (cd "$STAGE_DIR" && find . -name '*.rej' -delete 2>/dev/null)

    # Strip mbox headers exactly like git am does.
    if ! (cd "$STAGE_DIR" && git mailinfo "$INFO_OUT" "$BODY_OUT" < "$PF" \
            2>"$REJECTS_DIR/$p.mailinfo.err") || [[ ! -s "$BODY_OUT" ]]; then
        STATUS="FAIL_MBOX"
        FAIL=$((FAIL+1))
        STDERR_TXT="$(cat "$REJECTS_DIR/$p.mailinfo.err" 2>/dev/null | tr '\n' ' ' | head -c 600)"
        REJ_EXCERPT="$STDERR_TXT"
        REJ_COUNT=0
        CLASS="malformed-patch"
    else
        (cd "$STAGE_DIR" && git apply --check --reject -p1 "$BODY_OUT" 2>"$REJECTS_DIR/$p.stderr")
        RC=$?
        if [[ $RC -eq 0 ]]; then
            STATUS="PASS"
            PASS=$((PASS+1))
            CLASS="n/a"
            REJ_EXCERPT=""
            REJ_COUNT=0
        else
            STATUS="FAIL"
            FAIL=$((FAIL+1))
            STDERR_TXT="$(cat "$REJECTS_DIR/$p.stderr" 2>/dev/null | tr '\n' ' ' | head -c 600)"
            mapfile -t NEW_REJS < <(cd "$STAGE_DIR" && find . -name '*.rej' -type f 2>/dev/null)
            REJ_COUNT="${#NEW_REJS[@]}"
            if [[ $REJ_COUNT -gt 0 ]]; then
                REJ_EXCERPT="$(cat "${NEW_REJS[0]}" | tr '\n' ' ' | head -c 600)"
            else
                REJ_EXCERPT="$STDERR_TXT"
            fi
            for rj in "${NEW_REJS[@]}"; do
                rjbase="$(basename "$rj")"
                rjdir="$(dirname "$rj" | sed 's|^\./||; s|/|_|g')"
                prefix_tag="${p%.patch}"
                if [[ -n "$rjdir" ]]; then
                    cp "$STAGE_DIR/$rj" "$REJECTS_DIR/${prefix_tag}__${rjdir}__${rjbase}" 2>/dev/null || true
                else
                    cp "$STAGE_DIR/$rj" "$REJECTS_DIR/${prefix_tag}__${rjbase}" 2>/dev/null || true
                fi
            done
            CLASS="$(classify "$STDERR_TXT" "$REJ_COUNT")"
        fi
    fi

    (cd "$STAGE_DIR" && find . -name '*.rej' -delete 2>/dev/null)

    esc() { echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | head -c 800; }
    RESULTS_JSON_ITEMS+=("$(printf '{"patch":"%s","status":"%s","classification":"%s","reject_excerpt":"%s"}' \
        "$(esc "$p")" "$(esc "$STATUS")" "$(esc "$CLASS")" "$(esc "$REJ_EXCERPT")")")

    printf '  %-90s %s\n' "$p" "$STATUS" >&2
done

{
    printf '{\n'
    printf '  "target":"%s",\n' "$TARGET"
    printf '  "commit":"%s",\n' "$SHA"
    printf '  "repo":"%s",\n' "$REPO"
    printf '  "patches_dir":"%s",\n' "$PATCHES_DIR"
    printf '  "start":"%s",\n' "$START_GLOB"
    printf '  "end":"%s",\n' "$END_GLOB"
    printf '  "total":%d,\n' "${#PATCHES[@]}"
    printf '  "pass":%d,\n' "$PASS"
    printf '  "fail":%d,\n' "$FAIL"
    printf '  "skip":%d,\n' "$SKIP"
    printf '  "results":[\n'
    first=1
    for r in "${RESULTS_JSON_ITEMS[@]}"; do
        if [[ $first -eq 1 ]]; then
            first=0
        else
            printf ',\n'
        fi
        printf '    %s' "$r"
    done
    printf '\n  ]\n'
    printf '}\n'
} > "$REPORT_JSON"

{
    echo "============================================================"
    echo "kernel-rc-portcheck SUMMARY"
    echo "  target : $TARGET  ($SHORT_SHA)"
    echo "  repo   : $REPO"
    echo "  patches: $PATCHES_DIR"
    echo "  range  : $START_GLOB .. $END_GLOB  (${#PATCHES[@]} files)"
    echo "  result : PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
    echo "============================================================"
    echo ""
    echo "Per-patch:"
    printf '  %-90s %-6s %s\n' "patch" "status" "classification"
    printf '  %-90s %-6s %s\n' "-----" "------" "--------------"
    for r in "${RESULTS_JSON_ITEMS[@]}"; do
        pname="$(echo "$r" | sed -n 's/.*"patch":"\([^"]*\)".*/\1/p')"
        pstat="$(echo "$r" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')"
        pcls="$(echo "$r" | sed -n 's/.*"classification":"\([^"]*\)".*/\1/p')"
        printf '  %-90s %-6s %s\n' "$pname" "$pstat" "$pcls"
    done
    echo ""
    echo "JSON report : $REPORT_JSON"
    echo "Reject files: $REJECTS_DIR/  (one *.rej per failed hunk, prefixed by patch)"
    echo "Stderr      : $REJECTS_DIR/<patch>.stderr"
    echo ""
    if [[ $FAIL -eq 0 ]]; then
        echo "OVERALL: FULL PASS - every patch applied cleanly to $SHORT_SHA."
    elif [[ $PASS -eq 0 ]]; then
        echo "OVERALL: TOTAL FAIL - zero patches applied to $SHORT_SHA. (target probably way ahead of series)"
    else
        echo "OVERALL: PARTIAL - $PASS/${#PATCHES[@]} applied cleanly, $FAIL failed."
        echo "          This is the EXPECTED case for a real rc-tag forward-port."
        echo "          A human/zoder needs to resolve the failures before any merge."
    fi
} | tee "$REPORT_TXT"

if [[ $FAIL -eq 0 && $SKIP -eq 0 ]]; then
    exit 0
fi
exit 1
