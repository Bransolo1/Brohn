# Preferred participant batching: production integration acceptance

Status: production integration accepted on 24 September 2026. The production helper passes 31 independent contract checks; actual Chrome recovery passes 31 checks and two clean narrow-page accessibility/reflow scans. This is a transfer/recovery qualification of an original synthetic journal, not a new physical trial-timing experiment.

The isolated candidate is already qualified separately in [PARTICIPANT-UPLOAD-BUDGET-REVIEW.md](PARTICIPANT-UPLOAD-BUDGET-REVIEW.md): 31 pure checks and 16 actual HTTP checks on the exact original complete journal. Candidate measurements do not prove that a production participant page loads the new policy.

The production change retains the current 3 MiB hard limit for new operations, adds a 1.5 MiB preferred prefix, sends an indivisible larger first event whole up to the hard limit, and reconstructs persisted operations exactly under the existing 4 MiB ceiling. No operation ID, sequence bound, observation or scientific timing rule changes. The participant request timeout remains 15 seconds.

## Actual browser proof

`tests/participant-preferred-delivery.mjs` uses actual Chrome, the production participant page, actual IndexedDB and a separately owned R receiver. Its companion R fixture creates two original sample releases from the already accepted source design. After real consent/start, before any actual timed observation is collected, it places the independently accepted complete synthetic journal in that session's IndexedDB record for a focused transfer/recovery test. It does not claim new human collection or a second trial-presentation qualification.

The passed assertions cover:

- A new operation uses the preferred prefix, while an existing persisted 3 MiB operation above preference retains its original complete bytes and bounds.
- The real receiver commits an event operation while the test deliberately loses its acknowledgement. Reload must resend the same operation with identical evidence and retain the complete local journal until the final durable receipt.
- A separately lost final acknowledgement retains the exact finish operation across reload and does not queue another analysis job.
- All 394 events and 15,000 maximum-key observations survive with the exact frozen design/timeline. Jobs are cancelled before scientific execution.
- Actual delivered production runner/helper bytes match the frozen source identities; current browser pages have no exceptions, narrow completion pages have no axe violations or overflow, and screenshots are inspected.

The original journal, synthetic credentials/stores, browser receipts and screenshots remain external. The harness cancels its jobs and stops only its own service on exit.

Receipt: `make/work/test-runs/brohn-preferred-delivery-iEcQpf/results.json`. `source-start.json` pins the tested runtime and harness files; their hashes remain unchanged at the final check. The actual page responses match production helper SHA-256 `2c1afc86b382adbdfd43b7e1157fd0cb039349c95b6cfd57522e74a30c2ff9da` and runner SHA-256 `e4cc3f74360bb7428a9441716afec335e8a3145ad475d4859ef3fd8710ebaee6`.

The new-operation case sends six distinct contiguous event operations. Its first operation contains sequences 1-8, occupies 1,009,093 bytes and commits at the real receiver in 4.632 seconds before the harness withholds its acknowledgement. The retained-operation case reconstructs the original sequences 1-100 envelope at exactly 3,091,328 bytes; that first commit takes 13.319 seconds. Both cases reload with the exact unchanged uncertain envelope, then receive the complete final receipt. The new-operation case additionally loses and retries its final acknowledgement with the exact same finish body. The differing first-request size includes the browser-generated operation ID; no event changes.

Each reopened server record contains all 394 original events, including three 5,000-key native trial histories, with final canonical event hash `a784219f7c4cce3cbf9b284f6342458dbac09430bb209cddf8e076787fcfa1df`. Each case queues exactly one analysis job, cancelled at attempt zero. No scientific worker executes. The source journal SHA-256 remains `23a9ac23b0de684154c622c215092901f18d8b336f44fef0872d6f219111c7c1`.

The uncertain-event and uncertain-finish screenshots were visually inspected: the page explicitly retains local responses while awaiting a receipt. Both 390 by 844 completion screenshots were inspected; they are byte-identical and show legible wrapped text, a fully visible start-session button and the confirmed final receipt, with no horizontal overflow or axe violations. This run does not qualify an indivisible event above the preference through a scientific receiver; that unchanged size fallback has focused byte-boundary tests. The retained large operation remains comparatively close to the 15-second timeout. Host timings are observations, not capacity or hosted latency guarantees.

Reproduction:

```text
node tests/participant-event-batch.mjs
node tests/participant-preferred-delivery.mjs <accepted-large-receiver-directory>
```

The source directory is produced by `tests/platform-participant-large-receiver.R`. It must contain the accepted original `large-journal.json`, first persisted batch and start/acceptance receipts. This proof is scoped to transfer/recovery, not physical device timing, arbitrary session capacity or scientific worker publication.
