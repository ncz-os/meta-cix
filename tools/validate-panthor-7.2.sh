#!/bin/bash
# Cross-shell validation helper for the linux-cix-sky1-ncz 7.2 patch step.
#
# The literal command
#   cd ~/yocto-docker && source poky/oe-init-build-env build-cix-ncz72 \
#     >/tmp/be.log 2>&1 && bitbake -c patch linux-cix-sky1-ncz
# uses `source` (bash builtin) which is missing in /bin/sh (dash).
# Always invoke validation through this wrapper so the harness shell choice
# cannot make the verification artifact lie.
#
# Usage:  tools/validate-panthor-7.2.sh [--clean]
#
# Exit codes:
#   0  validation passed (do_patch Succeeded after forced reapplication)
#   *  validation failed; tail of LOGFILE is on the terminal
#
# Notes:
# - We deliberately avoid `set -u`/`set -e` in this script. oe-init-build-env
#   tests `[ -n "$BBSERVER" ]` and similar, which break under `set -u` from
#   a strict parent. `set -e` also aborts early on harmless warnings.
# - LOGFILE controls where the full output goes. Default: /tmp/cix_ncz72_validate.log

WORKDIR="${WORKDIR:-$HOME/yocto-docker}"
BUILDDIR="${BUILDDIR:-build-cix-ncz72}"
LOGFILE="${LOGFILE:-/tmp/cix_ncz72_validate.log}"

# Force bash so `source` and `BASH_SOURCE` work for oe-init-build-env's
# path resolution. If /bin/bash is not available, fall back to env bash.
if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

cd "$WORKDIR" || exit 2

# `source` is required by oe-init-build-env (bash builtin; absent in dash).
# shellcheck disable=SC1091
source poky/oe-init-build-env "$BUILDDIR" >"$LOGFILE" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "VALIDATION FAILED: oe-init-build-env exit=$rc" >&2
  tail -20 "$LOGFILE" >&2 || true
  exit "$rc"
fi

if [ "${1:-}" = "--clean" ]; then
  bitbake -c cleansstate linux-cix-sky1-ncz >>"$LOGFILE" 2>&1 || rc=$?
fi

bitbake -c patch linux-cix-sky1-ncz >>"$LOGFILE" 2>&1 || rc=$?

echo "---- tail of $LOGFILE ----"
tail -25 "$LOGFILE" || true
echo "--------------------------"

if [ "${rc:-0}" -ne 0 ]; then
  echo "VALIDATION FAILED: bitbake exit=$rc" >&2
  exit "$rc"
fi

if ! grep -q "task do_patch: Succeeded" "$LOGFILE"; then
  echo "VALIDATION FAILED: do_patch did not report Succeeded" >&2
  exit 1
fi

echo "VALIDATION PASSED: do_patch Succeeded"
exit 0
