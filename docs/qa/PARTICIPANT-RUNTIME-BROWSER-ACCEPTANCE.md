# Preserved participant runtime: browser acceptance

Status: 74 actual browser/receiver checks and three clean narrow-page accessibility/reflow scans passed on 24 September 2026. A separate final-source setup-recovery follow-up passed 20 checks and three further scans, resolving the wording issue and qualifying durable retries after local/UI failures. The two source-specific receipts remain separate.

The production implementation and direct transaction/catalog checks are described in [PARTICIPANT-RUNTIME-PRESERVATION.md](../architecture/PARTICIPANT-RUNTIME-PRESERVATION.md). This separate browser fixture uses real Chrome, IndexedDB and a separate actual R HTTP receiver. Hosted request identity is supplied by an explicitly synthetic trusted-edge adapter. It does not qualify public TLS, OIDC or reverse-proxy configuration.

`tests/fixtures/runtime-preservation-browser.R` prepares a small original text survey and separate releases. It copies the current distribution into an external fixture directory, publishes the first releases, then changes only comments in that copied runner/worklet before publishing a second distribution. A separately labelled simulated pre-feature release is created through the internal legacy publication body. This demonstrates legacy behavior without assigning invented historical code identity.

`tests/participant-runtime-preservation.mjs` verifies:

- Actual redirect and page-derived runtime header; durable start JSON remains unchanged.
- A committed but unacknowledged start recovers its original run after release revocation or resource expiry.
- An uncommitted saved setup cannot enroll after revocation and retains its original pending request.
- Lost event/final acknowledgements survive pinned-page reload with exact operations and complete local evidence until final receipt.
- Revoked or expired runs retain local events/drafts without inventing a participant ending or analysis job.
- Old/new distribution bytes and the explicit unpinned path remain distinct; relative icon and native AudioWorklet module requests resolve to the original release.
- A restarted receiver without a static distribution serves preserved assets and refuses missing legacy files.
- Backup/restore preserves event and runtime assignments, rotates capabilities and keeps execution paused. Old capabilities fail; restored exact runtime bytes remain available through the new capability.

No physical camera/audio capture or scientific worker execution is part of this fixture. Automatic analysis jobs are cancelled before execution. Runtime tables, generated credentials, browser receipts, screenshots and copied distributions remain external; the harness stops only its own services.

Reproduce from the configured repository runtime after source freeze:

```text
node tests/participant-runtime-preservation.mjs
```

## Accepted receipt and scope

`make/work/test-runs/brohn-runtime-browser-aJN5t2/results.json` contains the 74 checks, three scans, actual asset hashes and immutable source identity. The fixture completed four real small survey sessions. Each queues exactly one analysis job, cancelled at attempt zero. Two separately revoked/expired runs remain in progress with their original received events and local drafts retained; no ending or job is fabricated. The genuinely uncommitted revoked setup creates no run. Five of the six admitted runs have the exact separately preserved assignment; the explicit legacy simulation has none.

The test restarted the receiver with an absent static root, then started the restored workspace on the same fixture port. All three receiver processes shut down; the harness exited zero and a subsequent process inventory found no remaining fixture R process. Backup/restore preserved every received event and assignment, rejected old capabilities, served exact original code with the rotated capability and retained the execution pause.

Key SHA-256 identities in the full receipt:

| Source | SHA-256 |
|---|---|
| `R/platform-runner-assets.R` | `aa935e7863d66752e61eda4287ee8cc4cf4cecc799745b4b5795f62d177462bc` |
| `R/platform-delivery.R` | `619ab78cb9ea7d7da39ee0267523c0208cb9288cf6c49cd5dfe50de33b27a245` |
| `R/platform-backup.R` | `ea1071ce6581d8b7d2f5c68ddb97df74e62295868daa6739381bd978496ad6bd` |
| `www/participant/runner.js` | `c3f8e8f598ad11ea2a2d219587df1f6880d5e54578809a84c7f5b506b675a094` |
| `www/participant/camera.js` | `d4a0a24707af59ef87693aa68b64d111d346105c5a43b413cb21fa0675d3f4dd` |

The original and updated copied distributions have distinct manifests. Actual browser page responses match their respective runner bytes. Native `AudioWorklet.addModule` succeeds at the relative versioned path; `worklet-responses.jsonl` independently records the actual receiver's status, exact path and returned raw-byte hash. This establishes module availability, not audio capture or a physical timing measurement.

## Visual inspection

The 390 by 844 completion, rejected setup and revoked-run screenshots were inspected, along with the pending final-receipt desktop screenshot. Text and controls are legible, with no clipping, horizontal overflow or axe violations. Completed sessions show the final receipt; revoked runs clearly say data remain local and delivery is unconfirmed.

The original 74-check receipt's rejected, uncommitted setup correctly shows its revoked-link error and retains the exact pending request, but its heading remains "Preparing your session" with "Please wait" above the permanent refusal. Root corrected that misleading wording and a related retry risk. The focused final-source acceptance below supersedes this visual limitation without relabelling the original receipt.

## Final-source setup recovery follow-up

`tests/participant-setup-recovery.mjs` passed **20 checks and three clean 390 by 844 scans** in `make/work/test-runs/brohn-runtime-browser-setup-Oef2mW/results.json`. Its source SHA-256 is `2fc09fb2fbfd726563190037130106e024ab3aa93aa238fb338e1f6db5523933`; the tested final runner SHA-256 is `92c0aeb8585f685ce84bafcbd74c49356d2dbb72e851e749c4b6f1dc4ac74aa3`. All tested sources remain unchanged across this follow-up.

The browser deliberately fails one initial IndexedDB write before enrollment. No start request is sent and no durable local record is claimed. On retry, the fixture independently reads IndexedDB at each actual start request to confirm its exact pending body is durable before transmission. It then withholds a real committed acknowledgement, reloads and verifies byte-identical recovery of the same server run. The completed survey creates one analysis job, cancelled at attempt zero.

A second deliberate display failure occurs in the document title setter after the actual run has been durably stored. The interface offers recovery of the existing session; it does not offer a new setup operation. Reload preserves the original run ID, credential and frozen protocol, issues no second start POST, and completes one run and one analysis job. A third case refuses an uncommitted setup after revocation while retaining its exact pending body and consuming no allocation.

All three actual screenshots were visually inspected. The initial local-save failure says "Session setup needs attention" without a false retained-data claim. The post-admission error says "Your existing session needs attention" and offers "Recover this session". The revoked setup displays its refusal under the attention heading, without ongoing-preparation wording. Text and controls fit the narrow viewport and all three axe/reflow scans are clean. The owned receiver exited zero, two jobs were cancelled at attempt zero, and no fixture R process remained. No scientific worker executed.

Reproduce this focused follow-up independently:

```text
node tests/participant-setup-recovery.mjs
```

## Retained earlier attempts

The initial actual HTTP runs in `make/work/test-runs/brohn-runtime-browser-12hvNZ` and `brohn-runtime-browser-gTaE2f` exposed a transport mismatch: installed httpuv supplies `QUERY_STRING` with a leading `?`, while the prepared parser only recognized the form without it. The public link consequently fell through to the installation page instead of redirecting to preserved code. The second run records the actual transport prefix without changing it. Both attempts stopped before participant enrollment and shut down their owned receiver. Their failures remain retained; final acceptance requires the corrected parser and a fresh source-pinned run.

Root corrected the parser to accept exactly one optional leading `?`, retaining duplicate and conflicting identity checks. The final accepted run above uses that correction. Intermediate attempts `brohn-runtime-browser-FE8CWr` and `brohn-runtime-browser-FScPzY` passed actual redirect/header, lost-start recovery and exact event retry, then stopped because the harness awaited a Playwright page response event for a native worklet fetch. Native module loading itself completed; this fetch is not exposed through that page event in the tested Chrome. The harness now uses successful native module loading plus the independently retained actual receiver response receipt. Both intermediate attempts retained their failure screenshots/logs and completed cleanup; no product change was made for that harness correction.
