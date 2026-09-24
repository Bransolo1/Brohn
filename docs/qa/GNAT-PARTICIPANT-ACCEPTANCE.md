# GNAT participant component acceptance

24 September 2026. The isolated browser component and independent R replay pass
the evidence below. The connected researcher, consented participant, native
analysis, export/import and cohort journey has its own acceptance gate. This
document does not mark that wider route complete.

Procedure: [Brohn single-target GNAT](../methods/GNAT-BROHN-PROCEDURE.md).
Domain/compiler/scorer evidence: [GNAT core acceptance](GNAT-CORE-ACCEPTANCE.md).

## Installed contract

`www/participant/gnat-core.js` provides the pure `BrohnGnatCore` observation
engine. `www/participant/gnat.js` exposes:

```js
BrohnGnat.run({
  container, compiled, emit, onCheckpoint, signal,
  clockInstanceId, checkpoint: null
})
```

The caller owns consent, actual session authority, durable journaling, exact
transport retries and final session ending. The renderer neither posts to a
parallel endpoint nor creates its own participant store. Any non-null checkpoint
refuses a restart of this administration. The result contains `outcome`,
`reason`, `responses` and `last_completed_trial_id`.

The complete compiled sequence has 396 entries: 12 self-paced instructions and
384 original trials. The renderer emits the existing nested event kinds
`task_instructions`, `task_trial_started`, `task_trial_finished` and
`task_interrupted`. It does not shorten trials, add accuracy retries or replace
the named deadline/feedback/blank parameters.

Onset records retain geometry, page-clock identity, visible/focused state and an
explicit `release_wait` containing start/end, initial held keys, raw key events
and visibility snapshots. A failed wait can be attached to `task_interrupted`
without inventing an onset. Trial results retain all key classifications,
visibility changes, requested deadline, observed deadline timer and subsequent
animation frame, observed response removal, feedback and blank timing. A genuine
miss or correct rejection has a null response key and null response latency.

An eligible first Space event uses the half-open original timestamp window:
onset inclusive, deadline exclusive. A delayed on-time event can be accepted
before sealing. A contradictory event observed after a saved trial is preserved
separately in `task_interrupted.contradiction`; its `step_id` names that original
sealed trial. The already saved response is never rewritten. Earlier complete
receipts do not make an interrupted administration complete.

## Pure state and independent replay

The installed `tests/gnat-state.mjs` passes 33 checks in:

`work/test-runs/brohn-gnat-component-20260924-01/evidence-state-1790261495922`

It executes all 384 compiled trials and covers hit, miss, false alarm and correct
rejection; zero measured latency; the exact excluded deadline; the last eligible
fractional timestamp; delayed dispatch before/after sealing; earlier-than-first
contradictions; other, untrusted, modified, repeated and impossible key states;
held-key refusal; visibility/focus loss; incomplete timer/frame evidence; minimum
feedback and blank; release-required progression; immutable terminal records;
and invalid timing/procedure inputs.

Its complete 384-trial generated journal passes three independent R checks in
`independent-r-replay.json` in the same folder. All four outcomes remain distinct,
every frozen trial is received, and `outer_session_qualified` remains false.
This is an original synthetic component fixture, not fabricated received study
data. No participant session, scientific report or analysis job is created.

The first full pure-journal generator attempt used unrounded JavaScript additions
between simulated page times and was refused for reversing its own serialized
clock by a binary64 unit. The fixture now emits its declared six-decimal page
times consistently. That preparation failure is retained in
`work/gnat-next-20260924`. Separately, actual cross-language replay exposed a real
R derived-arithmetic issue: a serialized `2617.03` deadline did not equal raw
binary64 `1617.03 + 1000`. The domain owner normalized only derived deadline,
latency and duration-bound calculations to the declared six decimal places.
Raw event eligibility and ordering remain exact. This representation agreement
does not assert microsecond physical timing accuracy.

## Actual Chrome evidence

The original complete browser receipt is:

`work/gnat-next-20260924/evidence-browser-1790260796892/results.json`

It passes 13 checks, including all 384 actual timed trials and all 12 self-paced
instruction screens in 371,127 ms. The fixture sends trusted Space keys for Go
items and genuinely withholds responses for No-Go items. All complete onset and
finished receipts are retained in `complete-384.json`. No timer is accelerated,
clock paused or shortened complete protocol substituted.

The component also exercises held instruction Space, observed release before
onset, trusted response timing, actual deadline withholding, a trusted delayed
timestamp delivered through Chrome's input interface, real focus loss, refresh
refusal with the local journal preserved, and a failed durable onset write.
These use the entire frozen compiled protocol but deliberately interrupt their
partial cases; they are not presented as completed administrations.

The initial focus test failed because Playwright's enabled focus emulation kept
`document.hasFocus()` true even after another tab became foreground. The retained
attempt is `evidence-browser-1790260673826`. The corrected test explicitly turns
off that emulation before changing the foreground page. Actual blur evidence
then reports `focused: false` and interrupts. Product focus guards were not
weakened or replaced with a mocked visibility flag.

Independent R replay accepted the original complete 384-trial journal and every
outcome/latency, but rejected its initial delayed-key interruption because the
renderer named the current boundary rather than the required original sealed
trial in `step_id`. The one-line identity correction leaves timing, normal
completion, core state and rendered content unchanged. Exact previous renderer
bytes are reproduced by reversing that one edit, and the installed complete
fixture equals the original fixture; both checks are in:

`work/test-runs/brohn-gnat-component-20260924-01/source-delta.json`

The final installed-source fault receipt is:

`work/test-runs/brohn-gnat-component-20260924-01/evidence-browser-1790261577253/results.json`

It passes 11 actual Chrome checks, adding focus loss during a held-key wait before
any trial onset. The typed failed wait survives with its observed false focus
and exact interruption clock, and no trial onset is invented. Its independent
R replay receipt passes 12 checks joined to the retained original complete
384-trial evidence. The initial inconsistent delayed-key receipt remains
explicitly refused, while the corrected late key and pre-onset wait are retained
as separate interruption evidence. Earlier component receipts remain available;
the final partial receipt does not claim a second full administration.

The initial instructions at 390px have zero axe violations and no horizontal
overflow. Their actual screenshot was visually inspected: category instructions,
physical-key requirement, interruption explanation and phase-start button are
readable. This is a component instruction scan, not a full-platform accessibility
audit. The integrated journey owns authoring, actual timed material/feedback and
result screenshots.

## Exact source identity

| Source | SHA-256 |
| --- | --- |
| Installed `gnat-core.js` | `0cd76c3b8f19ddf37eb5d0230a8d0af8f9f11e24ab21bc3c6d19646fc42fdf1c` |
| Original full-384 `gnat.js` | `1795882a1a65ebe6b905fce332aa3d7524985e07b6053747e0bd31a499d70ac1` |
| Installed corrected `gnat.js` | `7b348b9f14805ac63831365a552437144e160b6054e4dd681aca658d18027194` |

The independent replay receipts pin their actual R domain hash. Source phases
are kept separate. Existing six participant profiles and previously preserved
runtime distributions are outside these new component files.

## Reproduction

From the repository root with the documented R/Node dependencies configured:

1. Run `Rscript --vanilla tests/fixtures/gnat-component.R <new brohn-gnat-* directory>`.
2. Run `node tests/gnat-state.mjs <that directory>`.
3. Run `node tests/gnat-browser.mjs <that directory>` for the actual complete
   component journey. `--component-only` runs the deliberately interrupted cases
   and must not be reported as complete-protocol acceptance.
4. Run `Rscript --vanilla tests/verify-gnat-browser.R <compiled.json> <evidence directory>`.
   An optional third directory supplies a separately identified fault-path
   continuation while retaining the original complete receipt.

The component writes only its explicit fixture/evidence directory. It does not
qualify consent, delivery authentication, transport-loss reconciliation, native
scoring, population/material reliability or physical visual timing. Those
boundaries remain with their respective connected and scientific evidence.
