# Participant upload headroom review

Design review and nonloaded candidate qualification, 24 September 2026. The historical candidate measurements below remain separate from the subsequently completed [production integration and actual browser recovery acceptance](PARTICIPANT-PREFERRED-BATCH-ACCEPTANCE.md). The production runner now adopts the tested 1.5 MiB preference with its unchanged 3 MiB hard limit. Scientific trial deadlines, feedback durations, reaction-time rules and the recorded browser clock remain independent of delivery timeouts.

## Current evidence

The actual complete HTTP fixture in [CANONICAL-ENCODER-PERFORMANCE.md](CANONICAL-ENCODER-PERFORMANCE.md) accepted a 3,091,328-byte event request in 14.030 seconds. Its exact operation retry took 7.862 seconds. This passes the current participant fetch timeout of 15 seconds with only about 0.97 seconds of local headroom.

At the measured baseline, `runner.js` selected at most 100 complete events under a 3 MiB budget for a **new** operation. It durably persists the operation ID and sequence bounds before sending. A retained operation is reconstructed with those exact bounds under the helper's existing 4 MiB wire ceiling; it is never silently split or renamed. The R receiver also checks a separate 4 MiB **canonical** JSON limit, so wire size alone does not establish canonical acceptance.

An immutable read of the accepted complete journal compares preferred prefix sizes using the production helper. External receipt: `make/work/test-runs/brohn-participant-large-receiver-20260924-03/upload-policy-review.json`. Its source SHA-256 is `23a9ac23b0de684154c622c215092901f18d8b336f44fef0872d6f219111c7c1`. Source bytes are unchanged. The three large source events contain 1,005,061, 981,891 and 999,614 bytes respectively.

| New prefix size | First request bytes | Maximum-key trials in first request | Requests for complete 394-event journal |
|---|---:|---:|---:|
| 1 MiB | 1,009,080 | 1 | 7 |
| 1.5 MiB | 1,009,080 | 1 | 6 |
| 2 MiB | 1,993,743 | 2 | 5 |
| 3 MiB | 3,091,330 | 3 | 4 |

The comparison operation IDs are two bytes longer than the accepted HTTP operation, explaining the two-byte difference in the last row. These are exact byte/count comparisons, **not measured HTTP latency estimates**. Passing a smaller new limit alongside the already persisted first batch retains its original 3,091,328 bytes, ID and sequences 1-100 exactly.

## Adopted implementation policy

Add a **preferred** 1.5 MiB prefix target while retaining the current 3 MiB hard limit for new operations and the existing 4 MiB reconstruction ceiling for persisted operations. A preferred target must not become a smaller accepted single-event limit:

1. Reuse a persisted operation exactly, ignoring all new-operation preferences. An uncertain upload remains the same operation until the receiver acknowledges or explicitly reconciles it.
2. For a new operation, choose the largest contiguous prefix up to 100 events that fits the preferred target, accounting for the exact UTF-8 operation envelope.
3. If its first complete event exceeds the preferred target but fits the existing new-operation hard limit, send that **one complete event alone**. Do not truncate its fields, split its key history or refuse it merely for exceeding the preference.
4. Retain the existing explicit single-event hard-limit refusal and local data retention. The R canonical bound remains authoritative; no accepted envelope or scientific observation limit increases.
5. Persist the chosen exact operation/bounds before any network request. Only a durable receipt advances the acknowledgement and clears that operation.

The proposed helper argument can be `preferredBytes`, defaulting to `maxBytes` to preserve existing standalone callers. Validate that both are integer byte counts and `1 <= preferredBytes <= maxBytes <= 4 MiB`. The runner would supply 1.5 MiB preferred and its unchanged 3 MiB hard limit. Merely changing its existing `maxBytes` to 1.5 MiB would incorrectly reject larger indivisible events and is not the recommendation.

For this source, 1.5 MiB separates the three expensive trials while requiring one fewer request than a 1 MiB target. The candidate HTTP evidence below supports better per-request headroom for this journal, not proof that every large-session transaction will meet 15 seconds.

## Nonloaded candidate evidence

The candidate is `tests/fixtures/participant-event-batch-preferred-candidate.js`, exposed only as `BrohnEventBatchPreferredCandidate`. It is not loaded by `index.html`, `runner.js` or R's production loader. Its final SHA-256 is `9033f1225f2fcd9ebd0305b6d69cad97388e0c3d43716a3aa34fed649430b0ee`.

**31 pure checks pass**, including all prior selector contracts, exact preferred UTF-8 boundaries, a complete indivisible event above preference, an exact 3 MiB first-event fallback, a following oversized event becoming its own later fallback, unchanged 4 MiB persisted-operation reconstruction, deep input immutability and the original default gap refusal at an exact hard boundary.

`make/work/test-runs/brohn-participant-preferred-receiver-candidate-20260924-02/results.json` records **16 actual HTTP checks** using that final candidate. A fresh sample release has the exact original compiled task/outer timeline; the test reads the original accepted 394-event source file without rewriting it. All 15,000 maximum-key observations, event IDs, sequence positions, clocks and phase fields are unchanged. Candidate selection produces six complete request bodies; the actual unchanged production receiver accepts them. Exact retries do not duplicate events or jobs, the whole-history finish succeeds, and a reopened store retains the same final event hash as the baseline. The one automatically queued scientific job is cancelled at attempt zero. The service is stopped.

| Candidate HTTP transaction | Bytes | Elapsed |
|---|---:|---:|
| Events 1-8, first 5,000-key trial | 1,009,078 | 5.273 s |
| Exact same first operation retry | 1,009,078 | 2.576 s |
| Events 9-12, second 5,000-key trial | 984,714 | 4.648 s |
| Events 13-112, third 5,000-key trial | 1,111,193 | 6.014 s |
| Events 113-212 | 112,323 | 2.782 s |
| Events 213-312 | 113,466 | 2.965 s |
| Events 313-394 | 91,612 | 3.117 s |
| Finish after complete original journal replay | 83 | 2.772 s |
| Exact finish retry | 83 | 0.097 s |

The final candidate's slowest append is **6.014 seconds**, compared with **14.030 seconds** in the earlier production-prefix baseline. The initial candidate run in `-01` had the same six envelope bytes and a slowest append of 7.045 seconds. A final review added stricter default-boundary compatibility and its explicit test, then repeated the complete HTTP route in `-02` on the final candidate identity. The earlier successful run is retained, not relabelled as final-source evidence.

| Measurement | Production 3 MiB | First candidate run | Final candidate run |
|---|---:|---:|---:|
| Append requests | 4 | 6 | 6 |
| Slowest append | 14.030 s | 7.045 s | 6.014 s |
| Sum of append HTTP times | 23.184 s | 29.273 s | 24.798 s |
| Sum of all HTTP times, including start/retries/finish | 35.722 s | 37.664 s | 31.706 s |

`comparison.json` in the final directory pins all three receipts and verifies the identical final event hash, unchanged shared product source hashes, and byte-identical candidate envelopes. These sequential host measurements show useful per-request headroom; they are not a controlled throughput benchmark. More requests cause more complete prior-history replays, and both candidate runs have greater summed append time than the baseline. Recommend integration for improved receipt headroom while keeping the cumulative replay limitation explicit. No timeout was increased, and no scientific worker ran.

## Frozen-release compatibility

At the inspected source revision, release/run storage freezes design and compiled protocol JSON and immutable stimulus hashes. JavaScript and CSS are served from current `static_root` through unversioned participant routes, so a reload can fetch current scripts while already open pages keep their loaded copies. That is not a pinned historical JavaScript manifest; introducing one is a separate root-owned integration.

The proposed preference remains backward-compatible during a coordinated asset update: new helper plus old runner defaults to its existing 3 MiB limit; old helper plus new runner ignores the extra preference argument and continues existing 3 MiB selection. Neither combination changes the persisted operation schema or frozen scientific protocol. `index.html` loads the batch helper before the runner. When runtime assets become versioned, retain relative script/CSS resolution, `camera.js`'s relative `audio-worklet.js`, and the relative favicon; study media continue using their authorized absolute `/api/assets/` URLs and the runner's absolute API routes. Preserve the token/study query when redirecting to a pinned entry page.

## Timeout and cumulative work

R currently performs a full canonical request validation, canonical request hashing, original-event replay and individual event encoding before receipt publication. `platform-delivery.R` also rereads/replays the existing entire session before every new append and finalization. Consequently, smaller new request bodies cannot by themselves guarantee bounded latency after a large accumulated journal. That cumulative replay path needs its own profile and, if necessary, a separately qualified incremental state design; no shortcut may trust a caller's state or change the accepted evidence.

There is no demonstrated application request-time supervisor in the current participant handler. The inspected hosted configuration adds a body-size cap, but no explicit coordinated application/proxy response-time budget. Raising the browser timeout alone would therefore be a **client patience change**, not a supervised server budget. It can permit a large indivisible event or old retained operation to finish, but cannot bound server work or establish capacity. Do not describe it as a performance repair or alter trial response windows to match it.

If a larger event-request timeout is subsequently needed, keep it specific to delivery, retain a finite abort, prevent concurrent retries, preserve the exact persisted operation after an uncertain outcome, and continue displaying truthful locally-saved/awaiting-receipt status. A client abort must never be treated as evidence that the server rolled back. Align any chosen timeout with an explicitly measured and supervised backend/proxy policy before making a hosted guarantee.

## Integration acceptance and remaining limits

- Completed separately: 31 production helper checks and 31 actual browser checks with two clean narrow-page scans. Exact delivered helper/runner bytes, lost event/final acknowledgement recovery, retained old 3 MiB operations, no duplicated events/jobs and final local-journal deletion are covered in the linked production acceptance. The normal 15-second timeout is unchanged.
- An indivisible event above the preference, retained old large operations, and increasing complete prior-journal replay work. Do not claim smaller-prefix timing qualifies these different cases.
- The completed browser proof deliberately withholds acknowledgements after real commits and reloads exact persisted operations. It does not simulate every network/proxy failure or qualify arbitrary accumulated journal sizes.
- The browser transfer proof preserves every original observation and frozen timeline; no new physical trial collection or stimulus-timing claim follows from it. Concurrent ongoing trial presentation under delivery load remains a separate capacity qualification.

Reproduction from the configured repository runtime:

```text
node tests/participant-event-batch-preferred-candidate.mjs
Rscript tests/platform-participant-preferred-receiver.R <accepted-large-receiver-directory> <new-external-directory>
```

The accepted source directory is produced by `tests/platform-participant-large-receiver.R`; it contains synthetic local credentials and should stay external. No production source was edited for this candidate. All large journals, private stores, HTTP receipts and generated comparison artifacts remain external.
