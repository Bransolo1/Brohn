# Saved facial observations and exact recorded pixels

Status: qualified as a connected saved-result review slice. Worker checks, guarded publication, actual researcher navigation, downloads, mobile/desktop accessibility and restart passed with the explicitly joined evidence below. This is a bounded saved-result review feature, not a model-validity, hardware or deployment sign-off.

## Delivered contract

`facial_review` builds a sealed derived SQLite index from both COMPLETE native JSONL and face-wise CSV artifacts. It cross-checks every retained frame, original numeric token, integer/rational PTS, eligibility state, original summary and saved source binding. The preview is a consistency check only. The original report, its permission and camera authority, native artifacts and recording stay immutable.

The researcher chooses a native AU/category, exact recording-relative decimal bounds and a recording time. The view contains original eligible values, explicit no-face/multiple-face/incomplete-output states, and gaps. Connections follow only adjacent supported samples under the original gap rule; no face identity is established. Selecting a time prepares/reuses its exact recorded frame in the background. Full original frame JSON, selected CSV plus source manifest, image PNG and a labelled figure are downloadable. Complete original artifacts remain available from the report.

`facial_frame` checks the complete original FFprobe ledger and the saved decoder manifest/version, then sequentially decodes the original frame without seeking, rotation, crop or resize. The decoded RGB must equal the SHA-256 saved during original inference. Shared `media_pixels.py` writes a lossless RGB PNG. Viewing needs the original pinned FFmpeg runtime, not Py-Feat or model weights. All original source objects and derived results are held and revalidated across processing/publication/open/read/download. Camera withdrawal and current project authority still apply.

## Accepted evidence

All paths below are external local evidence beneath `work/test-runs/` in the outer workspace; original recordings and runtime assets are not committed.

| Evidence | Result | Scope |
| --- | --- | --- |
| `brohn-facial-review-contract-20260924-02/results.json` | 17 groups passed | Explicitly hand-authored 61-frame native-shaped contract data: beyond-preview paging, all 27 fields, exact decimal membership, missing/multiple/invalid states, gap, complete/empty CSV and corruption refusals. Not native-model evidence. |
| `brohn-facial-review-reference-20260924-02/results.json` | 11 groups passed | Original six-frame actual native mixed-state result; all 27 series equal original numeric tokens; all six 640x454 PNGs independently decode to the original saved RGB hashes and integer PTS; full seven-row export and unchanged originals. No inference rerun. |
| `brohn-facial-review-domain-20260924-02/results.json` | 14 current continuation groups passed | Actual R guarded publication, original-source binding, exact decimals, complete frame/CSV, stale and closed contexts, original data unchanged. Reuses the original historical sealed index after the helper repair and queues only one new exact-frame job. |
| `brohn-facial-review-authority-20260924-01/results.json` | 5 groups passed | Actual copied original named-consent camera report preserves every original authority/source ref; rollback-only receipt mismatch is refused; original rows/triggers/bytes restored. No participant event invented, jobs or inference run. |
| `brohn-facial-review-browser-20260924-02/acceptance.json` | 33 successful groups and 12 clean scans across three explicit phases | Complete report entry, cancel/retry, native values, exact pixels, exact/empty/multiple-face ranges, CSV/JSON/PNG/figure, stale resource refusal, restart, bounded rapid keyboard navigation, and actual offline figure at320/390/1440px. |
| `brohn-media-pixels-20260924-03/results.json` | 25 shared-helper groups passed | Parent's actual lossless/multistream/error/resource checks, long path, no-clobber and post-encoding source-mutation refusal. |

The final joined receipt is **`brohn-facial-review-browser-20260924-02/acceptance.json`**, SHA-256 `854a2f521d78d7ea73f7e62600bcec312bb7095ef8b95c39ae8f7c893deb2e09`. Its independent closed-store inspector rechecked every original source byte, all six published frame RGB identities, downloaded PNG hashes, completed worker implementation hashes and all phase receipts.

| Browser phase under that fixture | Evidence and outcome | SHA-256 |
| --- | --- | --- |
| `browser-1790256470433/results.json` | 21 groups, 6 clean scans; original full connected path and restart | `15634d95d783973118bacee287cc2c010b511d34172327b46625feddceb87bbd` |
| `navigation-1790257118661/failure.json` | 7 successful navigation groups, 2 clean current-view scans, followed by a real failed standalone export check. Failure remains unchanged. | `f7457efe8e403df94f5a70c26fdc0e7749f1382282208c9e0407d21e04bad390` |
| `export-1790257420374/results.json` | Corrected actual-download continuation: 5 groups, 4 clean scans, no new jobs | `a3b4ad44969535e38f7efe13bb9b46e2f1a0bfd1fb082077ce1fc1317594c5de` |

Only `R/platform-facial-review-views.R` changed between these accepted phases. Each phase retains its own exact source snapshot, including `www/facial-review-ui.js`; the joined receipt does not claim a single uninterrupted run on one UI revision. Final browser accounting is **four inherited original jobs and nine new derived jobs**: one completed index, six completed frames, one cancelled index and one cancelled frame. The two cancelled requests have successful replacements. No native inference or original report scoring was repeated. Restart and the corrected-export continuation added zero jobs.

The final view coalesces keyboard cursor changes after500ms BEFORE external row lookup, permits one automatic frame extraction at a time, and retains only the latest pending selected time. Existing queued work completes without automatic global cancellation. The actual keyboard test paused the isolated worker with frame4 queued, moved rapidly to frame5, observed no additional queued job, then released processing and verified exactly frame4 followed by frame5. Completed pixels have no redundant prepare button.

Current native views passed at390/1440px; the actual downloaded standalone figure passed at320/390/1440px. Tests measured actual physical glyph size (at least11.5px), checked unchanged plotted native values and counts, performed axe/reflow checks, and inspected screenshots. The figure is self-contained with no external requests. I visually inspected the actual phone chart, source image and final320px exported figure: labels, legend and source pixels were legible without clipping.

The native reference consists of six independently timed frames composed from a retained permitted Apache2 test image: blank, one face, one face, two faces, blank, one face. Integer PTS are 2000, 2040, 2110, 2310, 2710, 2910 with time base 1/1000. Three samples are eligible and original adjacent single-face support is 0.07 seconds. It is not a natural-motion or actual-participant fixture.

## Retained failures and corrections

- Domain `-01`: harness lazy evaluation claimed a job before evaluating the expression that queued it. The corrected harness explicitly forces the argument. The initial index succeeded; the frame was never executed. `failure.json` labels this harness failure.
- Domain `-02`: actual original-frame publication exposed Windows MAX_PATH when the helper appended a full SHA to a successfully created temporary filename. Root changed the final filename to fixed `recorded-frame.png` inside the already unique owned per-job directory, preserving atomic no-clobber behavior and descriptor hashes. The failed job and `failure.json` remain. The 14-check continuation reopens the SAME historical index without inference or index rebuilding; it is not described as one uninterrupted run.
- Browser `-01`: deliberately stopped for a coordinated shared report-view edit immediately after startup. The owned R worker completed its index before termination. `coordination-abort.json`, original `failure.json`, source snapshot and service log remain; this attempt is not browser acceptance.
- Navigation follow-up: actual downloaded HTML lost its `head` because `as.character()` hoisted Shiny head content; all three responsive variants appeared. The final writer uses `htmltools::renderTags()` and explicitly assembles `rendered$head` and `rendered$html`, matching the existing report exporter. Original broken download/failure evidence is retained, and the corrected actual download passed independently without repeating frame jobs.
- Before final browser qualification, the facial chart gained a real compact SVG viewBox driven by measured CSS width. The harness checks physical text size at 390px as well as axe, overflow and screenshots; scaling an 820px viewBox alone was insufficient.

## Reproduction

```powershell
# Use the prepared publication Python; no model imports occur.
& $PublicationPython -B tests/workers/test_facial_review.py --evidence <new-contract-evidence>/results.json
& $PublicationPython -B tests/workers/test_facial_review_reference.py <original-native-reference> <new-reference-evidence>

# Set LC_ALL=C, R_LIBS_USER, BROHN_PUBLICATION_PYTHON,
# BROHN_PUBLICATION_NATIVE_MANIFEST and BROHN_FACIAL_FFMPEG_DIR.
& $Rscript tests/fixtures/researcher-facial-review.R setup <new-domain-folder> <original-native-browser-folder>
& $Rscript tests/platform-facial-review.R <new-domain-folder>
& $Node tests/researcher-facial-review.mjs <new-browser-folder> <original-native-browser-folder>
& $Node tests/researcher-facial-review-navigation.mjs <browser-folder> <full-browser-attempt>
& $Node tests/researcher-facial-review-export.mjs <browser-folder> <retained-navigation-attempt>
& $PublicationPython -B tests/inspect-facial-review-acceptance.py <browser-folder> <full-browser-attempt> <navigation-attempt> <export-attempt>
```

The navigation/export continuation scripts intentionally assert the retained phase shapes/source transitions used by this qualification; they are focused historical continuation tools, not fresh-install default suites. The standalone worker contract test is self-contained.

The optional domain `--resume-index` mode deliberately reuses exactly one prior successful index in a retained failed attempt. It must not be used to claim an uninterrupted qualification. Browser fixtures copy originals into an isolated workspace, distinguish inherited from new jobs, retain source hashes, and stop only their owned services.

## Limits

Software agreement does not validate an emotional or attentional construct, model demographic performance, real camera timing or person continuity. Native category names remain native classifier names. AU outputs are not calibrated FACS intensities; AU07 retains its distinct original decision objective. Missing faces are unavailable, never neutral/zero scores. Multiple-face rows stay frame-local and excluded from original single-face summaries. The browser's real-native source contains six frames; larger paging is a separately labelled authored contract proof. Exact source PTS is the file clock, not an inferred alignment to study events.
