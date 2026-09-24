# SC-IAT receiver, interchange and reuse integration

This acceptance covers the named Brohn response-window SC-IAT, `sciat-brohn-response-window-im100/1.0`. It uses original synthetic observations through the real R receiver and SQLite store. It does not claim browser execution, physical timing qualification, stimulus validity or a scientific worker publication. Component/browser evidence and the scoring adapter remain separate.

## Passed connected contracts

`make/work/test-runs/brohn-sciat-window-integration-20260924-02/results.json` records 52 passing checks on 24 September 2026:

- The five preceding task-profile definitions match their pinned pre-registration snapshot exactly.
- Two fresh sample-release allocations receive complete outer journals: frozen keyboard preflight, study steps, 192 assigned trials, complete feedback/blank evidence and the final study outcome. Each journal contains 394 events. The receiver persists every original event field and acknowledges contiguous batches.
- Each completed session automatically queues its expected analysis. Both jobs are cancelled before any worker attempt, with their attempt counters remaining zero.
- Native task export replays the original journal. CSV and protocol registry preserve all 192 rows and every source cell for both allocations. Imported first-response scores, counts and complete scoring audits agree exactly with native pure analysis.
- Independent arithmetic checks the 144 test-trial contrast, mapping-specific error replacement and pooled original-correct sample standard deviation. The 48 practice trials remain excluded from that arithmetic.
- Summary imports remain `declared_trial_summary`: they gain no native key history, browser-clock replay or physical timing qualification. Invented corrections after a wrong first response and false native-evidence declarations are refused.
- Native and imported plots preserve all raw positions and latencies. Their 191 first responses include two errors; the separate correct-first measure has 189 values. One omission remains missing. No error acquires an invented final-correct latency.
- Explicit two-person cohort linkage accepts only the registered score recipe and produces descriptive person summaries in D units. It does not count trials as people or add inference.
- Clone and template reuse create new study/task/category identities while retaining the registered settings. A real ZIP export/import preserves decoded PNG bytes, source hash and alternative text; missing image descriptions are refused. Later draft-image edits and reuse do not change either released session.
- Start/end implementation hashes and original session evidence remain unchanged. Generated recordings, registries, packages, private stores and receipts remain external.

The initial `-01` setup used `preview` as a release origin, which publication correctly refused. The final fixture uses `sample` and keeps the original synthetic material status. That refused setup is retained separately.

## Large event envelope: size passes, parser latency corrected

The original JavaScript fixture builds complete native-shaped 5,000-key observations with fractional browser milliseconds. `BrohnEventBatch` chooses three complete events under its configured 3 MiB wire budget. The exact wire body is **3,015,284 bytes**; the real R request parser accepts it and produces a **3,121,214-byte** canonical body, below its unchanged 4 MiB limit. No event or key observation is truncated.

A separate fresh read of that immutable envelope is recorded in `make/work/test-runs/brohn-participant-event-envelope-20260924-01/results.json`. All four data-contract checks pass, including native replay of the complete first 5,000-key trial and unchanged source bytes. This follow-up measured:

| Operation | Elapsed time |
|---|---:|
| Actual R request parsing and canonical size validation | 36.00 seconds |
| Canonical encoder alone | 38.56 seconds |
| Native replay of the first complete 5,000-key trial | 0.53 seconds |

The original measurement exposed a delivery-performance gap: request validation alone exceeded the participant runner's 15-second fetch timeout. A subsequent bounded encoder correction is qualified in [CANONICAL-ENCODER-PERFORMANCE.md](CANONICAL-ENCODER-PERFORMANCE.md): 174 exact-byte/validation checks pass, and the same envelope now passes actual request parsing in 3.62 seconds with identical canonical bytes. The original failed performance observation remains retained. These parser measurements do not include a network round trip or subsequent receiver transaction costs. The same acceptance document separately records 13 full HTTP checks: a valid complete 192-trial journal with three distinct 5,000-key trials takes 14.030 seconds for its 3,091,328-byte first append and 7.862 seconds for the exact operation retry. Later append and finish requests are below 3.28 seconds; a reopened store preserves every event. This passes the current local 15-second budget with limited first-append headroom, not a guarantee for slower hosts or networks. Neither receiver limits nor the scientific procedure changed.

## Reproduction

From the repository, using its configured R library and Python runtime:

```text
Rscript tests/platform-sciat-window-integration.R <new-external-directory>
Rscript tests/platform-participant-event-envelope.R <accepted-integration-directory> <new-external-timing-directory>
```

The integration fixture invokes `tests/fixtures/participant-event-envelope.mjs` using Node. Its full source fingerprints are retained in the receipts. It creates only synthetic local studies and sample sessions, cancels its automatic jobs, and closes its own stores. No user data, credentials, media recordings or existing scientific reports are required.
