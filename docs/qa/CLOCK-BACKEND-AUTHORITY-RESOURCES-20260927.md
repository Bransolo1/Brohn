# Clock backend, authority and saved-resource evidence

Evidence consolidated on 27 September 2026. This document is a sanitized
acceptance summary for repository publication. It contains no research stores,
identity-provider credentials, protected profiles or raw session/job fixtures.

The accepted implementation spans original marker selection, reviewed exact
clock maps, complete saved-row windows, a separate complete-export display job
and guarded access to saved resources. It is an external integration candidate
relative to production commit `28bc168c9f0e333dfa7be9d56dcf8ab7462a38b8`.
Production enablement and connected browser acceptance require the final joined
installation; this summary does not assert that those steps have happened.

## Behavior covered

Two original imported recordings retain their own clock, marker stream and one
or two selected scalar signal channels. Researchers choose two defining event
pairs and may retain up to 16 independent held-out pairs. Original event sequence,
timestamp token, value and identity survive selection. Repeated labels are
different rows; matching labels do not automatically establish event equivalence.

The reviewed map uses exact affine arithmetic over its supported defining-anchor
span. Saved windows preserve exact source coordinates and original values,
use a reference-relative half-open interval, and publish four complete artifacts:
selected rows, all unplaced original rows, complete original segment evidence
and a mapping manifest. Empty windows retain complete source counts. The
numerical table is a bounded page; it is not the complete plot input.

The separate `clock_plot` operation reads all four original saved exports.
It prepares an extrema-preserving display with separate signal/event lanes,
exact row references, continuity breaks, complete coverage counts and bounded
display projections. The full plot is retained as a portable JSON artifact.
It does not refit the clock map, infer missing timestamps, resample scientific
data or produce new scientific scores.

Five server-side operations capture original verified queue authority:
`clock_event_page`, `preview_clock_alignment`, `save_clock_map`, `clock_window`
and `clock_plot`. The authority envelope contains scoped non-secret identity
and session/profile references. Execution and final publication reread current
protected policy and refuse expired/revoked actors, removed/replaced policy,
cross-workspace/project scope or a lost job lease. An explicit retry retains the
original command but creates a new job with renewed authority. Uncertain named
map-save acknowledgement retains the original operation/job identity.

Historical access instead validates the current reader, exact original source
membership, current project/archive state, retained publication and original
successful job proof. Later expiry or revocation of the producer does not erase
a valid result for an authorized current reader.

Resource handles hold native Windows read seals. In the qualified one-signal
per-recording fixture, a saved window has 19 distinct original/map/preview,
window-document and export objects. The plot borrows that active window handle
and adds two owned seals for its plot and publication document. All required
seals exist before full byte verification. Subsequent deliveries recheck fresh
authority and original proof without rehashing already sealed files. Plot
release is idempotent and does not close its borrowed window; closing the
window immediately invalidates plot delivery.

## Separate qualification phases

Counts below belong to distinct source phases and fixtures. They are not summed
into one whole-product pass, and earlier checks are not relabelled as reruns of
later source versions.

| Phase | Accepted checks | Evidence and limit |
| --- | ---: | --- |
| Original marker-page backend | 26 actual-path checks + 10 restart + 23 authority faults + 11 CLI + 16 R/support | Five genuine new page jobs reuse two original imports; separate support fixtures are labelled. |
| Background named map saves | 20 actual/fault + 8 restart | Real separate workers, atomic map/job completion, versioning, lost acknowledgement, cancellation/rollback/retry; local backend phase. Two explicitly synthetic new imports qualify optional condition/exposure fields. |
| Saved original-row windows | 31 actual + 7 restart + 18 guard/cancel/retry | Three genuine window jobs over accepted map versions. |
| Window bounded-reader hardening | 23 component + 8 focused integration | Wrapper-only source change; old windows reopen and one new job retains identical artifacts. Earlier cancellation checks were not rerun after that bounded-reader change. |
| Four-operation authority integration, accepted checkout-05 | 29 completed checks before a retained harness stop + 21 continuation + 9 fresh-process | Real local/hosted jobs; all four operations refuse revoked actors before work and inside publication. The first phase did not finish as a whole. |
| Original-event selection bridge on accepted05 | 10 | Two additional genuine page jobs retain three selectable original markers for each recording. Final bridge fixture has 25 terminal jobs. |
| Saved-window process-local resources | 26 | All 19 fixture objects sealed before their first hashes; independent writer exclusion, current-reader/source/job checks, cleanup and idempotent release. |
| Complete plot component and CLI | 25 component + 14 CLI | Large 6,700-row, exact-coordinate, gap, later-extreme, display-bound and R-roundtrip fixtures. This is complete-export component evidence, separate from imported-window integration. |
| Fifth-operation plot adapter, checkout-07 | 24 actual/guard + 8 fresh-process | Seven new display attempts: four successes, two controlled actor failures, one cancellation. Four exact saved plots reopen. No scientific jobs or new imports. |
| Plot discovery and resources | 31 | Exact-window lookup, borrowed-window identity, two new seals before hashing/parsing, fresh reader/source/job refusal, independent writer exclusion, partial/corrupt-open cleanup and lifetime checks. No new jobs. |

The independent earlier 67-check queue-authority helper is supporting component
evidence, not another run of the integrated worker. Accepted05 has four
operations. Checkout07 extends the operation inventory to five and qualifies
the real plot route; it does not claim all earlier four-operation fault cases
were rerun under checkout07.

## Retained failures and corrections

The marker-page worker initially returned correct original participant/session
identity without optional condition/exposure fields; the first R validator
incorrectly required those optional fields. The corrected source preserves
absence and accepts declared optional fields without inventing them. A later
support test added two empty hosted-policy tables to an accepted catalog: its
logical research/job records stayed exact, but whole-catalog byte equality is
explicitly not claimed after that phase. Subsequent support uses fresh copies.

Initial map/window launchers omitted an explicit Python runtime setting and
were corrected on fresh copies. The first window publisher also refused an
incorrect artifact directory; it was corrected to the owned attempt's standard
artifact directory. A cancellation fixture originally expected retry to reuse
a job ID; the corrected expectation preserves the platform's fresh-job retry.

The first integrated late-revocation harness attempted a guarded job read after
revoking the actor but before saving its diagnostic. Access was correctly
refused. Its store and failure remain retained. Only diagnostic ordering changed
for the successful stopped-copy continuation; application source did not change.

The first saved-window resource attempt exposed assignment through a locked
handle binding. Release now mutates a separately referenced state environment.
The next test did not distinguish native write exclusion from the copied
objects' ordinary read-only attributes. The accepted disposable-copy test
removes/restores those attributes and independently probes access before and
after releasing native seals.

The first real plot adapter child exposed a cross-language display-summary
boundary: Python JSON `0.0` and `1.0` become `0` and `1` after R serialization.
The revised checker accepts exact finite numeric equivalence in the small
summary while keeping booleans and exact strings distinct. Complete plot bytes,
artifact SHA/size and source bindings remain exact. A real R roundtrip and
malformed-value refusals passed before checkout07 was created.

The first checkout07 plot was successfully published before two test-harness
defects stopped later assertions: list field-order comparison and a locally
shadowed hash spy. The corrected continuation reused that exact successful job
and its actual worker receipt; it did not replace or rerun it. The final plot
resource fixture retains a separate initial parse-only harness failure. No
failed attempt is silently promoted to a completed phase.

## Preservation and evidence identities

Every phase identifies its copied source and retains failed attempts. The
accepted05 hosted continuation preserves inherited successful and failed jobs;
its selection bridge adds only two marker-page jobs. The plot adapter retains
all 25 bridge jobs and adds seven display attempts. The resource phase retains
all 32 resulting jobs and adds none. Existing reports, original window exports
and source bytes remain unchanged.

The accepted plot adapter verifies all 189 files in its original bridge source
workspace and all 1,221 external checkout files. The plot-resource phase verifies
all 246 files in its original adapter workspace and the same 1,221 application
files. These exact local byte identities do not automatically apply to another
clone with different line endings.

Sanitized phase identifiers (raw evidence stays outside the public repository):

| Evidence | SHA-256 |
| --- | --- |
| Original event backend joined receipt | `7294cd34eab23da0e9e0676a623829f9af2ba6dd3e04f8b5d9d412e195e343f3` |
| Map-save backend joined receipt | `53313f39dc115e7272c65584e6de0a7390fcfb35477eeba0d7291a3e2b61fabc` |
| Saved-window backend joined receipt | `c691dcf5afdf68fd242d99927ff201879d7cfda93cf5b37c9347077032343a59` |
| Accepted05 authority/bridge joined receipt | `9e24c9710b4b0b2203a4206e488ae51dfd4aa59879a9dd97275dd14bc18b7209` |
| Saved-window resource receipt | `33b8a5da82130c7c6bc61cefefdd926cb9a656bbb25db84a59b40083f1d60679` |
| Complete plot component/CLI joined receipt | `5cb24c0f07a319a44149ea1015cc21abe718f6e9224b415ada0c5ce4289155d0` |
| Checkout07 plot adapter joined receipt | `b31e3a17d1260ad7185d9306d1ba03add4ef83c8135c1436ee345682457970f2` |
| Plot-resource receipt | `0cca02888b28efc70f51531cb253dcb440c84c2408b308b634e148f7dd1b50a6` |

The exact new source inventory is maintained separately in
`CLOCK-BACKEND-INVENTORY.json` and its readable companion. It identifies 21 new
backend/resource/plot files and three existing loader/coordinator/worker files
that require merging clock hooks into current production behavior. It excludes
the separately owned researcher UI/catalog/selection/controller modules.

## Explicit boundaries

These fixtures use original imports of deliberately synthetic recordings, real
local supervised workers and synthetic verified-edge researcher contexts. They
do not establish real participant/device synchronization accuracy, the current
user's hardware behavior, clinical or psychological construct validity,
physical acquisition timing, a live OIDC login, reverse proxy, TLS deployment,
or protection against an arbitrary privileged database administrator.

The qualified native resource/publication seals are Windows-specific. A Linux
or macOS implementation needs equivalent platform evidence. Prepared runtime
recipes and retained fixture stores are not a clean-machine installation test.
Backend durations are not keyboard/mobile responsiveness measurements.

The reviewed affine map still reports physical synchronization as not
established and timing uncertainty as unknown. Held-out residuals are fit
evidence, not physical timing uncertainty. Complete plot preparation is bounded
display reduction; original exports remain authoritative and available when a
fragmented/oversized plot is refused.

Connected researcher flow, accessible renderer behavior, saved-history reuse,
active-session URL capabilities, stale-download refusal, low-click operation
and browser restart must be evidenced separately against the final joined
checkout. This document does not mark the full Brohn platform or its 17-package
build manifest complete.
