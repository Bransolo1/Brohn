# Save, clone and move study designs

Status: **implementation plan, 2026-09-08**. These requirements extend the
[master architecture](../MASTER-ARCHITECTURE.md). The current immutable
`study-protocol/0.1.0` JSON snapshot/export in
[protocol storage](../../R/protocol-storage.R) preserves the current bounded
design, including its two PNGs. It does not yet provide the general package
format, template library or restore-as-draft flow below, and contains no collected
data. Preserve its reader and introduce an explicit migration.

The current app also exports and reopens a draft bundle through **Export JSON**
and **Open a draft JSON file**. That bounded schema preserves existing identities
and session-origin restrictions; it does not provide the general design-only
package, fresh-identity cloning or neighboring history transfer specified below.

Qualtrics similarly separates a QSF survey design/settings export from response
data, and imports it as a new survey. This is a useful interaction precedent;
Brohn's package makes no QSF compatibility promise.
([Qualtrics import/export documentation](https://www.qualtrics.com/support/survey-platform/survey-module/survey-tools/import-and-export-surveys/))

## Researcher flow

Study Library exposes **New study**, **Use template** and **Import design**.
Every study offers **Clone**, **Save as template** and **Export design** under its
actions. An accessible ordered list provides the same commands as cards.

| Action | Outcome |
|---|---|
| Autosave | Updates the current draft with revision checks and visible saved/retry status. |
| Save as template | Creates a named, versioned reusable design in the permitted template library; later template edits do not change existing studies. |
| Clone | Creates a new draft from the explicitly selected draft or published revision. Default name is “Original name — copy”; researcher can rename and choose an authorized destination. |
| Export design | Produces a versioned `.brohn-study.zip` with a contents/dependencies preview. |
| Import design | Validates in isolation, previews what will be created and what needs fixing, then creates a new draft. It never launches collection. |

Opening a historical study defaults to its preserved revision and results.
**Clone this design** is the direct path to another wave, cohort or replication.
The original stays unchanged. Optional comparison of successive waves belongs
to analysis across distinct datasets; cloning never combines their records.

An unchanged design should take one clone action and one destination/name step.
Import uses choose file → review → create, followed by the normal readiness
summary. Remember the last valid destination; expose advanced dependency details
progressively. Provide keyboard operation, labelled file selection, progress,
cancel and a downloadable plain-text validation report.

## Copy contract

**Copy:** study description and editable design; condition/control labels;
practice/baseline/rest blocks; task and questionnaire graphs, branching AST,
translations and scoring keys; timings and frozen participant appearance;
counterbalancing/randomization policy; eligible stimulus bytes and metadata;
AOI geometry/keyframes, coordinate transforms and semantic labels; declared
preprocessing, QC, exclusion and analysis recipe settings; source citations,
method/model versions, required channels, units and device capability profiles.

**Do not copy:** participant/contact/consent-response records, answers, observed
events or recordings, runs, allocations, realized assignment state, results,
run-specific manual exclusions, reports, invites, deployment URLs/tokens,
provider credentials, connection secrets, station identity, participant-specific
calibration or private workspace paths. Consent/instruction *text* may copy;
review it for the destination institution. Templates and exports use the same
design-only allowlist. Show researcher-authored text and attachments for review:
an allowlist cannot guarantee they contain no personal information.

Copy design-level reviewed AOIs with provenance; exclude gaze-derived proposals
unless explicitly converted into a reusable design asset with appropriate
rights and provenance. Preserve design seeds needed to reproduce a randomized
stimulus schedule; reset live allocation state and generate new run seeds under
the declared policy. Do not carry recruitment quotas already filled.

## Portable package contract

Introduce `brohn-study-package/1.0` separately from domain schema versions:

```text
manifest.json           # package/domain versions, lineage, file hashes and sizes
design.json             # canonical declarative design and local references
assets/<sha256>.<ext>    # permitted stimulus/font bytes
aoi.json                # design AOIs and geometry references
recipes.json            # versioned settings and source references
dependencies.json       # required capabilities, models, rights and missing assets
```

The manifest records Brohn/renderer compatibility, original revision hash,
export time, licences/attribution and every included file's SHA-256. It contains
no absolute paths or credentials. Hashes establish integrity, not publisher
trust. Model references include version/hash, source, licence and expected
output schema; SDKs, model weights and API secrets are not bundled by default.
Pinned references remain visible if that engine is unavailable.

Export includes only assets the researcher may redistribute. Otherwise retain
a descriptive dependency and lawful retrieval/replacement instructions, then
label the package **requires assets**. Never silently substitute a stimulus.
External web stimuli retain the intended URL, viewport and interaction profile
after removing credentials/tokens. A URL is not an archival copy: destination
preflight checks availability, login, embedding restrictions and content drift.
Changed content requires researcher review and a new compiled revision.

On import, create new workspace study/revision/entity IDs and an explicit
old-to-new map. Rewrite all graph edges, branching/question references, scoring
keys, stimulus/AOI links and recipe links in one transaction. Preserve original
IDs only as provenance. Asset identity stays content-addressed where permitted;
semantic equivalence ignores remapped IDs while retaining all design behavior.
No reference may accidentally resolve to an unrelated local entity.

## Import safeguards and permission semantics

Parse into a quarantined temporary area with bounded streaming reads. Initial
configurable limits: 512 MiB archive, 2 GiB expanded total, 512 MiB per file,
10,000 entries and 100:1 expansion ratio. Report the exceeded limit rather than
partially importing; larger legitimate designs require an explicitly configured
storage policy, not disabled validation.

Reject absolute/drive/UNC paths, `..`, symlinks, hardlinks, Windows device names,
alternate streams, case/Unicode-normalization collisions, duplicate entries,
encrypted/nested archives and unlisted files. Resolve every extracted path
inside the quarantine root. Check actual streamed size and hash against the
manifest, file signatures against supported types, schema/graph constraints
and total resource budgets. Reject executable files and active embedded content;
unsupported HTML/SVG/script assets become actionable errors. Never evaluate
uploaded R/JavaScript/Python, shell commands, arbitrary URLs or expressions.
Only supported declarative logic reaches the compiler. No automatic package
installation, network asset fetch or model execution occurs during import.

For in-workspace operations, source read plus clone/export permission and
destination create permission are required across projects. Recheck on commit.
An offline package cannot prove a remote source's current ACL; retain its declared
provenance/rights and enforce destination policy without claiming authentication
of its author. Destination roles and retention
policy apply; source ACLs, collaborators and links are not inherited. Shared
asset hashes never grant access; create an authorized reference or copy with
destination retention accounting. Preserve source lineage only where permitted.

Name collisions offer rename; exact package hashes offer **Open existing import**
or **Create another copy**. Default is a new study, never overwrite. A future
“apply to draft” command requires edit permission, a field/asset/logic diff,
expected revision and explicit confirmation; published revisions remain
immutable. Unsupported *capabilities* create a labelled draft with fix tasks;
unknown/unmigratable structural schemas are rejected without dropping fields.

Cancellation, hash/schema failure, disk exhaustion or permission loss leaves no
visible partial study. Commit metadata and authorized object references
atomically, with crash reconciliation for staged bytes and an idempotency key.
Retry resumes safely or restarts validation. Removing a newly imported draft
does not delete shared objects still referenced elsewhere.

## Build ownership and acceptance

| Package | Required evidence before release |
|---|---|
| BWP01 | Versioned schemas/migrations and complete ID/reference remapping; old JSON snapshot still readable. |
| BWP02 | Transactional clone/import, permissions, duplicate retry, interrupted import cleanup and shared-asset retention. |
| BWP03 | Independently specified fixtures prove export/import preserves graph reachability, branch truth tables, controls, timing, seeds, scoring keys, AOIs and recipe settings. |
| BWP05 | Original and imported designs yield equivalent planned sequences and response/scoring behavior under fixed test seeds; deployment and participant state remain new. |
| BWP15 | Student saves template, clones historical design and imports into a fresh project; dependency fixes and keyboard/error recovery work without finding filesystem paths. |
| BWP17 | Roundtrip on a clean supported installation, missing-engine/asset cases, licence manifest and adversarial ZIP fixtures pass; documented limits and compatibility accompany release. |

Use independent expected fixtures, not merely exporter→importer self-agreement.
Cover nested survey logic, repeated stimuli, control/baseline phases, video AOIs,
cross-project asset restrictions and non-ASCII names. A deliberately changed
scoring key, missing asset or graph edge must fail equivalence. Tests prove
software behavior, not scientific validity of every imported design.

Track these alongside [journey acceptance](journey-acceptance.json): scenarios
21 (clone), 22 (templates), 31 (portable roundtrip) and 32 (unsupported or
malicious packages), within the complete [study lifecycle](STUDY-LIFECYCLE.md).
