# Saved signal review responsiveness

24 September 2026. This extends the existing complete-value acceptance; it does
not change scientific values, exclusions, exports or interpretation.

The ready exact-value view rereads report/catalog authority every second. It had
also repeatedly traversed the same large report to produce canonical JSON for
its hash. The recorded ECG report took approximately 0.92 seconds for one such
hash and 1.20 seconds for a cold context check on the exercised Windows host.

The signal-value reader now retains at most 128 pairs of a native serialized-value
SHA-256 and its canonical hash. It always fingerprints the complete current value.
Changed nested values, types and fields require a fresh canonical traversal.
It retains no report bodies, object bytes, permission results or database rows.
Fresh project, catalog, source and immutable-object checks remain in place.

`tests/platform-signal-value-hash.R` passed nine checks against independently
specified canonical JSON, changed nested values, typed null/zero/text, invalid
values, repeat computation and cache eviction. The existing
`tests/platform-signal-values.R` passed all 27 checks, including real worker
publication, complete CSV, cancellation/retry, changed catalog/project rejection,
stale page/download handling and revocation of visible values at the next poll.
Its retained workspace is `make/work/test-runs/brohn-values-qa-6bb066fd3e43`.

The same recorded context then took 0.03–0.05 seconds across five warm checks
(median 0.04 seconds). The timing receipt is
`make/work/test-runs/brohn-values-responsive-20260924/timing.json`.
These are observed host/fixture timings, not platform-wide performance promises.

## Actual interface check

`tests/researcher-signal-responsiveness.mjs` copies a retained recorded-data
workspace and opens its existing ECG report through Data library, the saved report
and its exact-value explorer. It passed 11 checks in
`make/work/test-runs/brohn-signal-values-browser-responsive-20260924-01/browser-1790217907170/results.json`.

The 108,000-row source remained complete. Across eight seconds of 50 ms browser
observations, Shiny reported busy in 11.875% of samples. Three navigations from an
active exact-value view to a ready Data library took 386, 256 and 532 ms. Search
worked after each navigation. Original ECG, PPG and schema reports remained
byte-identical; exact-value jobs were terminal and the two changed production
files retained their starting hashes. No browser exception occurred. The retained
desktop screenshot was visually inspected; the existing value-reader acceptance
provides the wider numerical, narrow-screen and accessibility coverage.

This is a focused regression check on one Windows host using one recorded ECG
report. It does not establish concurrent-user, clean-machine or every-report
latency. Services and the test browser were stopped after the journey.
