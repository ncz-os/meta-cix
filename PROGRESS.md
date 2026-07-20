# O6N dmesg root-cause fix loop — progress log

Tracking the `o6n-fix-loop-task` (2026-07-20 08:31 UTC+08). Headline work
flow follows the task brief exactly. Author identity for commits in this
log: `Jason Perlow <jperlow@gmail.com>`.

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
- `linux-cix-sky1-ncz/linux-cix-sky1-ncz-7.2/patches-7.2/` has 168 wired
  patches (numbered 0001-0166 + 2 `.unwired` DEBUG beacons).
- Local kernel-source working tree at
  `/home/jasonperlow/yocto-docker/ybuild/tmp/work/cixmini-nclawzero-linux/linux-cix-sky1-ncz/7.2+ncz/kernel-source`
  is on `v7.2-rc3 + 153 NCZ downstream commits` (HEAD
  `9f3b050970d2e`).
- v7.2-rc4 verified to exist on remote `git.kernel.org`:
  - `v7.2-rc4` tag: `6946cd5d0aa4dd10a414ddcb7a10844fdb0ad345`
  - `v7.2-rc4^{}` (commit) = `1590cf0329716306e948a8fc29f1d3ee87d3989f` = HEAD of `master`
  - 1 commit beyond rc3 = `b9e8d2c8e6e7` (whatever the upstream rc4 bump is).

## Scope for this iteration

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

## Status (filled in as work progresses)

### PRIORITY 0 — rc3→rc4 rebase — IN PROGRESS

(See updates below.)

### Issue 1 — reset lookup badly specified — PENDING

### Issue 2 — cix_resume_prepare.service — PENDING

### Issue 3 — btrfs nodelalloc unknown — PENDING

### Issue 4 — devfreq transition information — PENDING

### Issue 5 — panthor protected-mode log — PENDING

