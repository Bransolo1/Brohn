# Exact canonical JSON performance

The SC-IAT integration audit found that a valid three-event envelope, with 5,000 original synthetic key observations per event, took 36 seconds to pass the R request parser. Its canonical encoding alone took 38.56 seconds in a separate measurement. The participant runner's fetch timeout is 15 seconds.

The change is confined to `.brohn_store_json` in `R/platform-store.R`. It keeps the original recursive validation, scalar/array rules, object ordering, finite-number rules, depth limit and final byte limit. It resolves the same pinned `jsonlite` 2.0.0 string and numeric primitive formatters once per document, bypasses repeated public option/S4 dispatch per scalar, and escapes an object's keys together. Boolean output remains exactly `true` or `false`. No source, receipt, catalog or report hash format changes.

These package-private primitive functions are intentionally tied to the pinned runtime. Updating `jsonlite` requires rerunning the frozen-original equivalence test; they must not be replaced with a new numeric formatter merely because displayed values look the same.

## Accepted evidence

External receipt: `make/work/test-runs/brohn-canonical-performance-20260924-01/results.json`.

**174 checks passed**, including:

- Exact bytes and SHA-256 against the independently frozen original function from commit `e35db46`, plus a hand-authored literal JSON contract.
- Binary64 limits, subnormal numbers, negative zero, near-adjacent doubles, integer/double vectors, explicit nulls, empty objects/arrays, forced singleton arrays and mixed nested records.
- Unicode and Latin-1 input, escaping, radix key order across available collations, malformed UTF-8 refusal, and 100 deterministic independently generated mixed trees.
- Unsupported R classes, missing/nonfinite values, invalid/duplicate keys, atomic names/dimensions, depth-64 boundaries and exact UTF-8 byte limits. Original input values remain unchanged.
- Full immutable maximum-key envelope bytes and hash, then the actual participant request parser using the production encoder.

| Same retained envelope | Result |
|---|---:|
| Original JavaScript wire body | 3,015,284 bytes |
| Original and optimized canonical body | 3,121,214 bytes, identical |
| Frozen original encoder | 38.05 seconds |
| Optimized production encoder | 3.06 seconds |
| Actual request parse and canonical validation | 3.62 seconds |

The 3.62-second parser measurement is below the unchanged 15-second fetch timeout. It measures parser/validation latency, not a full network round trip or subsequent receiver transaction. Actual participant delivery remains a separate integration requirement.

The existing **74 durable storage checks**, **56 participant delivery checks** and **24 exact numeric transport/legacy replay checks** also pass, covering real SQLite persistence, immutable objects, job fencing, restart, researcher release, allocation, consent, receipts, recovery and HTTP. No receiver size limit, scientific scoring rule or participant timeout changed.

The read-only candidate qualification passed 173 checks before the product edit. An initial candidate test stopped at a lazy-evaluation bug in its random-tree test generator; the generator was fixed before the full proof. The failed development directory remains external. No product change was made on the basis of that incomplete test.

## Complete HTTP transaction follow-up

`make/work/test-runs/brohn-participant-large-receiver-20260924-03/results.json` records **13 passing checks** using the unchanged production encoder and a separate actual participant receiver process. This is independent of the parser-only benchmark above. It sends a complete original synthetic 192-trial SC-IAT session, including frozen equipment requirements, actual assigned protocol, onset, feedback/blank and finish events. Three distinct responded trials retain 5,000 key observations each, including a first response exactly at the 1,500 ms deadline. Native full-journal replay passes before transport. The original journal has 394 contiguous outer events; it does not duplicate one finished trial into unrelated protocol positions.

The production JavaScript helper chooses the complete contiguous batches under its existing 3 MiB wire budget. HTTP timings cover request send through complete response receipt, including the receiver's parse, validation, hash, SQLite transaction and response. The test's transport timeout is 180 seconds solely to preserve terminal evidence if the production runner's unchanged 15-second budget is missed.

| Actual HTTP transaction | Wire bytes | Elapsed |
|---|---:|---:|
| First 100 events, including all three maximum-key trials | 3,091,328 | 14.030 s |
| Exact same operation and bytes retried | 3,091,328 | 7.862 s |
| Events 101-200 | 112,335 | 2.800 s |
| Events 201-300 | 113,370 | 3.075 s |
| Events 301-394 | 105,250 | 3.279 s |
| Final completion | 83 | 2.901 s |
| Exact completion retry | 83 | 0.096 s |

All measured requests finish inside 15 seconds, but the first append has only about **0.97 seconds of headroom**. This is a single local loopback measurement under the current host load, not a guarantee on slower hosts, remote networks or every supported journal. The full transaction remains materially slower than parsing alone.

Every source event field and all 15,000 maximum-key observations survive persistence exactly. The acknowledged retry creates no duplicate events; completion creates exactly one analysis job, cancelled before attempt zero advances. A reopened store retains the completed run, exact journal and cancelled job. All measured product source fingerprints and original fixture bytes are unchanged, and the receiver subprocess is stopped at exit. No scientific worker executes in this follow-up.

The preceding `-01` fixture setup stopped on a wrong source-manifest filename before any service launch; `-02` stopped because the optional R `curl` package was absent. Both directories are retained. The accepted harness uses built-in Node HTTP transport and the installed R runtime without adding dependencies. These were fixture setup failures, not accepted delivery runs.

## Reproduction

```text
Rscript tests/platform-canonical-performance.R <new-external-directory> <original-selected-envelope.json>
Rscript tests/platform-store.R
Rscript tests/platform-delivery.R
Rscript tests/platform-json-precision.R
Rscript tests/platform-participant-large-receiver.R <new-external-directory>
```

Generate the original envelope with `tests/platform-sciat-window-integration.R` as described in `SCIAT-WINDOW-INTEGRATION-ACCEPTANCE.md`. The byte oracle lives in `tests/fixtures/original-store-json.R`; it retains the original scalar serialization independently of the optimized helper. The complete HTTP fixture generates its own original synthetic study and chooses an unused loopback port; it requires Node on PATH and the configured R library, and cancels any automatically queued jobs. Receipts, credentials in synthetic private stores, large synthetic envelopes and timing artifacts stay outside the repository.
