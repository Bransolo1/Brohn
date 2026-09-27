# Reviewed cross-recording alignment checkpoint

27 September 2026. Scoped connected acceptance; full-platform development continues.

This checkpoint adds the connected researcher route for
`reviewed-two-event-affine/0.1.0-draft`: choose two preserved recordings, choose
original event correspondences, inspect an exact mapping and independent checks,
save a named version, and review original measurements with complete exports and
an automatically prepared overview. See the [researcher guide](../operations/REVIEW-ALIGNED-RECORDINGS.md)
and [architecture contract](../architecture/REVIEWED-CLOCK-ALIGNMENT.md).
All 50 capabilities and 17 work packages remain in scope and unfinished.

## Delivered behavior

The normal Data library view now offers **Align another recording**. Reference
recordings, imports, named alignments, versions and saved windows have bounded
search/paging. Original-event pages preserve exact row references across search
and overlapping pages. Defining events start unselected. A researcher must review
their correspondence and rationale; identical event labels are not evidence of
the same occurrence. Up to 16 independent pairs check the map without refitting.

Save and review publishes a named immutable map version, prepares its full
supported original-row window and automatically prepares a separate overview.
Every selected export row contributes to the display input. Supported numeric
signals retain actual extrema representatives, original continuity breaks,
separate units/scales and exact fractions; events retain original positions or
explicit count bins. Missing and unplaced observations are not invented values.
The display introduces no scientific score or resampling.

Chart state is independent of original-window readiness. The four original
exports remain usable while a chart waits, fails or is cancelled. Explicit retry
paints a new preparation ticket before access/source work; it renews authority
only for an appropriate failed/cancelled command. Late completion cannot replace
a different visible window. Existing successful exact-window plots are reused
before queueing. Different numerical pages retain different window identities;
the complete plot's coverage stays whole-window, but cross-page caching is not
asserted. Retained-CSV paging is a separate optimization.

Window and plot delivery hold qualified native read seals and recheck current
reader, source membership, project/archive state, successful publication and
session-bound HTTP capabilities. Bounds edits, closure and invalid source/access
refuse stale downloads. Old versions and exact plot/export bytes survive process
restart without a processing worker. Historical access belongs to the current
reader; an expired producer does not invalidate a successful authorized result.

## Connected evidence and source phases

These are separate phase-specific records, not one summed product score. The
external root below is
`C:/Users/User/Documents/Codex/2026-09-05/make/work/`.
The raw QA stores, screenshots and private configuration are not in GitHub.

| Phase | Executed evidence | Scope |
| --- | --- | --- |
| Original window authoring, UX checkout07 | `clock-ux-next-20260925/browser-journey-02`: 9 checks, 2 clean 390px scans | Visible original events, nonzero independent residual, actual preview/map/window workers, four actual browser downloads, repeated-save refusal. Three new successful jobs; 27 prior jobs and 53 original objects unchanged. |
| Independent original-row oracle | `browser-journey-02/independent-exports.json`: 11 checks, all 17 selected rows | Original JSONL values, identities, nanosecond tokens above 2^53, segments and independently calculated Fraction coordinates. Known scale 101/100, span 101/50 seconds, held-out residual -3/200 seconds. |
| Saved history, UX checkout08 | `browser-history-01`: 13 checks, 3 clean narrow scans | Real previous map version, unchanged downloads, edited-bound HTTP404 and cold restart with no processing worker or new jobs. |
| Connected complete overview, UX checkout10 | `browser-plot-02`: 19 checks, 4 clean narrow scans | Four original downloads while the chart waits without a worker; cancellation, painted retry, real child publication, changed-bound refusal, same-byte cold restart, actual researcher-authored version two, and exact version-one reopening. Eight new jobs: seven successes and one intentional cancellation. All 30 prior jobs, 59 original objects and scientific reports unchanged. |
| Independent connected-plot oracle | `browser-plot-02/independent-plot.json`: 12 checks | Exact bindings to all four browser downloads, all 17 selected rows, all 11 supported signal representatives, all four marker positions, independent Fraction/bin/vertical projections and separate missing-value runs. No worker implementation imported. |
| Final presentation, UX checkout11 | `browser-final-01`: 15 checks, 3 clean narrow scans; first complete signal figure in the natural phone viewport, actual chart download, all four original bytes and cold restart. No new jobs; 38 original jobs and 71 original objects unchanged. | Only paragraph ordering, accessible ready-message visibility and completed-heading scroll placement changed from checkout10. Processing, source/authority and resource logic did not change. |

The final source is assembled from accepted original-window/authority components,
the separately qualified plot adapter/resources and connected UX. Source hashes
and cross-phase provenance are recorded in `CLOCK-SOURCE-PHASES.json`; do not
claim earlier tests executed against later changed files. The
[backend/authority/resource summary](CLOCK-BACKEND-AUTHORITY-RESOURCES-20260927.md)
records actual processing, fault injection and restart counts separately.

## Component, renderer and regression evidence

- Original UI state: 44 assertions across nine scenarios, including atomic
  two-page queue rollback, stale selections, duplicate save, original download
  guards and native-resource lifecycle spies. These are Shiny state tests, not
  substitutes for the real browser/native worker evidence above.
- Complete overview controller: 27 passing checkout10 state assertions plus
  16 focused retry/window assertions. The retained alternate-window harness
  selection error was corrected using a genuine map-version/window selection.
  Source access revoked after retry feedback prevents lookup or a new queue;
  queued/running attempts reattach without a duplicate. Malformed failure detail
  receives a clear fallback. Final JavaScript coverage is recorded with its
  [reproduction instructions](../../tests/CLOCK-UI-REPRODUCE.md).
- Pure renderer: 25 checks over 11 fixtures; 17 independent CSV checks verify
  all 1,379 representative coordinates. Actual Chrome checks include 53 assertions
  and six clean scans, followed by five R and seven browser checks at the genuine
  2,000/2,001-marker boundary. Exact tiny-span labels, later extrema, disconnected
  runs, keyboard numerical views and malicious-label escaping are covered.
  This renderer source is unchanged in final connected UX.
- Portable Python package: 141 checks across eight suites through the actual
  catalog launcher. All recordings are generated in new external evidence
  folders. The suite includes a genuine R `brohn_json` roundtrip. Its 24 plot
  checks exclude one older test requiring a previously published catalog;
  the original external plot component therefore has 25 checks. See
  [portable instructions](../../tests/CLOCK-PYTHON-REPRODUCE.md).
- Existing core regression on frozen checkout10: all seven configured suites
  passed on the first attempt, totaling 408 assertions. Five actual imported-task
  attempts produced three expected reports and two expected integrity refusals.
  All 390 frozen application identities and 1,269 original checkout files stayed
  unchanged. The temporary delivery receiver bound loopback and was cleaned up.
  Final presentation-only changes did not alter those shared worker/store paths.

## Retained failures

Earlier attempts remain in external evidence; they were not overwritten or
silently combined into a fictitious clean run. Early browser harnesses used the
wrong navigation label, an unsupported Axe convenience context and an event
dropdown before its new binding was ready. These harness faults were corrected
without relabelling those attempts as passes. One owned idle R wrapper child was
identified by its exact fixture command and closed; later harnesses launch the
direct R executable and clean up owned processes.

The first plot browser correctly queued a retry, but its five-second wait still
saw the cancelled message while native/source work occupied the server. No new
application error was displayed. The retry was made explicit and responsive:
paint fresh preparation before that work. Its already queued attempt was allowed
to finish once in the same copied store, and a separate preservation check passed.
The original failed browser receipt remains failed. A focused test also found
that malformed legacy error detail produced an R diagnostic; the final helper
now supplies an understandable fallback. New source and fresh copied browser
evidence demonstrate both corrections.

The backend summary records separate worker, R/Python numeric-serialization and
resource-fixture failures, including their exact corrections and source limits.

## Limits and continuation

This is review/export for two recordings, each with one marker channel and one
or two supported scalar signals in a single unambiguous clock epoch. It does not
establish physical synchronization, timing accuracy, device qualification or
construct validity. Uncertainty remains unknown. Previously declared/processed
clock stages cannot silently become raw timestamps. Scientific recipes cannot
consume this map merely because a chart looks aligned.

Hosted authority tests use explicit synthetic verified-edge contexts and real
publication fences; they do not establish a new public deployment or identity
provider qualification. Windows native resource protection is the qualified
profile. Continuous playback, additional clock-fit/reset profiles, arbitrary
channel counts, complete report packaging, broader workloads and remaining
measurement/device/operations gates stay open. The full build continues after
publication; a checkpoint is not completion or a pause.
