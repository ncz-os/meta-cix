# Issue 4 adversarial analysis — rejected OPP-ceil prototype

The prototype that added `dev_pm_opp_find_freq_ceil()` to
`panthor_devfreq_get_cur_freq()` compiled in both kernel trees, but must not be
used:

- `panthor_devfreq_init()` already rounds `cur_freq` with
  `devfreq_recommended_opp()` and assigns the result to `profile.initial_freq`
  before devfreq copies it into `previous_freq`; the proposed first-transition
  root-cause story was therefore incomplete.
- `get_cur_freq()` is also exposed through sysfs, transition notifier old-rate
  reporting, resume bookkeeping, and `panthor_devfreq_get_freq()`. OPP-ceiling
  an unrelated CIX core clock would fabricate a GPU rate in all those paths and
  would also affect non-SCMI platforms.
- The downstream SCMI target returns success when rate limiting or backoff
  suppresses a transition. Generic devfreq then records the requested new OPP
  in `previous_freq` although hardware did not change. The driver consequently
  needs an actual SCMI current-state query/tracker and target-state contract
  reconciliation, not rounding of `clks.core`.

The 0168/2027 prototypes and recipe wiring were deleted. Any replacement needs
human-supervised O6N runtime validation and must not be inferred from a
compile-only result.
