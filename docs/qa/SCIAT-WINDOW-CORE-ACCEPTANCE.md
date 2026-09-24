# Brohn response-window SC-IAT core

24 September 2026. Named adaptation: `sciat-brohn-response-window-im100/1.0`.
The [procedure decision and independent arithmetic](SCIAT-WINDOW-CANDIDATE.md)
remain the methodological contract. This slice implements original code for a
three-role authoring record, full compiler, dedicated first-response replay and
participant renderer. The component checkpoint preceded registration; the
integration lead has now added shared registration/routes. Connected study
acceptance remains separate from the component evidence recorded here.

## Frozen APIs

`R/platform-sciat-window.R` provides:

```r
brohn_sciat_window_profile()
brohn_sciat_window_new(title = "Sample Brohn response-window SC-IAT", id = brohn_id("task"))
brohn_sciat_window_validate(block)
brohn_sciat_window_compile(block, allocation_index = 1L)
brohn_sciat_window_validate_compiled(compiled)
```

The block retains the existing `brohn-task-block/1.0` shell and exactly three roles:
`target`, `attribute_positive`, `attribute_negative`. Its settings contain
`control_rationale`, materials `language`, and an immutable `procedure` object.
Instructions are currently English. Categories and text/image materials retain
explicit origin, rights and existing immutable asset manifests. The operational
minimum of two exemplars per category is not a stimulus-validity claim.

The compiler returns the existing `brohn-compiled-task/1.0` shell with its new exact
profile, original `source_block`, `design_hash`, `procedure`/`procedure_hash`,
`sequence_hash`, allocation, categories, blocks, timeline and provenance.
`validate_compiled()` reconstructs the complete original sequence from the source
block and allocation and compares canonical hashes. Invoke this on original
immutable compiled data, before adding authorized participant asset URLs.

There are four instruction entries plus exactly 192 trials: 24 practice, 72 test,
24 practice, 72 test. Odd allocations are A-first; even allocations B-first.
Positive stays on E and negative on I. A pairs target with positive; B pairs it
with negative. Category quotas, keys, all durations and per-block exemplar-cycle
reset belong to the named procedure. Park-Miller 16807 plus Fisher-Yates makes
the realized sequence independent of ambient R RNG state/configuration.

`R/platform-sciat-window-delivery.R` provides the existing outer-state-shaped seams:

```r
.brohn_sciat_window_delivery_new()
.brohn_sciat_window_delivery_apply(state, event, step)
.brohn_sciat_window_delivery_complete(state, step, event)
brohn_sciat_window_replay(compiled, events)
```

The dedicated wrapper uses `state$active$task`, the actual enclosing step start,
the actual page-clock instance and frozen `step$task`. It does not create a second
session, event table, consent record, participant ending or storage authority.
Pure task-only `replay()` explicitly returns `outer_session_qualified=FALSE`;
its nested observations cannot establish consent or a completed study.

The browser loads `www/participant/sciat-window-core.js`, then
`www/participant/sciat-window.js`. Its public call is:

```js
BrohnSciatWindow.run({container, compiled, emit, onCheckpoint,
  signal, clockInstanceId, checkpoint: null})
```

`emit(kind,data)` and `onCheckpoint(point)` must resolve after the existing
caller's durable local write, independently of eventual transport acknowledgment.
A failed callback stops the task and rejects; it cannot return completed. The
renderer owns no network or participant storage. Both instruction and timed
checkpoints are nonresumable. A non-null checkpoint refuses restart. The current
outer runner's interrupted-refresh/retained-journal behavior must remain in force.

## Received evidence contract

All observations remain inside the existing outer `type="task_event"` envelope,
with its existing scope and decimal-string `browser-monotonic` millisecond clock.
Nested clocks retain the same `instance_id` and `time_origin_ms`. Every nested
payload has `task_id`, `procedure_hash` and `clock`.

| Nested kind | Additional fields |
| --- | --- |
| `task_instructions` | `step_id`, `block_id` |
| `task_trial_started` | `trial_id`, `block_id`, `held_codes`, `timing_reference="requestAnimationFrame_before_paint"`, `viewport`, `stimulus_rect` |
| `task_trial_finished` | Fields described below, with `trial_id` and `block_id` |
| `task_interrupted` | `step_id`, `reason`; no invented trial onset or remaining phase end |

A finished-trial payload retains:

- `outcome`: `response`, `omission`, or `interrupted`.
- `response_outcome`: actual first `response`, sealed `omission`, or null when
  interruption prevented either. This remains distinct from trial completion.
- `response_code`, `response_ms`, `correct`: first accepted key, its event-time
  latency and literal accuracy; all null for omission. An error is terminal and
  cannot acquire a later correct-response latency.
- `onset_ms`, `deadline_ms`, `response_closed_ms`, `feedback_start_ms`,
  `feedback_end_ms`, `blank_end_ms`: observed phase boundaries, null where absent.
- `keys`: each allowed-key down/up observation has `type`, `code`, `event_ms`,
  `observed_ms`, literal `repeat`, `trusted`, `modifiers`, `response_open`,
  `accepted`, and `ignored_reason`. It includes ignored observations and releases.
- `interruption_reason`, `frame_count`, `max_frame_gap_ms`.

The receiver derives the first accepted response from the full key journal,
checks all summary fields, replays held/repeat/modified/synthetic/anticipatory
decisions and verifies feedback/blank durations. It rejects another accepted key
after the first. Missing or partial phases remain interrupted. The completion
guard requires all 192 assigned trials and four instructions in order, with no
interruption or clock-instance change. The outer delivery service still owns
event sequence/idempotence, consent, run ending and actual receipt support.

The event timestamp decides the inclusive 1,500 ms response boundary. A timeout
first enters a pending state; an eligible key arriving before sealing can still
win even when the timer callback ran first. Omission sealing passes a timer task
and another animation frame. If contradictory eligible evidence arrives after
sealing, the task interrupts instead of silently scoring a false omission.
Reversed event timestamps also interrupt. This is an explicit finite-observation
policy, not a guarantee about arbitrary operating-system dispatch delays.

## Minimal shared hooks owned by the integration lead

1. Route only this exact profile through its new constructor, validator, compiler
   and source-bound scorer. Keep every older profile's path and scoring unchanged.
2. At outer task start, route initial replay state by exact profile. At nested
   task events and outer step completion, route the corresponding apply/complete
   guards. Do not relax the old receiver's allowed fields or correction rules.
3. Add the two JS files to the existing participant resources and select
   `BrohnSciatWindow.run` in the current `showTask` route. Pass the current page
   clock, abort controller, durable event callback and checkpoint callback.
   Refresh stays an outer session interruption; do not call this module to replay
   already timed work.
4. Add authoring/clone/template/portable design handling for exactly three roles,
   fixed settings and nested source/procedure identity. Decorate image URLs using
   the existing authorized asset route after validating immutable compiled data.
5. Score the original `task_trial_finished` payloads only after full delivery
   replay. The separate scorer maps 144 test rows to the verified arithmetic
   reducer; the 48 practice observations remain available and unscored.
6. Preserve first-response versus omission/interruption semantics in complete
   exports/imports and person-aware cohorts. Imported summaries must not acquire
   invented key/phase/consent evidence. Export both original clock support and
   declared data-evidence level.

Key observation arrays are bounded to 5,000; hitting the operational limit
interrupts rather than truncating. The existing HTTP receiver caps each request
at 4 MiB. Offline transport must choose batches by serialized byte size as well
as event count; a large retained event must not make a 100-event batch impossible
to deliver. This shared transport constraint is reported to the integration lead.

## Evidence and limits

Final component evidence is retained at:

`C:/Users/User/Documents/Codex/2026-09-05/make/work/test-runs/brohn-sciat-core-20260924-04`

The pre-registration R domain suite passes **63 checks**, including full independent
original journals for both orders, exact quotas/exemplar cycles, source identity,
negative response/phase/clock cases and unchanged existing registration. The
pure JavaScript suite passes **22 checks**, including full 192-trial simulations
for both orders and both callback orders at the exact deadline. Independent R
cross-replay passes **19 checks** over those state outputs, including all 384
simulated trials. A trusted modifier-key release now clears held state even
though it cannot itself count as a response; the regression is in both the pure
state and actual browser checks.

Actual Chrome evidence is at `browser-1790230701830` under that folder: **17
checks**, both complete **192-trial** orders, and **two** instruction accessibility
scans at 1,280 and 390 pixels with zero violations/overflow. Independent R replay
passes **7 checks** against the actual retained browser journals, including both
complete orders, held-key/focus interruption and the prior-clock reload journal.
The desktop stimulus and narrow instructions were visually inspected. The final
run is fresh against the pinned sources; it does not reuse the earlier browser
run whose recovery test stopped after an overly strict assertion.

After shared registration, the updated domain suite passes **64 checks** at
`C:/Users/User/Documents/Codex/2026-09-05/make/work/test-runs/brohn-sciat-core-20260924-05-registered`.
Its independent snapshot in `tests/fixtures/sciat-legacy-profile-contract.json`
comes from pre-registration commit `0a6bde71c38f7419bcd979b322e20a6526cddad1`.
All five older profile definitions still hash to
`9b4045230a5a6885341f6179ccfe2219a3f31c84a021e4978e442a406435f653`;
the new profile is separately registered and constructs through the shared route.
The original 63-check unregistered receipt is retained without alteration.

| Retained receipt | SHA-256 |
| --- | --- |
| `-04/results.json`, 63 checks | `9e44a5f693307f58e51384e789dceddb3402929ba445e2be0377e2f711187a4f` |
| `-04/state-results.json`, 22 checks | `ff34cb488d3d8aa4f784f5e0192e696d8b513758a6ab69ebcdee2ee108d7e2ab` |
| `-04/independent-state-replay.json`, 19 checks | `ef09de748566c9179325300138d6e59d4b68829573acfc3a81cd26041d1521c5` |
| `-04/browser-1790230701830/results.json`, 17 checks | `3eeb47a017481c564ed2ba14d1a0236d0a165b819f537be51abffb9420864245` |
| `-04/browser-1790230701830/independent-browser-replay.json`, 7 checks | `2c498dd671ee2c808753f50743042f4bd6ad42faa25a9703537810f623d6896c` |
| `-05-registered/results.json`, 64 checks | `777fbc6d30839c2e3f18fb4d1e2ffac4d29c5fac237c0ba55ebaa9bb9618464b` |

All component services are terminal. No participant-service records, scientific
jobs or reports were created by this component fixture. Earlier `-01` through
`-03` folders remain preliminary diagnostics. Independent Chrome replay exposed
a pure-helper initialization error: its first nested observation precedes outer
callback dispatch. The helper now starts from the nested clock; actual delivery
continues to use the genuine outer `step_started` time. No original event was
rewritten to satisfy replay.

Browser component fixtures use original synthetic materials and trusted Chrome
keyboard events driven by Playwright. They deliberately do not register a study, claim a
consent/service receipt, run scoring workers or establish scientific validity.
The pending-ack component probe tests only that network acknowledgment belongs
to the caller; a real lost-ack service replay remains a connected acceptance gate.
Short preliminary probes are labelled partial component debug, never a completed
192-trial acceptance. Headless tab switching did not generate a blur, so the
retained failure is a fixture diagnostic; the corrected probe transfers actual
browser focus into an iframe and requires a trusted blur event.
An actual reload can record a genuine partial interruption before navigation;
the test preserves that received event and verifies it has no invented response
or phase completion. It no longer incorrectly requires every reload to leave
only an onset event.

The connected launch gate remains: researcher author/review/reuse, actual study
consent and both full192-trial assignments, exact retry/lost acknowledgment and
refresh receipts, native saved scoring, complete export/import and cohort review.
Physical keyboard/display timing, reliability and construct fit remain separate
from software replay and reference arithmetic.
