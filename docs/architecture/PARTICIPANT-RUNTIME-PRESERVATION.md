# Preserving participant code with study releases

24 September 2026: production publication, HTTP delivery, atomic run assignment
and backup hooks are connected; joined browser/researcher acceptance passes.
The extended preservation test passes 57 checks; a separate connected dispatcher
and storage test passes 27. Newly published studies now preserve their generic
participant files. Historical unpinned releases keep their original behavior.

## Purpose and stored contract

A study release already preserves its design and materials. Its participant
HTML, JavaScript, CSS and audio worklet previously came from the installation,
allowing a software update to change the code used when a participant reloaded.
Preserve the exact generic distribution bytes in the content-addressed object
store when a **new release** is published. Keep an immutable manifest of logical
path, SHA-256, byte length and response media type, plus a separate immutable
run-to-release runtime assignment. This records assigned code, not proof of
browser execution, physical timing, scientific validity or an entire preserved
operating environment.

Manifest `brohn-participant-runtime/1.0` currently contains 17 files, including
the relative camera worklet and brand icon. File and total limits are 1 MiB and
8 MiB. Preparing a release reads and rechecks original bytes, verifies entry
references belong to the inventory, and refuses a missing or changed file.
The allowlist is maintained alongside participant dependencies; it is not a
general JavaScript dependency analyser. Future secondary imports, CSS assets
or workers need explicit inclusion and browser acceptance.

`brohn_runner_assets_publish(store, prepared, create)` runs the publication
callback and stores its assets in one SQLite transaction. Exactly one new
release row must be created inside that transaction. Returning an existing
release is refused even when it has no participants. Historical releases remain
`legacy_unpinned`; current source bytes must never be presented as their history.
The object media type in the manifest controls serving: content deduplication
can legitimately give an existing object catalog entry a different media type.

`brohn_runner_catalog_integrity(con)` verifies manifest hashes, all object
references and sizes, run/release/hash agreement and missing run assignments.
This is connected to backup verification. The immutable publication audit also
records the expected manifest: a lost manifest, or even loss of both runtime
tables, cannot silently turn a known pinned release into legacy unknown history.
The ordinary backup copies all registered objects and tables; restore preserves
these bytes while retaining its existing closed-release, paused-workspace and
rotated-capability behavior.

## Delivery and recovery integration

Use the directory layout
`/api/runtime/{release-token}/{manifest-hash}/participant/index.html?token={release-token}`.
Relative scripts, styles, `audio-worklet.js` and `../brand/brohn-app-icon.svg`
then continue to resolve without rewriting preserved bytes. The original
`/participant` and `/participant/` links redirect only for pinned releases.
Keep the same origin and IndexedDB identity. Reject conflicting, repeated or
missing page token identities instead of loading release A's code for release B.

Serving each resource requires the known release capability, its exact pinned
manifest and an exact manifest member path. Recheck the stored bytes and return
them directly. Never fall back to installation files for a missing or corrupt
preserved object. There is no arbitrary object or filesystem route.

**Recovery exception for generic application code:** a known release's pinned
generic code can remain readable after recruitment/resource expiry or
revocation. It contains no authored study content or participant data and is
already part of the public application distribution. This preserves the existing
ability of an admitted, independently authorized run to reload, upload retained
events, reconcile a receipt or withdraw. Keep edge/origin controls and every
study-entry, stimulus, enrollment, run-expiry and run-revocation check unchanged.
A restored old capability must fail after token rotation.

Start requests for newly pinned releases need explicit matching runtime identity.
Use a dedicated `X-Brohn-Participant-Runtime` request header derived from the
pinned page path; validate it against the release before enrollment. Assign the
runtime inside the same transaction as the run and receipt. Existing historical pending start, event batch and finish requests
retain their exact original bodies and operation IDs. A new metadata field must
not be retroactively inserted into an uncertain request. Run protocol schemas
and raw historical events remain unchanged.

An uncertain start request can also be reconciled when study entry later closes
or expires. The browser retains and resends the exact original request; the
receiver permits the already admitted client mapping and continues to refuse a
new enrollment. Returned deployment metadata is separate from the protocol.

## Executed preparation evidence

`work/test-runs/brohn-runner-assets-20260924-06/results.json`: 53 passing checks,
including all 17 exact stored files, changed installation versus original
release, refusal of retrospective/changed pinning, transactional rollback,
immutable assignment, traversal/missing/oversize/corrupt assets, complete backup
and restore, and independent corruption probes for manifest, object and run
assignment integrity. Ten further direct route checks cover exact redirects,
conflicting/missing/duplicate page identities, relative worklet/icon bytes,
closed-release code recovery and rotated restore capabilities. These call the
prepared route helper directly, not a connected production HTTP server. The
corruption probes roll back their deliberate catalog changes. Two publication
fault checks confirm that a failed creation callback or third asset-store call
leaves release, credential, runtime and audit counts unchanged.

The initial `-01` test stopped because its synthetic study omitted required
stimulus content; only that fixture was corrected. `-02` passed 32 checks before
review tightened new-publication-only pinning and catalog validation. Preserve
those receipts; they do not substitute for the final source result. `-03` passed
40 checks before the prepared route helper and its ten checks were added.
`-04` passed 50 checks; `-05` adds publication fault checks and respects filesystem
case sensitivity when checking source containment.
`-06` keeps runtime reads read-only, without a schema write or retrospective
migration, and adds a legacy-catalog check. Actual concurrent HTTP capacity
remains an integration concern.

## Connected acceptance and remaining work

- Connected publication/start/backup dispatcher checks pass 27 assertions in
  `work/test-runs/brohn-runner-query-fix-20260924-01/platform-runner-delivery.json`, including failed
  publication and failed binding with release/run/credential/hosted-policy/
  receipt/audit rollback. This invokes the actual HTTP dispatcher, not a browser
  or network proxy. The first two attempts corrected fixture omissions (project
  initialization and the survey question); no product behavior was changed.
  The fourth run adds refusal of authenticated operations when an originally
  preserved runtime assignment is missing; the third passed the prior 25 checks.
  Actual HTTP testing then exposed the server's leading `?` query delimiter,
  which the initial direct fixtures omitted. Normalizing that one delimiter
  preserves both forms and duplicate-identity rejection. The same query-fix
  directory contains the final 57 preservation checks. Original browser failures
  are retained in the separate browser acceptance record.
- The [actual browser and receiver journey](../qa/PARTICIPANT-RUNTIME-BROWSER-ACCEPTANCE.md)
  passes 74 checks and three narrow accessibility/reflow scans. It exercises
  distinct old/new releases, restart without the original distribution, pending
  events and final receipts, server-committed lost start acknowledgement, native
  worklet loading and the relative icon. Explicit legacy history remains unknown.
  Revoked/expired recruitment permits only previously admitted, independently
  authorized recovery. Run revocation/expiry still refuses delivery and retains
  local evidence. Restore rotates capabilities, preserves exact code/events and
  keeps execution paused. This uses a synthetic trusted edge and does not qualify
  public TLS/OIDC deployment.
- Visual inspection of that receipt found misleading setup-failure wording.
  The follow-up also identified a failed first local write followed by an
  unjournalled retry, and a later display failure offering a new start after a
  run was already saved. The corrected runner persists the exact pending setup
  before every attempt; after admission it reloads the same saved session.
  A separate actual-browser fault-injection receipt passes 20 checks and three
  clean narrow scans at `work/test-runs/brohn-runtime-browser-setup-Oef2mW`.
  It verifies the exact durable request before transmission, lost-acknowledgement
  recovery, unchanged admitted run/credential without another start request, and
  refusal of an uncommitted revoked setup with no allocation. The two completed
  fixture sessions each queue one job cancelled at attempt zero; no scientific
  worker was needed for these recovery checks.
- Researcher-facing release/run provenance and exported report links are
  connected. Their [researcher journey](../qa/PARTICIPANT-CODE-PROVENANCE-ACCEPTANCE.md)
  passes seven checks/four scans and a separate 21-check source/export audit.
  Final narrow-screen wrapping and keyboard inspection passes two browser
  checks/two scans and four independent checks. Collect, assigned protocols,
  closed History and native reports retain the same original code identity.
  One participant completion produced one native report; all subsequent review,
  export, restart and visual corrections created zero additional jobs.

Preserving browser assets alone does not freeze R compilation/replay or native
analysis implementations. Analysis jobs already fingerprint their scientific
code. Reconcile compiler compatibility and future release migrations separately;
do not describe this feature as a complete executable environment archive.
