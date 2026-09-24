# Continuous EDA source review

This route reviews the original `eda-neurokit-highpass/1.0` report. It reads the complete saved physiology-series and physiology-events artifacts; it does not run cleaning, decomposition, detection or selected-window scoring again. Event-related EDA remains a separate route.

## Scientific and source contract

- The three aligned traces retain saved `clean_us`, `tonic_us` and `phasic_us` in microsiemens. The original source unit, conversion factor, source clock origin, recording/channel/segment and original sample indices remain explicit.
- Candidate peaks use the saved exact `source_peak_sample`. Nonmissing onset and recovery timestamps must match exact retained processed samples. Missing endpoints and their amplitude/timing consequences remain unavailable. Recovery markers identify the saved half-recovery sample; they do not imply an interpolated crossing.
- The saved relative-prominence setting is dimensionless. There is no invented absolute-uS threshold line. These continuous candidates have no stimulus attribution and do not identify emotion.
- Viewport selection uses closed decimal source-time bounds. A candidate is included when the known onset-to-recovery support intersects the viewport; an unavailable endpoint uses its peak only for this intersection rule. Its complete original candidate row and available markers remain in the export even when an endpoint is outside the viewport.
- Solid/dashed traces distinguish retained samples from excluded processing edges. Distinct source segments are selected separately; missing intervals and acquisition gaps are never connected. Short unsupported segments explain their unavailable state.
- Whole-segment features remain unchanged. Complete candidate count, retained duration and conditional-amplitude denominators reconcile with the original saved report. A candidate with missing onset does not acquire a zero amplitude.
- These processed EDA artifacts omit raw conductance samples. The interface says so and directs the researcher to the original dataset download. No raw signal is reconstructed from display previews.
- Original report/dataset revisions, project authority, source bytes, artifacts, origin and optional original study revision are pinned. Native source guards cover worker reading and guarded publication. Session downloads recheck current source authority and selectors; navigation, selection changes or source revocation invalidate old exports.

The numerical recipe is defined by Brohn's retained worker/version and saved parameters. [NeuroKit's EDA documentation](https://neuropsychology.github.io/NeuroKit/functions/eda.html) describes its clean/tonic/phasic outputs and onset, peak, amplitude, rise and recovery features. These software checks do not establish recording-specific physiological validity. [Boucsein et al.'s publication recommendations](https://onlinelibrary.wiley.com/doi/10.1111/j.1469-8986.2012.01384.x) inform the need for explicit acquisition, processing and interpretation evidence; see `MEASUREMENT-ACADEMIC-ACCEPTANCE.md` for the wider qualification boundary.

## Bounded complete outputs

Each review accepts at most 500,000 selected samples and 5,000 selected candidates; it refuses excess rather than truncating scientific exports. It verifies both entire input artifacts, including rows outside the selected window. Each CSV is limited to 128 MiB; the retained review JSON is limited to 24 MiB. Complete numerical exports are `eda-samples.csv`, `eda-candidates.csv` and `eda-markers.csv`.

The on-screen sample table is explicitly the first 50 selected rows. Each trace uses a bounded envelope of actual sample endpoints/extrema, with retained/excluded runs separated; no new interpolated sample values are exported. Up to 50 candidates appear at once, with keyboard-operable candidate paging and exact complete exports. Standalone accessible SVG embeds the exact source/selection/parameters and current candidate page. Source-time labels increase precision as needed; unusually long common origins have an explicit labelled offset and unchanged source coordinates/metadata.

## Evidence, 24 September 2026

Receipts, synthetic recordings, screenshots and generated exports stay outside the repository under `make/work/test-runs/`.

| Layer | Evidence | Result |
|---|---|---|
| Independent native reader oracle | `brohn-eda-continuous-native-20260924-02/results.json` | 14 tests passed; hand-authored complete processed values and nullable candidate endpoints, exact all-row exports, independent sample-position markers, decimal boundaries, whole-segment denominator, zero candidates, corruption/private envelope and bound refusal. No scientific model called. |
| R source contract and SVG | `brohn-eda-continuous-domain-20260924-04/results.json` | 35 checks passed; immutable source binding, request substitutions, exact complete exports, nullable endpoint validation, preserved original report and distinct desktop/mobile/large-origin time labels. |
| Actual import, scoring, review and restart | `brohn-eda-continuous-review-browser-20260924-03/browser-1790229712399/results.json` | 21 connected checks and five clean desktop/390-pixel accessibility, reflow, distinct-axis and text-overlap scans. Seven terminal successful jobs: real source import, scientific analysis and five saved reviews. Independent JSONL decoding verifies every selected sample, candidate and marker; SVG marker geometry agrees with its labelled axes. Original full report and input remain unchanged through a process restart. |
| Maximum candidate population | `brohn-eda-continuous-performance-20260924-01/post-run-verification.json` | An actual supervised/native publication retained all 50,201 selected samples, 5,000 candidates and 15,000 markers; eight original/export objects independently reverified after completion. Job lifecycle: 124.12 seconds. |
| Background verification and exact predicate cache | `brohn-eda-continuous-performance-20260924-02/results.json` | 11 checks on an external copy of that successful publication, with no new scoring or review job. Cold predicate 6.61 seconds, warm predicate 0.08 seconds. Cold open request 3.05 seconds; background verification 44.15 seconds. Reactive test round trips while verification ran: at most 0.05 seconds. No numbers/downloads were exposed before verification; changed values and stale selection were refused. |
| Live authority despite successful predicate cache | `brohn-eda-continuous-authority-20260924-01/results.json` | Four checks: report-owner and dataset-owner substitutions invalidate a previously successful cached result; rollback restores the unchanged original evidence. |
| Final UI-only reopen and visual follow-up | `brohn-eda-continuous-review-browser-20260924-03/visual-1790230937974/results.json` | Reopening the existing gap window focuses its verified result heading within the 390-pixel viewport. Independently captured SVG and DOM bounds confirm all three captions, distinct ticks and source-time label are legible. Exact retained manifest and all seven terminal jobs remain unchanged; no job was submitted. |

Earlier domain runs `-01` through `-03` passed at their respective source versions. `-04` covers the current domain including the isolated predicate cache and background verification helper.

The candidate-bound test uses an independently authored software fixture, not a physiological qualification dataset. It tests the full 5,000-candidate limit at 50,201 samples; it does not claim an actual 500,000-sample memory benchmark. Its first harness completed the real publication and all checks but failed writing its final summary because a `testServer` timing vector was scoped incorrectly. The successful job and all objects remain in `performance-01`; `post-run-verification.json` independently establishes their terminal state. The separate `performance-02` receipt captures fresh timings on copied evidence. The test now captures timings in an explicit shared test environment and closes its store after owned-job cleanup.

Browser attempt `-01` completed the real analysis and first review but its oracle-copy helper incorrectly expected `sha256` on a retained artifact descriptor containing `hash`; its failure is retained. Attempt `-02` passed its connected checks, but manual inspection found repeated Y labels on narrow conductance ranges. The final `-03` source fixes vector tick labels, explicit large-origin offsets and history labels containing exact bounds plus saved time. Its full source fingerprints are in the receipt. The current domain/native readers did not change the scientific scoring recipe.

The final follow-up changes only the view module: after successful background verification, reopening focuses a focusable result heading through the existing application focus handler. The earlier full journey has UI SHA `f67d69b2922b366c2ead570cba2c7d992d362df1c4b497560bac4f2d1adf9a93`; the focused follow-up covers final UI SHA `5d01e02f4c31d9c1b1deff8ad9f9bfcafd1fc570ee98039385da28c88ced474a`. Domain SHA `c30a83791d0adf3c8437637e615cd155d67879f26e8037b0aeeb093809ec56c6` and reader SHA `62907d9532cb91701815db7940f334c9ccc2339f574c647cd6140619a100b0eb` remain unchanged. Full application loading also passed under `LC_ALL=C` after this change.

An initial element screenshot omitted two captions despite their presence in the full-page capture; a fresh element capture and inspected final image confirm a capture-paint artifact, not clipped SVG source. The first visual replay's summary overstated viewport visibility: its recorded chart bounds were offscreen, although all captions were within the SVG. That original receipt is retained, superseded by the final focused receipt above. Intermediate attempts at an exact whole-SVG viewport assertion also failed; final evidence separates the automatically focused heading from the complete element capture. It does not claim that the heading and entire tall three-panel chart fit together in one phone viewport.

Verification uses a maximum eight-key cache of successful pure predicates, keyed by the complete exact R result/input and loaded validator identity. Source authority and native guards are never cached. First numerical verification and full byte/envelope checks run in a supervised R child; adoption rechecks source, selectors and guards. An R-serialized binary SHA is used only for ephemeral UI history commands and same-session body comparisons. Saved interoperable report/request/provenance hashes retain their existing canonical contract.

The history panel exposes the latest 40 saved windows for the selected report. Each entry identifies its exact source-time bounds and saved date.

## Reproduction

Run from the repository with its provisioned R library, native publication guard and Python profiles configured:

```text
python tests/workers/eda_continuous_review.py -v
Rscript tests/platform-eda-continuous-review.R <new-external-receipt-directory>
Rscript tests/fixtures/researcher-eda-continuous-review.R setup <new-brohn-eda-continuous-review-browser-directory>
node tests/researcher-eda-continuous-review.mjs <same-browser-directory>
Rscript tests/platform-eda-continuous-performance.R <new-external-performance-directory>
Rscript tests/platform-eda-continuous-authority.R <accepted-performance-directory> <new-external-authority-directory>
```

The browser fixture must use a fresh external directory. It creates only original synthetic conductance, imports through the real transfer review and mapping form, and starts/stops its own server/worker. Its default port is 3933; `BROHN_EDA_CONTINUOUS_REVIEW_TEST_PORT` can override this during setup. No participant data or downloaded media are needed. Live hardware, electrode quality and labelled physiological validity are outside this software acceptance.
