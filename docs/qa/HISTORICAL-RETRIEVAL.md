# Historical research retrieval contract

Older research must remain reachable as unrelated work accumulates. Filter by
the actual study or dataset and its project **before** applying a page bound.
A global recent-record limit followed by an R filter is insufficient. Related
lists report their full scoped total and use forty-row Next/Previous controls.
Each command carries the visible parent, relation and current offset; a command
from another study, dataset, stage or previous page must not move the current list.

The independent fixture is
[`tests/fixtures/researcher-history-fixture.R`](../../tests/fixtures/researcher-history-fixture.R).
It creates an isolated original catalog with:

- 43 target datasets and 43 target reports attached to its oldest dataset;
- 510 newer unrelated datasets and reports;
- one old matching cancelled processing attempt followed by 110 unrelated attempts;
- deliberate same-parent references in another project, which must be excluded;
- an empty study, two retained earlier design revisions and a tiny original CSV.

These saved report bodies are explicitly marked as catalog fixtures. No
participant or scientific computation is claimed. The old global500/100 retrieval
provably omits the target records. Parent-scoped retrieval returns exact source
IDs in independently inserted reverse chronology, with forty and three rows.
The fixture passes **14 backend assertions**, including stale/cross-parent command
rejection, foreign-project exclusion and immutable report-body identity.

[`tests/researcher-history-pages.mjs`](../../tests/researcher-history-pages.mjs)
passes **21 actual-browser assertions** with three clear narrow accessibility
scans. It exercises Review, Results and History pagination, the oldest report's
full JSON, an earlier frozen design revision, an unrelated and an empty study,
and dataset-specific report/processing history. Old page events are replayed
through the real Shiny connection and rejected. The complete original CSV hash
remains identical, a fresh researcher session reaches the oldest report again,
and a readonly backend reopening confirms the original counts and hashes.

Evidence: `work/test-runs/brohn-history-pages-1788846680547/browser-evidence` and
its sibling `backend-results.json`/`fixture.json`. The harness launches only its
owned isolated Shiny process; it does not use participant services or scientific
workers. A Windows interpreter-launcher cleanup issue in the harness was corrected
by using the direct interpreter and a graceful stop request.

The [selector extension](../../tests/researcher-history-selectors.mjs), with its
[independent fixture](../../tests/fixtures/researcher-history-selectors.R), adds
510 newer study bodies and passes **16 actual-browser assertions** with three
clear accessibility scans. Server-side search finds the older archived study
and excludes another project's study. An actual accepted mapping retains its
selected study revision and original source hash after reopening; it does not
restore or change the archived design. The automatically requested analysis is
explicitly cancelled, and no worker or scientific result is claimed. A late
prior-dataset save event cannot alter the newly opened source.

The combined-measures picker retrieves both exact oldest report IDs despite the
newer unrelated reports. Actual server search responses exclude unrelated and
foreign-project sources. Both selections reach the real source review, which
correctly shows zero participant identities for these original catalog fixtures.
Cancel leaves the protected dataset and job count unchanged. Testing the open
multi-select found a missing `aria-controls` attribute; the shared frontend fix
now links each combobox to its actual live listbox. Desktop and 390-pixel scans
pass with the dropdown open, and keyboard Escape preserves both selections.
Evidence is under
`work/test-runs/brohn-history-pages-selectors-z1jO5u/selector-evidence`.

## Adjacent retrieval paths identified by the audit

These were observed during the initial audit and should use the same parent-first
query contract. A fix in the main Review/Results lists alone does not establish
coverage for every row below; their own regression evidence must be retained.

| Path | Failure caused by a global bound | Expected behavior |
| --- | --- | --- |
| `platform-multimodal-views.R` report picker | An old study cannot select its reports for combination | Query that study/project first; retain all pages or a searchable picker |
| `brohn_studies()` in Data/interchange mapping | An old study cannot be linked even when the main library can find it | Search/filter before limiting, including retained archived study references |
| Dataset/header/camera/interchange/curation/AOI progress leaves | An old source's attempt vanishes behind 100 unrelated jobs | Query the exact source/job operation before limiting |
| Header inspections | A retained native header appears missing | Query dataset/source identity before limiting |
| Acquisitions and discovery history | An old study loses its acquisition decision or review route | Query the study or explicit discovery identity first |
| Stream imports, streams and curations | An old recording loses its source stream or curation history | Query dataset/import/stream relationships before limiting |
| AOI proposals | An old study loses its saved proposal and review evidence | Query the owning study/project first |
| Legacy migrations | Earlier imported artifacts disappear from study History | Query the study/project before limiting; preserve artifact hashes |

This is automated synthetic software evidence, not observed human usability,
physical-device qualification or scientific-method validation.
