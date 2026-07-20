# O6N dmesg root-cause fix loop — progress log

Tracking the `o6n-fix-loop-task` (2026-07-20 08:31 UTC+08 → 14:40 UTC+08
across resumed iterations). Headline work flow follows the task brief exactly.
Author identity for commits in this log: `Jason Perlow <jperlow@gmail.com>`.

## State when this run started

- Repo HEAD: `wip/ultra/2026-07-10-linlondp-26q2` at `149b75f` (clean
  tree). 181 commits on this branch.
- Recent (last-15) commits already cover the prior tonight's run: 8
  O6N-specific dmesg fixes (`armchina_npu` IRQF_ONESHOT, scmi-hwmon
  thermal-zone skip, edp-panel ACPI reads, plus the 5 same-pattern
  `-ENOENT`-not-deferred clock-lookup fixes across linlondp / usb3-phy /
  cdnsp-sky1 / cdns-i2c / sky1_timer), plus 5+ follow-on
  SCMI/DP/PHY/pwm-sky1 fixes (0138-0166 series).
- `linux-cix-sky1-ncz_7.2.bb`: SRCREV_kernel = `a13c140cc289c0b7b3770bce5b3ad42ab35074aa`.
  Verified: this commit's `git show` reads `Linux 7.2-rc3` (Sun Jul 12
  14:16:39 2026). So the actual upstream base IS v7.2-rc3, despite the
  recipe's still-saying-rc1 comment header.
- `linux-cix-sky1-ncz/linux-cix-sky1-ncz-7.2/patches-7.2/` had 168 wired
  patches (numbered 0001-0166 + 2 `.unwired` DEBUG beacons).
- Local kernel-source working tree at
  `/home/jasonperlow/yocto-docker/ybuild/tmp/work/cixmini-nclawzero-linux/linux-cix-sky1-ncz/7.2+ncz/kernel-source`
  is on `v7.2-rc3 + 153 NCZ downstream commits` (HEAD
  `9f3b050970d2e`).
- v7.2-rc4 verified to exist on remote `git.kernel.org`:
  - `v7.2-rc4` tag: `6946cd5d0aa4dd10a414ddcb7a10844fdb0ad345`
  - `v7.2-rc4^{}` (commit) = `1590cf0329716306e948a8fc29f1d3ee87d3989f` = HEAD of `master`
  - 1 commit beyond rc3 = `b9e8d2c8e6e7` (whatever the upstream rc4 bump is).

## Iteration scope

1. PRIORITY 0 — rebase `linux-cix-sky1-ncz_7.2.bb` onto v7.2-rc4
   (commit `1590cf0329716306e948a8fc29f1d3ee87d3989f`). Update recipe
   comment header (still says rc1) to mention rc3→rc4. Re-apply all 168
   wired patches on rc4; hand-adjust any with context drift. Build-verify
   on rc4 base. Commit + push.
2. Issue 1 — `reset_controller_add_lookup(): reset lookup entry badly
   specified, skipping` (×3). Find and patch the CIX ACPI/reset lookup
   provider that's registering incomplete entries.
3. Issue 2 — `cix_resume_prepare.service` exit-code failure. Investigate
   in `cix-installer` repo (post-install scripts) and meta-cix (systemd
   unit).
4. Issue 3 — `btrfs: Unknown parameter 'nodelalloc'`. Find where it's
   specified (`/etc/fstab` or rootflags=) and fix it (likely rename or
   delete).
5. Issue 4 — `devfreq CIXH5000:00: Couldn't update frequency transition
   information`. Investigate the panthor/scmi devfreq path.
6. Issue 5 — `panthor CIXH5000:00: [drm] Firmware protected mode entry
   not be supported, ignoring`. Trace the actual log site; demote or
   leave alone depending on whether it affects function.

## Status

### PRIORITY 0 — rc3→rc4 rebase — DONE (committed + pushed)

- **Commit**: `b79d69a kernel(7.2): rebase SRCREV to v7.2-rc4 (1590cf032971)`
- Recipe `SRCREV_kernel` bumped from `a13c140cc28...` (v7.2-rc3) to
  `1590cf0329716306e948a8fc29f1d3ee87d3989f` (v7.2-rc4).
- Recipe header comment updated from "v7.2-rc1" wording to "v7.2-rc4"
  wording (lines 6-7).
- All 167 wired patches in `patches-7.2/` reapply cleanly on rc4 — none
  required hand-adjustment. The patch set was designed for 7.2-rc1,
  then rc3 (`edf9662`), and now rc4 — the 168→167 changes between
  sessions turned out to be a tooling count discrepancy (the 168 was
  the count from the prior session's PROGRESS.md header, the real
  count is 167 wired patches numbered 0001-0167 once the 0167 was
  staged in this iteration). Verified by reading the actual
  `patches-7.2/` directory.
- Paired full build verification completed successfully after the rebase and
  Issue 1 patch: `Tasks Summary: Attempted 1002 tasks of which 953 didn't need
  to be rerun and all succeeded.`

### Issue 1 — reset lookup badly specified — DONE LOCALLY; PUSH BLOCKED

- **Root cause**: drivers/soc/cix/acpi/cix-acpi-resource-lookup-v1.c (and
  the older non-v1 cix-acpi-resource-lookup.c used in 7.0.12/next tree)
  guard `reset_lookup_handle()`'s entries with:

  ```c
  if (!lookup->provider || (!lookup->dev_id && !lookup->con_id))
      continue;
  ```

  This guards against entries with no provider AND no dev_id AND no
  con_id.  But drivers/reset/core.c's `reset_controller_add_lookup()`
  enforces a TIGHTER contract: it rejects entries where `!dev_id ||
  !provider` and emits `pr_warn("reset lookup entry badly specified,
  skipping")` — without inspecting `con_id`.  So an entry whose dev_id
  is NULL while con_id is set slips past the local guard, reaches reset core,
  and gets rejected with the noisy warning — observed 3× per boot on O6N.
  The v7.2 source already has an `acpi_dev_name()` fallback for consumers whose
  platform_device has not yet been instantiated; the 7.0.12 sibling patch
  backports that fallback. Therefore a remaining NULL name denotes an
  unresolved/incomplete firmware reference, not ordinary probe ordering.

- **Fix**: tighten the guard to require BOTH provider and dev_id to be
  non-NULL, matching the reset core's own contract.  An entry without
  dev_id is not usable by `devm_reset_control_get*()` anyway (those
  calls match lookups by dev_id — the consumer's struct device_name —
  never by con_id alone), so dropping it locally is correct semantics,
  not a workaround.
- **Patch files** (wired into both recipes and committed):
  - `recipes-kernel/linux-cix-sky1-ncz/linux-cix-sky1-ncz-7.2/patches-7.2/0167-soc-cix-acpi-resource-lookup-tighten-badly-specified-guard.patch`
  - `recipes-kernel/linux-cix-sky1-next/files/next-patches/2026-soc-cix-acpi-resource-lookup-tighten-badly-specified-guard.patch`
- **Build status**: paired full bitbake run passed all 1002 tasks, including
  `do_patch`, `do_compile`, `do_compile_kernelmodules`, packaging and deploy.
- **Apply verification**: both patches pass `git apply --check` against
  separately exported pristine pre-patch source trees.
- **Commit**: `2692c71 fix(soc): validate CIX ACPI reset lookup entries`
  (author/committer `Jason Perlow <jperlow@gmail.com>`).
- **Adversarial review**: Codex gpt-5.5 was invoked repeatedly using prompt via
  stdin as required, including a final post-build review attempt at 14:33. The
  tool could not run the review because its configured OpenAI credentials are
  invalid/expired (HTTP 401, `refresh_token_reused` / missing bearer auth). No
  approval was fabricated. Manual source audit confirmed reset core's exact
  provider+dev_id contract, dev_id-before-con_id matching, fallback semantics,
  and recipe wiring.
- **Push**: attempted immediately after commit, but origin rejected SSH auth:
  `Permission denied ... Too many authentication failures`. Commit remains one
  local commit ahead of origin; no force-push was attempted. Operator must
  restore origin credentials, re-run Codex after reauthentication, then push.

### Issue 2 — cix_resume_prepare.service exit-code — FIRMWARE/INSTALLER LEVEL, FIX STAGED IN .work/

- **Root cause**: `/usr/bin/cix_resume_prepare.sh` (NOT in this repo;
  it's in the cix-installer repo at ARGOS `~/cix-installer-build/
  cix-installer/post-install/`).  The script unconditionally runs:

  ```sh
  swapPart=`blkid | grep $RESUME | sed 's/:.*//'`
  swapon $swapPart
  mount -o remount,nodelalloc,rw / /
  ```

  On O6N with no swap partition configured, $RESUME is empty (no
  `resume=` on the kernel cmdline) and $swapPart ends up empty too,
  so `swapon` with an empty arg fails.  Then the `mount -o remount` line
  also fails (for a separate reason — see Issue 3).  Script exits
  non-zero → systemd reports `Failed with result 'exit-code'`.

- **Fix**: rewrite the script to:
  1. Only attempt swapon if there's an actual matching partition.
  2. Drop the `nodelalloc` from the remount line (Issue 3 below — it's
     not a valid btrfs mount option on this kernel version).
  3. Always `exit 0` after the remount, even if individual steps
     failed non-fatally.
- **Staged fix** (NOT YET applied to running rootfs, NOT in a git
  repo on this host):
  - `meta-cix/.work/cix-installer-fix/cix_resume_prepare.sh` — the
    corrected script (syntax-checked clean with `sh -n`).
  - `meta-cix/.work/cix-installer-fix/orig.sh` — the current shipped
    version (copy of `/usr/bin/cix_resume_prepare.sh`).
  - `meta-cix/.work/cix-installer-fix/cix_resume_prepare.sh.diff` —
    unified diff.
- **Where the fix needs to land**: in the cix-installer repo on ARGOS
  (not on this host), so that future O6N installations get the
  corrected script.  Operator action required.

### Issue 3 — btrfs Unknown parameter 'nodelalloc' — SAME FIX AS ISSUE 2

- **Root cause**: same `/usr/bin/cix_resume_prepare.sh` line:
  `mount -o remount,nodelalloc,rw / /`.  `nodelalloc` is a mkfs-time
  btrfs option (removed from btrfs-progs around 2019) — it is NOT in
  the kernel's `btrfs_fs_parameters[]` table (verified at
  `fs/btrfs/super.c`).  Passing it triggers the generic
  `invalf(fc, "%s: Unknown parameter '%s'", ...)` from
  `fs/fs_context.c:144`, surfacing as `btrfs: Unknown parameter
  'nodelalloc'` in dmesg.  Also makes the remount itself fail
  (which contributes to the cix_resume_prepare.sh exit-code failure).
- **Not in fstab**: the O6N's `/etc/fstab` (generated by the
  cix-installer post-install/34-fstab.sh hook on this host) has
  `defaults,ssd,discard=async` for the btrfs root line — no
  `nodelalloc`.  So fstab is NOT where this comes from.
- **Fix**: same as Issue 2 — drop `nodelalloc` from the remount line.
  The kernel already knows the existing mount options from the
  original mount, so a bare `mount -o remount,rw / /` is sufficient on
  both btrfs and ext4 rootfs.
- **Patch artifact**: see Issue 2 above.

### Issue 4 — devfreq "Couldn't update frequency transition information" — ROOT-CAUSED; PROTOTYPE REJECTED

- **Exact warning path**: `devfreq_set_target()` calls
  `devfreq_update_status(devfreq, new_freq)` after a target callback reports
  success. `devfreq_update_status()` requires exact `freq_table` matches for
  both `previous_freq` and the new target, otherwise the generic devfreq core
  emits the warning.
- **Critical correction to the initial hypothesis**: the initial raw core rate
  is already rounded through `devfreq_recommended_opp(dev, &cur_freq, 0)` in
  `panthor_devfreq_init()`, stored as `panthor_devfreq_profile.initial_freq`,
  and copied by `devfreq_add_device()` to `previous_freq`. Therefore the
  warning is not simply caused by an unrounded initial `clk_get_rate()` value.
- **CIX-specific mismatch**: the downstream SCMI target path programs the
  `gpu_core` performance domain, while `get_cur_freq()` and
  `get_dev_status()` read `ptdev->clks.core`. More importantly,
  `panthor_devfreq_target()` intentionally returns success when a transition is
  suppressed by rate limiting/backoff, and generic devfreq then records the
  requested OPP as `previous_freq` even though hardware did not change. The
  downstream driver therefore lacks a trustworthy, synchronized current SCMI
  performance-state report.
- **Rejected prototype**: 0168/2027 rounded `clk_get_rate(core)` upward to an
  OPP in `panthor_devfreq_get_cur_freq()`. It compiled in both trees during the
  paired 1002-task build, but adversarial source review found it semantically
  unsafe: it would fabricate a current GPU frequency from an unrelated clock,
  affect non-SCMI platforms too, and change sysfs `cur_freq`, transition
  notifier `old`, resume bookkeeping, and `panthor_devfreq_get_freq()` output.
  It also does not repair the target-success-without-transition contract.
- **Disposition**: the prototype was removed from both recipes and is not
  committed. The rejected patch files were removed from the layer so they cannot be
  accidentally wired later; the investigation and failed-review evidence is
  retained in `.work/issue4-review-analysis.md`. A correct fix requires querying/tracking
  the actual SCMI performance state and reconciling suppressed target calls,
  then human-supervised O6N runtime validation. That cannot be established by
  compile-only desk work, so no speculative kernel patch is forced.
- **Codex**: final adversarial review was invoked via stdin at 14:35 but failed
  with the same HTTP 401 credential error; no review verdict was invented.

### Issue 5 — panthor Firmware protected mode entry not supported — NOT A BUG, INFORMATIONAL

- **Source line**: `drivers/gpu/drm/panthor/panthor_fw.c:586-590` (in
  both v7.0.12/next and v7.2/ncz trees; unmodified by NCZ — verified
  via grep against `patches-7.2/`).
- **Code path**: when parsing CSF firmware interface sections,
  panthor reads `hdr.flags`.  If `hdr.flags & CSF_FW_BINARY_IFACE_ENTRY_PROT`,
  the firmware declares a "protected mode entry" feature that
  upstream panthor v7.2-rc4 does not implement.  The driver emits:

  ```c
  drm_warn(&ptdev->base,
           "Firmware protected mode entry is not supported, ignoring");
  return 0;
  ```

  This `return 0` is intentional — the section is correctly skipped,
  and firmware loading proceeds normally.
- **Verdict**: per the task brief ("don't silence a message you
  haven't confirmed is safe to silence"), this is a genuine,
  accurate, informational log line from unmodified upstream code.  It
  is NOT a bug and the driver handles the unsupported feature
  gracefully.  Not patched.  Could optionally be demoted to `drm_dbg`
  in a future cosmetic upstream patch to reduce log noise, but that's
  a stylistic preference, not a bug fix — out of scope here.

## Build status and external blockers

- `/tmp/o6n-build-0167.log` records the paired build of rc4 + Issue 1 and the
  then-wired Issue 4 prototype. Both kernel recipes completed `do_patch`,
  `do_compile`, `do_compile_kernelmodules`, packaging and deploy. Final line:
  `Tasks Summary: Attempted 1002 tasks of which 953 didn't need to be rerun and
  all succeeded.`
- Issue 4 prototype recipe wiring was removed after semantic review; removal
  returns the built tree to a strict subset of that successful compile.
- Codex is externally blocked by expired/invalid credentials (HTTP 401).
- Push is externally blocked by origin SSH authentication. Local HEAD is
  three commits ahead of origin `b79d69a` (`2692c71` Issue 1,
  `ce923fc` final report, plus the tracked installer handoff artifacts commit).

## Final state / operator handoff

All requested items have a root-cause/disposition entry. Priority 0 is built
and pushed. Issue 1 is build-verified and committed locally but cannot be
Codex-approved or pushed until the external authentication failures are
repaired. Issues 2/3 have a syntax-checked installer fix staged under
`.work/cix-installer-fix/` for the ARGOS/cix-installer operator. Issue 4 is
correctly left without a speculative patch after the first prototype failed
semantic review. Issue 5 is confirmed informational and intentionally
unpatched.

Required operator actions:

1. Reauthenticate `~/.local/bin/codex`, run the saved Issue 1 review prompt at
   `.work/codex-review-issue1-final.prompt`, and require `VERDICT: APPROVE`.
2. Restore SSH credentials for origin
   `root@192.168.207.101:/mnt/datapool/git/meta-cix.git` and push local HEAD (including `2692c71`) without force.
3. Apply `.work/cix-installer-fix/cix_resume_prepare.sh.diff` in the scoped
   cix-installer repository on ARGOS, review/build there, and push separately.
4. If Issue 4 is pursued, implement actual SCMI current-state tracking and test
   only under human-supervised board boot; do not resurrect 0168/2027 as-is.

The `.o6n-fix-loop-done` sentinel is intentionally **not** created because the
required Codex approval and push of Issue 1 did not complete.
