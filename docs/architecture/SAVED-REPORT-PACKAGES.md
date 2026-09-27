# Saved-report package architecture

27 September 2026. This contract covers the `complete-findings/0.1` contents
profile and `controlled-gaze-explicit-paired/0.1` renderer. Read the
[checkpoint](../qa/PUBLICATION-REPORT-HANDOFF-20260927.md) for executed scope and
[researcher guide](../operations/SHARE-SAVED-FINDINGS.md) for the normal flow.
It advances BWP07/BWP13/BWP15 and PC02/PC05/PC13 without closing them. All 50
registered capabilities and 17 work packages remain in scope.

## Researcher experience

Enter from study Results or an exact saved report. A compatible combined report
can recommend itself and its exact, unambiguous gaze/questionnaire parents.
Unavailable references give a reason; a newer report head is never substituted.
Manual overrides and reopened history retain their saved selection. Every
selected source can be removed even if absent from the current catalog page.

One Prepare action saves an intent before preparing required distributions and
assembling the report. Change contents exposes exact figure selectors, ordering,
image inclusion and identifier choice. The default includes all applicable
supported figures. Unsupported report families or known required scientific
collections remain visible with a reason and their existing export route.

Feedback appears before costly work. Explicit preparation owns completion focus
only until the researcher deliberately changes focus or scrolls. Later passive
opening does not take focus. The ready output subscribes to its reactive resource
URLs before testing the native handle, so first opening actually reveals both
downloads. Form edits immediately invalidate old links.

Navigation/session loss releases UI capabilities and stops further automatic
continuation in that controller; already queued durable jobs keep their lifecycle.
Reopening unfinished preparation reads its state until explicit Resume/Retry.
Cancel detaches the intent and cancels exclusively owned pending dependencies;
shared work needed by another active intent remains. A successful historical
package reopens under current reader policy without repeating scientific work.

## Records and process responsibilities

| Record or component | Responsibility |
| --- | --- |
| Exact reference | `kind`, `id`, `revision`, `body_hash`, `project_id`; used for every saved source, intent, frozen selection and package. |
| `report_package_intent` | Durable request, command idempotency, exact source/section choices, stage, dependencies and next action. Changed contents create a new command and CAS-supersede the exact prior revision. |
| `report_package_selection` | Frozen request plus resolved distribution references, coverage, section bindings and implementation identity. An assembly retry preserves this exact selection. |
| `report_package` | Immutable successful publication linking original selection, job receipt and standalone HTML/ZIP/manifest objects. |
| Views/controller | Bounded catalog/selector reads, feedback, explicit actions, history and session-bound download capabilities. It does not load scientific arrays or reconstruct producer authority. |
| Source/authority backend | Exact source closure, producer/current-reader separation, shared prerequisites, transactional intent transitions, native source holds and atomic publication. |
| Supervised assembler | Projects complete saved results, renders supported figures/tables and builds deterministic payloads. It does not rerun inference/scoring. |
| Archive/raster helpers | Pinned bounded subprocesses for deterministic ZIP and verified PNG/JPEG decoding; no network or undeclared source paths. |

Intent states are `prepared`, `waiting_for_display`, `ready_to_freeze`,
`assembly_queued`, `succeeded`, `needs_authority`, `needs_attention`, `failed`,
`cancelled` and `superseded`. Read reconciliation can record an actual terminal
failure but cannot queue, retry or renew authority. Only the initiating/resumed
live controller advances an available next step. Publication completes the
package, job and intent atomically; stale jobs cannot overwrite a superseded or
cancelled intent.

The parent performs cheap metadata validation before obtaining all original
read seals. Full verification and packed-questionnaire hydration occur under
those holds. A bounded scratch bundle gives the child complete verified sources
without inflating the normal job-input envelope. Current actor/source/intent and
lease/token checks repeat inside publication. Cleanup releases owned resources
on success, refusal, failure or cancellation.

## Maintainer interfaces

The UI calls `brohn_report_package_choices`,
`brohn_report_package_report_choice` and
`brohn_report_package_selector_catalog` for bounded metadata. An exact historical
choice does not require scanning a latest-results page. Catalog rows expose
the exact reference, title, compatible adapters and an unavailable reason;
selector rows carry the saved selector and a human-readable label.

```r
brohn_save_report_package_intent(store, command_id, request,
  expected_revision = NULL, prior_intent_ref = NULL)
brohn_continue_report_package_intent(store, intent_ref, action = "advance")
brohn_cancel_report_package_intent(store, intent_ref)
brohn_read_report_package_intent(store, intent_id, project_id)
brohn_report_package_catalog(store, study_id, project_id, cursor = NULL, limit = 25L)
brohn_open_report_package_resources(store, ref, project_id)
brohn_report_package_resources_current(store, handle)
brohn_release_report_package_resources(handle)
```

Intent readers return the exact intent reference, status, request, dependencies,
selection/job/package references, reason and `next_action`. The latter is one
of `continue`, `wait`, `resume`, `retry`, `review`, `download` or `none`.
Explicit `resume`/`retry` obtains current authorization; passive polling cannot
renew it. Resource opening returns `record`, `handle`, parsed `manifest` and
HTML/ZIP/manifest artifact descriptors. Current checks return a fresh record
and those descriptors; release is idempotent. Server-only paths do not enter
portable manifests or client requests.

Worker integration calls `brohn_report_package_input`, then
`brohn_prepare_report_package_execution` before the supervised child. The
replacement input contains the exact selection/fingerprint, pinned implementation
and a sealed prepared-bundle descriptor capped at 128 MiB. The parent holds
the complete original sources and bundle until publication/cleanup. In the
child, `brohn_analyse_report_package(input, scratch)` delegates to
`brohn_render_report_package(bundle, output_dir)`; the assembler has no store or
authority argument. Its bundle contains the frozen selection, exact original
saved report bodies, verified complete analyses, saved distributions and sealed
asset descriptors. It validates source-bound selectors before projecting labels.

`brohn_publish_report_package` commits the job, package and intent together.
The tagged exact-reference distribution prerequisite has its own source-holding
parent branch and current queued-actor fence. Its generic retry route refuses
and directs the caller through the durable preparation intent, which renews
authority explicitly. Legacy scientific operations retain their existing path.

Backend and source policies live in `R/platform-report-package.R` and its
`-sources`, `-authority` and `-distributions` companions. Pure complete-value
projection and rendering live in `-tables` and `-render`. Controller/views own
UI state and session capabilities. `scripts/workers/report_package_archive.py`
and `report_package_raster.py` are bounded helpers; worker dispatch and load hooks
remain in the shared job/loader/analysis-worker modules.

## Included findings and complete numerical evidence

| Adapter | Selected figures | Numerical coverage |
| --- | --- | --- |
| Gaze context | All exposures or one exact saved exposure; explicit bounded candidate display. | Complete supported saved gaze collections, quality, support, original source row identities and methods. |
| Explicit distributions | All groups or an exact question/scale/typed-condition group; all or selected 20-category pages. | Complete supported answers, revision/scale evidence and distribution collections; packed previews are hydrated from their original complete artifact. |
| Paired findings | All comparisons or an exact comparison/contrast hash; means/differences and all or selected 50-person pages. | Complete saved contrast/person/session evidence, exclusions, uncertainty and multiplicity. No new inference. |

Choosing fewer figure pages never truncates included numerical collections.
Every selected page has a matching numerical alternative. The manifest records
source references, methods, coverage, payload sizes/hashes and omissions chosen
by policy. Known unsupported required parents are rejected through a bounded
exact-reference closure; unknown scientific fields fail rather than disappearing.

Package aliases preserve relationships across source reports. Their namespace
binds kind/project/id/revision/hash, so identical bodies at two revisions remain
distinct. Crosswalks and combined rows join the exact selected original source;
ambiguous unbound references fail. Original opaque scale score IDs remain
consistent between scores and item evidence. Visible Person/Visit labels carry
source context while canonical JSON/CSV and SVG metadata keep exact package
identities. Free text remains verbatim: aliases do not make the package anonymous.
Each section heading names its ordinal, adapter and Source N. The immediate
caption retains the complete saved title and origin, so repeated sections have
distinct accessible names without duplicating long titles in the heading.

HTML summaries disclose non-integer rounding to four significant figures;
integer counts and complete numerical JSON/CSV retain saved values. CSV includes
typed canonical records beside display cells. The self-contained HTML has no
script or external dependency. Its numerical evidence links require an unpacked
ZIP. The ZIP fixes member order and metadata and inventories every payload.
Equal frozen input and implementation/runtime produce equal package bytes;
new selections, policies or implementations are different artifacts.

## Authority, runtime and bounds

Saved reads use the current reader, exact original successful job proof and
current source eligibility. They do not reauthorize the original producer.
Native handles hold immutable files, and GET/HEAD download callbacks recheck
current source/project access and exact descriptors. Newer report heads do not
rewrite history; archived sources or lost access refuse existing capabilities.
These in-app controls cannot revoke already downloaded offline copies.

The profile allows up to 8 reports, 100 expanded panels, 100,000 rows under its
bounded model, 32 MiB HTML and 256 MiB payload; model/bundle, packed questionnaire
and paired questionnaire inputs have separate ceilings. Individual images are
at most 5 MiB and combined images at most 16 MiB. Consult
`brohn_report_package_limits()` for the exact enforced limits. Exceeding a limit
produces a refusal, never an implicit first-page report. Wider capacity is not
qualified by these limits alone.

Assembly uses the configured methods environment with CPython **3.12.10** and
Pillow **12.3.0**, plus the pinned R environment and native publication support.
`scripts/readiness/report-package-runtime.json` contains portable version
requirements; per-job implementation identity still binds actual configured
sources/runtime. There are no model weights for assembly. PNG/JPEG bytes and
saved geometry are checked; unsupported orientation is refused rather than
guessing a transform. Excluded images leave a labelled geometry frame.

The immediate shared follow-up is HTTP-response framing across other saved
explorers and hosted refusals: actual file/SVG success, 403/404, identity/gzip,
zero/nonzero and exact-power byte lengths, and sequential HEAD/GET requests.
The report-specific proof does not establish every inventoried route is broken
or fixed. Preserve each route's source/session/token checks and file ownership;
do not materialize large files merely to answer HEAD or alter global numeric
formatting. Broader report adapters follow this qualification.

The next task adapter must bind exact historical sources and a frozen display
audit. Existing task plots use current-head checks and rebuild delivery-journal
display evidence under current profile rules, so calling them unchanged would
not establish an exact historical, byte-only package. All seven enabled task
profiles, including GNAT and SC-IAT, remain in scope. Choice tasks, physiology,
EEG and camera/media each need their complete numerical/artifact projections;
supported questionnaire scales already belong to this first profile.

Other report families, original/raw-recording bundles, larger profiles, public
sharing operations, post-collection restrictions and backup enforcement remain
separate work. Mobile figure enlargement and shorter display-only table headings
are useful follow-ups. Software checks do not establish device accuracy,
physical synchronization, construct validity or observed human usability.

## Reproduction

[Portable tests](../../tests/REPORT-PACKAGE-REPRODUCE.md) separate pure rendering,
exact alias references, raster/archive boundaries, Shiny spies and simulated DOM.
The [checkpoint](../qa/PUBLICATION-REPORT-HANDOFF-20260927.md) separately records
actual researcher/participant/import/worker/download/history acceptance, native
authority checks and independent full-output review. Source fixtures and stores
containing local qualification evidence are not distributed with the repository.
