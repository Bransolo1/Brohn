# Cardiac exclusions: independent curated-source acceptance

Date: 20 September 2026. **Worker source association and R publication/authority acceptance, using original synthetic PPG.** This does not qualify physical acquisition, detector accuracy, NN intervals or artifact-label accuracy. Production files were not changed by this review.

## Executed route

`tests/workers/cardiac_review_curation.py` generates a canonical acquisition journal, calls the actual `stream_extract.extract()` implementation, runs the actual original PPG physiology analysis on its derived CSV, and calls the current cardiac exclusion worker against that report's complete input artifact and the extractor's complete decisions artifact. It does not substitute a hand-written derived CSV for the extractor output.

The original fixture contains 8,009 acquisition rows at a declared 100 Hz, two explicit people/sessions and device-clock identities, and seven explicitly missing sample rows. The extractor retains all 8,009 decisions and produces 8,002 derived rows. A short intermediate segment stays separate. The selected continuous table belongs to `person-β` / `visit-b` and contains 5,902 samples, occupying derived rows `[2100, 8002)`.

Derived row 2100 maps to **original one-based acquisition sequence 2107**, with exact source timestamp `1000000000001029999123` ns. These indices are deliberately different. Displayed analysis time remains seconds relative to the derived continuous segment; it is not relabelled as the acquisition clock. The first reviewed exclusion `[4100, 4400)` resolves to 300 samples with observed relative times 20 through 22.99 seconds.

## Results

**11 tests passed in 13.204 seconds** against the final worker after R integration, including the following independent checks and adversarial cases. The earlier isolated pass (15.117 seconds) remains retained separately.

- Every generated acquisition decision and each explicitly omitted source sequence reconcile with the original generator inputs. Every included derived row retains its source sequence, exact timestamp and original person/session identity.
- Preview and saved ledger endpoints match the independently indexed original acquisition rows, including the large decimal clock and source clock/segment IDs.
- Sixty-four disjoint spans retain exactly 130 requested endpoint records. The worker verifies all 8,002 included rows without retaining a full crosswalk in the preview result.
- Actual PPG recalculation produces exactly the surviving global derived indices `[2100, 4100)` and `[4400, 8002)`. Original converted input values and relative times remain exact. Both event tables start with a null previous interval; no interval crosses the exclusion. Both tables remain bound to the selected person and session; NN confirmation stays false.
- Changed decision bytes reject against the original pinned size/hash. Separately rehashed included-decision substitutions of person, clock, timestamp, timestamp unit, acquisition segment or derived segment also reject against the CSV.
- Missing interior decisions, swapped source order, hiding an included row, truncating included coverage, and truncating the originally pinned excluded tail reject.
- A decision file modified at end-of-read rejects before a result is returned.
- Another person and source bounds outside the selected continuous table reject. Original CSV/decision bytes and the inspected worker source files remain unchanged.

The row/time/value oracles come from the original generator and independently enumerated source membership. Detection is used to exercise the real output pipeline; matching output is not evidence of physiological validity.

## Reproduction and retained evidence

Set `BROHN_TEST_OUTPUT` to an external evidence directory, then run the installed methods Python against `tests/workers/cardiac_review_curation.py` from the repository root. With that variable absent, the test uses and cleans an isolated temporary directory.

This run is retained at:

`C:/Users/User/Documents/Codex/2026-09-20/oka/work/cardiac-review-curation-8rjlaikg`

It contains `acceptance.json`, exact worker source hashes, original canonical rows, extraction request/result, actual derived CSV and decisions, parent request/result and complete artifacts, cardiac request, accepted preview/reanalysis results, and separately named tamper fixtures. No generated acquisition data were added to the repository. The acceptance receipt records all test failures/errors; both lists are empty. The earlier pass is retained at `.../work/cardiac-review-curation-tjueln69`.

The adjacent independent direct-CSV review remains distinct: six nonzero-index/second-person coordinate checks and seven exact detector-environment checks are retained in `.../work/cardiac-review-peer-01` and `.../work/cardiac-review-engine-peer-02`. Those environment substitutions simulate historical metadata, not execution of historical package binaries.

## Actual R authority and publication acceptance

`tests/platform-cardiac-review-curation.R` passed **24 checks across eight supervised jobs** in a fresh owned workspace. Seven jobs succeeded and one publication was intentionally refused after authority revocation. The final retry succeeded. Evidence, immutable original/derived objects, reports and the full job history are retained at:

`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-cardiac-curation-domain-02`

`acceptance.json` records each assertion and job outcome; `progress.json` records `completed: true`. All test-owned R, Python and store handles closed. The route starts with an original multistream JSON bundle, then runs real import, extraction, original PPG analysis, complete catalog, review preview, separate exclusion analysis, deliberately refused preview and exact retry. It does not register the Python fixture's synthetic descriptors as authenticated source entities.

Reproduce from the repository root with the configured native R and restored libraries: run `tests/platform-cardiac-review-curation.R` with a fresh external output directory whose basename begins `brohn-cardiac-curation-` to retain evidence. With no argument, the permanent QA runner uses a fresh R session-temporary directory outside the repository; R removes that temporary evidence on session exit. The test generates its own source and needs no public dataset or prior workspace. The optional-output adjustment was parse-checked after the accepted run; no scientific or assertion logic changed.

The checks establish:

- The actual R importer/extractor accounts for 8,009 acquisition rows, seven omitted rows and 8,002 derived rows. The selected catalog table preserves the second person's identity and exact nonzero source bounds. Its authenticated preview preserves the independently specified acquisition sequence, nanosecond timestamp and clock described above.
- All seven distinct guarded original/derived/parent objects permit a non-mutating `r+b` open **before** processing. The test removes ordinary read-only attributes in its isolated workspace before this control. The same opens fail with `PermissionError` during actual parent-held publication, and succeed again after the job returns. All source hashes remain exact. This distinguishes native sharing exclusion from ordinary read-only file permissions and confirms guard release.
- Moving the current stream, import, original dataset, curation, derived dataset, parent report, catalog, review or accepted preview to another project independently refuses the frozen job input. Each of these nine mutations is rolled back in an isolated transaction.
- The real recalculated report retains the exact accepted preview ledger and surviving global derived ranges `[2100, 4100)` and `[4400, 8002)`, with NN confirmation false. A later review revision cannot reuse an earlier preview to authorize new bounds.
- Moving the original stream to a foreign project **after native output preparation, before the final transaction** fails with the specific curation-lineage/project error. No preview entity, result-object registration or completion receipt appears. Restoring authority allows the exact frozen retry.
- Same-size changes to the original canonical acquisition artifact and full decisions artifact reject before queueing. The fixture restores their exact bytes and ordinary read-only attributes. The original parent report, all source objects, saved review and separate new report remain unchanged and reopen successfully.

The initial `.../work/brohn-cardiac-curation-domain-01` run is retained. Its eight jobs and authority/retry checks completed, but its corruption setup stopped when opening an ordinarily read-only object for writing. No corruption was written. Review of that failure also identified the missing outside-guard control in the first write-denial probe. The final `-02` run corrects the test setup and demonstrates the guard lifecycle explicitly; the initial denial alone is not counted as native-seal evidence.

## Reviewed authority boundary and remaining limits

The standalone Python tests supply an explicitly synthetic curation identity/hash; they do not create authenticated R entities. The worker verifies the descriptor it receives and the complete included decision-to-CSV association. The separate R suite above tests the binding to the saved curation, original source/import/dataset entities, canonical and decisions artifacts, project authority, exact review revision and accepted preview.

Read-only review of `R/platform-cardiac-review.R` and its job/publication hooks found no additional concrete defect in the tested scope. Frozen lineage body hashes agree with the original curation construction. Native read guards cover the CSV, complete parent series and every curation source object before the child starts; the input is reverified after handles are acquired. Direct publication independently acquires guards. The final authority callback runs inside the store's immediate writer transaction before result registration and completion. The native guard checks both the held file and its current path identity.

Decision-byte verification in the Python worker occurs before and after crosswalk reading. A newly supplied, self-consistent descriptor is not authenticated by that worker alone; the R authority/seal boundary remains essential. These are bounded Windows source, row, identity and publication tests. They do not evaluate researcher artifact-label accuracy, scientific guard sufficiency, detector performance, clinical interpretation or physical recording quality.

The governing scientific boundaries and outstanding physical/reference qualifications remain in [the source-exclusion contract](../methods/CARDIAC-ARTIFACT-REANALYSIS-CONTRACT.md).
