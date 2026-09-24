# Brohn single-target GNAT core and saved plots

24 September 2026. Installed component qualification for the named
[`gnat-brohn-single-target/1.0` procedure](../methods/GNAT-BROHN-PROCEDURE.md).
This receipt does not establish completed participant/browser integration,
physical timing, material validity, reliability or whole-platform completion.
Ordinary authoring activation remains a separate connected-delivery gate.

## Implemented contract

[`platform-gnat.R`](../../R/platform-gnat.R) owns original deterministic
compilation, scoring and independent received-event replay. Public functions are
`brohn_gnat_profile`, `brohn_gnat_new`, `brohn_gnat_validate`,
`brohn_gnat_compile`, `brohn_gnat_validate_compiled`, `brohn_gnat_sensitivity`,
`brohn_gnat_score(compiled,responses,completed=TRUE,timing_known=TRUE)` and
`brohn_gnat_replay`. Delivery adapters use `.brohn_gnat_delivery_new`,
`.brohn_gnat_delivery_apply` and `.brohn_gnat_delivery_complete`.

Existing block/compiled-task/task-score 1.0 shells are retained. A canonical
compile reconstructs all 384 trials and 12 instruction boundaries from source,
seed and allocation. Procedure and exact sequence hashes remain separate.
Settings retain language, context kind/rationale, control rationale and immutable
procedure. Trials retain category/material, phase, round/cell, expected Go/No-Go
action, deadline and feedback/blank rules. No No-Go correct key is fabricated.

Scores bind `scoring_recipe=brohn-gnat-single-target-score/1.0` and the named
`gnat-brohn-endpoint005/1.0` arithmetic rule. Four cell sensitivities, four
criteria and two within-round contrasts are dimensionless. Full uninterrupted
384-trial support is required for primary eligibility. Correct rejection has
accuracy true and miss false; both retain null key and null latency. Nonpositive
sensitivity is retained with a support flag, without automatic person exclusion.

The audit contains immutable target/context labels and rationale, training and
round order, four-outcome counts, raw/corrected rates, endpoint flags,
response-only RT denominators and all observed rows. Unknown declared timing
retains actual nonnegative values and counts, including out-of-window values,
but produces no sensitivity, criterion, contrast or eligible metric. Its test
replaces `qnorm` with a throwing function to verify that scoring is not invoked.

## Received timing and interruption evidence

Nested events remain `task_instructions`, `task_trial_started`,
`task_trial_finished` and `task_interrupted` under the existing task envelope.
Each binds task/procedure and decimal page-monotonic clock identity. A finished
trial retains observed onset, deadline/timer/subsequent frame, sealed closure,
feedback and blank, complete raw keys, visibility/focus, provisional outcome and
qualified outcome separately. The server derives accepted Space, outcome,
latency and accuracy; it does not trust client summary fields.

Every successful onset requires its raw `release_wait` through the actual onset
frame. A failed guard can retain that typed wait on an interruption without
inventing onset. Initial/final held states must agree with observed key changes.
Late dispatch that contradicts a previously sealed withholding or first response
retains both receipts plus typed `contradiction={trial_id,key}` and interrupts;
no historical finished receipt is rewritten. Exact-deadline keys stay late.

Native timestamps and derived clock arithmetic serialize six decimal places in
milliseconds. The precision repair normalizes only derived deadline, RT and
minimum-duration operands. Exact raw half-open and monotonic comparisons remain
unchanged; one-microsecond short feedback/blank and changed RT are refused.
Pure replay explicitly returns `outer_session_qualified=FALSE`: it supplies no
consent, session or participant ending.

## Complete saved plots

[`platform-task-plots.R`](../../R/platform-task-plots.R) retains existing project,
report, immutable object, protocol and journal guards. GNAT native export rows
use the dedicated parser and audit, preserving exact response decimal lexemes.
The UI shows four outcome lanes plus distinct interrupted, unpresented and absent
source lanes, then actual Space-response latency and distribution. Withholding
is counted separately and has no zero/deadline-valued latency. There is no
final-correct latency selector for GNAT. No plot invokes scoring.

All 384 expected positions remain in complete models; the test-only filter has
240. Numerical pages contain 50 rows, while charts and guarded CSV/JSON/SVG
downloads retain complete selected arrays. CSV includes exact typed source JSON;
JSON additionally retains the complete source independently of the filter.
Responsive 320/680 SVG variants use 12-pixel text in their own viewboxes.
Actual browser accessibility and visual inspection remain the connected harness's
responsibility; component HTML checks are not described as browser proof.

## Retained evidence

Paths below are under the outer workspace's `work/test-runs`, outside Git.
Current core SHA256:
`c51e8f7e6015e59a9054a6cae8561ad3be4937c29058989ca5821113fb500803`.

| Receipt | Passed checks | SHA256 |
| --- | --- | --- |
| `brohn-gnat-domain-20260924-02/results.json` | 105 compiler/scorer/authored-journal | `3d56cb76cc1ef62d49d5d07bcbc63c086e0ce23ce4ca35c90f2145ef2521609d` |
| `brohn-gnat-replay-20260924-02/results.json` | 67 timing/key/release/contradiction adversarial cases | `3758c2ccde50f9a4eeaf27e8ec8d6fea1beeea72a7e0f2ecff0e7b7bdc44cddc` |
| `brohn-gnat-domain-20260924-02/independent-oracle.json` | 20 independent Python compiler/NormalDist checks | `e4aa621fc96fbfd77498bc9c92f9fece96e7f5fa5541064f182d3873e96a7f32` |
| `brohn-gnat-plots-20260924-04/results.json` | 26 complete native-row/plot/view/export/support checks | `c72ee4b3e072615872ffd055e562ee7a87f1e4d0d61c6405e121ef2b4e5b312c` |

The domain fixture retains complete compiled source, 780 authored nested journal
events, score and unknown-timing score. The independent standard-library oracle
checks every role/exemplar/action/phase/deadline using separately authored
Park-Miller/Fisher-Yates logic, four expected cell tables, quantile arithmetic,
response-only summaries and both contrasts. This is authored software evidence,
not a participant recording.

Earlier external candidate runs remain in `work/gnat-next-20260924`, including
97/48/20 checks before new evidence fields. Current-tree `-01` core receipts
precede the fractional clock repair and are not substituted for current hashes.
The JS-to-R mismatch that motivated repair was a real one-ULP arithmetic defect;
the original full JS receipt is retained by the participant component harness.

Plot attempt `brohn-gnat-plots-20260924-01` stopped at a harness expectation for
an underscore in a humanized table heading; original HTML/SVG is retained.
`-02` passed 25 checks. Attempt `-03` failed before fixture execution because a
concurrent shared authoring edit briefly contained a parse typo. The final
current-source `-04` receipt passed 26, including UI-independent cohort labels.
The existing `tests/platform-task-plots.R` regression passed 42 source/export/
Shiny checks, including project revocation and stale-control refusal.

Plot acceptance `-04` source SHA256 values: domain
`8e8d6de4b892f9ba422d5de76dbe641f73abca85a08f5c3b990cfc667e6d5c29`,
views `ce0ee433a2ff7add86c407049b561235f8e3e045bc69908f794e892afba0dad3`,
GNAT score/settings views
`b973199a4d643de8f0ad5f484abcff6061a38040969f94e645e02cb9fb3ced8c`.
The domain harness now snapshots only the earlier six profiles and records
actual GNAT registration dynamically, so later intentional activation does not
break this unchanged-core regression. Earlier receipts accurately retain their
disabled-registration state.

### Imported timing-label correction and activation-safe oracle

The imported source declares `timing_quality.definitions_known`; the common plot
view expects the singular `definition_known`. A known imported GNAT source was
therefore incorrectly labelled as having unknown timing. The plot model now adds
the singular display flag once, while retaining every original timing field,
the original source hash, score and exact rows. Native models are unchanged.

`brohn-task-plot-timing-20260924-01/results.json` passes 25 checks across actual
GNAT and legacy simple-RT CSV imports with known/unknown timing, rendered warning
text, unchanged original metadata and exports, plus native contract-model cases.
Its SHA256 is
`28e7013356687c1f77633da1ab477a6f96028022d4cd5be3d819d807ab2c9a09`.
The current plot domain SHA256 is
`eb70caf56068287a84fe3eff8cdb7ebd92901611822ea4bba3c0cf2e9a81f6e3`;
plot and GNAT views retain the hashes above. This receipt is model/import/render
evidence; the fresh complete browser journey qualifies the current UI separately.

After normal GNAT chooser activation, the independent oracle now checks the exact
original six-profile snapshot and records the actual registration flag instead
of requiring that GNAT remain disabled. Arithmetic and sequence assertions are
unchanged. Current core `brohn-gnat-domain-20260924-03/results.json` passes 105
checks (SHA256
`318fc4ea80a49521f93c9f053c1ad81bc2d9c72d9614298db1e172a194055cf5`),
and its `independent-oracle.json` passes 20 (SHA256
`e4ea41a7d50b49cb8e942bcb951d2bc3e6b8ade742843387d2c972865087d74f`).
Both report the current registration state; earlier preactivation receipts remain
intact and are not relabelled as current runs.

Reproduce with `LC_ALL=C` and the restored R library:

```powershell
Rscript tests/platform-gnat.R <fresh-evidence-directory>
Rscript tests/platform-gnat-replay.R <fresh-evidence-directory>
python tests/verify-gnat-core.py <domain-evidence-directory> <new-oracle.json>
Rscript tests/platform-gnat-plots.R <fresh-evidence-directory>
Rscript tests/platform-task-plots.R
Rscript tests/platform-task-plot-timing.R <fresh-evidence-directory>
```

No participant video, biometric model, identity recognition or external hosted
service is involved. The complete researcher/participant/import/cohort/browser
journey and activation decision are qualified separately from this core receipt.
