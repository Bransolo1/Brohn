# Paired results: complete source review

Brohn now connects existing saved gaze, quantitative explicit-response, assessment-scale and multimodal condition comparisons to paired-person figures and exact numerical evidence. This is a read-only review of an existing result. It does not add a hypothesis, recalculate its uncertainty, infer participant linkage or synchronize sensors.

## Researcher workflow

Open a saved study's Results, open its report, then choose **Open paired results**. Select a source measure and one of its already saved condition comparisons, then **Review paired observations**. Complete evidence is verified and prepared in a supervised background R process. Researchers can cancel preparation or navigate elsewhere while it runs.

The review includes:

- Paired control/test means: equal eligible observations within each condition and visit, then equal paired visits within each person, matching the saved method.
- Person differences alongside the full saved estimate and any saved 95% interval. Existing p-values and family correction remain unchanged. An interval is never added when the saved result has none.
- Separate numerical tables for people, visits including unpaired visits, and complete selected source observations. Tables and figures have bounded pages of 50 records. Full CSV and JSON downloads retain every selected record and original typed source fields.
- Accessible SVG figures with exact source/report hashes, condition comparison, page, person records, units and saved uncertainty embedded in metadata. The two figures share complete-comparison bounds across pages.
- Explicit unavailability when original identities, scoring keys, complete observations or saved person differences are missing or contradictory. A table preview cannot become a paired source.

The people table uses round-trip double-precision strings rather than the general report table's six-digit display. The CSV escapes spreadsheet formula-like identifiers while retaining the exact original source record in structured fields. Missing observations remain unavailable; another condition is explicitly outside the selected comparison. Distinct modalities keep their own units and eligible people.

## Source and lifecycle controls

The original result envelope, exact saved study design, report revision, project ownership and complete artifact are verified before opening. For packed questionnaires, the full typed artifact is hydrated and compared with the compact preview's source binding. Reconstructed session means must reproduce the saved person differences, person/visit counts and estimate. Combined results additionally verify their saved session differences and contributing row counts. Scale comparisons verify the saved scoring keys and assessment-source evidence.

Every interaction rechecks current report/project authority and retained source objects. Changing a measure or condition clears its preceding plot and cancels any pending preparation. Leaving the report kills the owned process. Download links carry the exact opening token; old links return 404 after replacement and cannot serve a later selection. CSV and JSON are prepared off-session and streamed from private temporary files. Temporary files are removed only after checking their absolute directory is the owned paired-review directory.

Explicit resource profiles are 12 MiB for complete questionnaire artifact hydration, 100,000 source or scale observations, 128 MiB serialized preparation input/result, 256 MiB per prepared CSV/JSON export, and five minutes per preparation. These are guardrails, not demonstrated maximum-capacity claims. Exceeding a profile produces a reason and preserves the original complete source.

An initial 3,000-observation reconstruction took 5.65 seconds in the foreground on the development host. That finding caused preparation to be moved off the Shiny event loop. Browser acceptance measures actual cancellation/navigation latency separately from background completion time.

## Independent checks

`tests/platform-paired-plots.R` passes 32 checks. Its original fixture has P1 visit differences of 2 and 6, yielding person difference 4; P2 and P3 contribute 8 and 12. The equal-person estimate is 8, whereas pooling the four visits gives 7. P4 has no test response and remains unpaired. A second saved condition comparison has estimate 13.

The checks cover repeat weighting, equal paired-visit means, complete missingness, exact saved uncertainty, declared multiplicity, scale keys, gaze units, reviewed multimodal linkage, conflicting source values, duplicate exposure identities, absent person/exposure identities, inconsistent saved visit counts, pagination beyond 50 people, SVG metadata, full CSV precision, formula escaping, complete questionnaire artifacts beyond their one-row preview, altered previews, oversize-artifact refusal before decoding, supervised preparation, private cleanup, newer report revisions and archived projects.

The browser harness is `tests/researcher-paired-results.mjs`. Its fixture creates original synthetic CSVs and uses actual analysis workers for explicit responses, gaze and their reviewed combined comparison. Optional `seed-stress` adds a 1,000-person/3,000-observation actual-worker report to exercise paging, cancellation and navigation during preparation. Evidence files, screenshots, complete exports and logs remain outside the repository.

Final connected browser acceptance on 24 September 2026 passed **28 checks and five accessibility/reflow scans**. `tests/paired_export_review.py` independently passed **13 XML/CSV checks**, including actual SVG endpoint distances, uncertainty geometry against the df=2 closed form, complete source coverage, and the exact 50 people on page 2 of the 1,000-person report.

The researcher journey exercised both source measures, alternative saved conditions, complete exports, keyboard table scrolling at 390px, stale-link 404 responses before and after replacement, background cancellation, navigation during preparation, pagination, and service restart/reopen. All four actual worker reports remained byte-identity unchanged and no scientific jobs were created by review/export. The final explicit and combined mobile captures and standalone exported means figure were visually inspected; the desktop figure and table were also inspected. The people table was corrected to follow the figure page, then the whole journey was repeated.

Final external evidence directory: `make/work/test-runs/brohn-paired-browser-20260924-01/browser-1790219369521`. Earlier attempt directories are preserved. Two screenshot-selector harness failures and a stale-link response issue preceded the accepted route. The older accepted browser receipt `browser-1790219155556` was superseded after the figure/table paging correction.

| Receipt | SHA-256 |
| --- | --- |
| `acceptance.json` | `36a48d6d34d554b78f8950279158ee40fd39f5768501c03d3f9d71f8d8cbacc0` |
| `independent-export-review.json` | `3e3b531131312693548435880f199c7e69606013bb5971e11d0f957637435af0` |

On this host, small-source paired preparation took 1.90-2.44 seconds including child startup and UI delivery. Full 1,000-person/3,000-observation preparation and complete export generation took 18.21 seconds in the background. Keyboard cancellation took 150 ms and navigation during preparation took 233 ms. The preceding scientific questionnaire worker needed approximately 190 seconds to create its original report; that existing scorer cost is distinct from this review layer and remains an optimization target. These measurements qualify this fixture, not the 100,000-observation maximum profile.

## Reproduce

Use Brohn's restored R dependencies and registered publication runtime. Run from the repository root. Pick a fresh external directory whose name starts with `brohn-paired-browser-`, and a free port through `BROHN_PAIRED_TEST_PORT` (default 3891).

```text
Rscript tests/platform-paired-plots.R
Rscript tests/fixtures/researcher-paired-results.R setup <external-directory>
Rscript tests/fixtures/researcher-paired-results.R seed <external-directory>
Rscript tests/fixtures/researcher-paired-results.R seed-stress <external-directory>
node tests/researcher-paired-results.mjs <external-directory>
python tests/paired_export_review.py <completed-browser-evidence-directory>
```

The directory must already exist and contain no fixture/workspace. Setup and seed do not use external participant data. The browser harness starts and stops only its owned researcher service. It does not enqueue scientific analyses during plot review. Preserve failed browser attempts; subsequent attempts create distinct evidence folders.

## Limits

Synthetic arithmetic and browser acceptance establish implementation behavior, not instrument validity or physical device timing. Person aliases remain declared or explicitly reviewed identities. The control/test lines are condition summaries for a person, not synchronized recordings. Inline historical methods retain their own saved statistical policy, including any legacy interval behavior; this visual layer does not silently revise it. Large sources beyond the stated profile require a future indexed preparation adapter and are explicitly unavailable here.
