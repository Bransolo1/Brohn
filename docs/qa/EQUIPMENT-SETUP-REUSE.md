# Reusable equipment setups

20 September 2026. This extends the qualified
[equipment windows and acquisition checks](ACQUISITION-WINDOW-AND-CHECKS.md).
It is a software reuse and source-review acceptance, not a physical-device,
calibration, physiological-validity or researcher-comprehension qualification.

## Saved definition and current collection

`equipment_setup` is a workspace library entity with immutable versions under
`brohn-equipment-setup/1.0`. Saving a new revision uses the existing store's
compare-and-swap revision boundary. Existing acquisitions keep their exact old
revision and body hash; a concurrent edit cannot silently replace the version
shown in the form.

The reusable body contains a name, the stable LSL source descriptor, every
ordered channel's declared fields, the complete channel XML fingerprint, and
the explicitly authored stream/clock kind, native unit declarations, measurement
family, channel roles/rails, source context, gaze mapping, monitoring selection,
gap threshold and readiness /1.1 criteria. Criteria retain original types,
including text code `001`, source/version/rationale and support requirements.

The complete channel fingerprint uses canonical XML for every original
`<channels>` container, in original order, including container attributes,
ordered declarations and nested vendor extensions. The live UID,
clock creation time and collection origin are outside this channel fingerprint.
The separately hashed stable descriptor includes the source ID/name/type,
nominal cadence, native sample type, channel count and parsed ordered fields.
Changing an otherwise undisplayed vendor channel field still changes the
fingerprint. Older discovery receipts without this fingerprint require a new
metadata discovery before saving or applying a setup.

The definition excludes participant/session/run/deployment identities, collection
origin, LSL session, live UID, live full-metadata hash, source clock identity,
raw metadata XML, process/owner fields, recording limits and approval flags.
An explicit field projection also removes such unsupported nested fields from
channel and criterion inputs. Equipment/source descriptions and researcher-authored
context remain text; this projection does not anonymize text entered by a user.

## Actual researcher workflow

After **Find local sources**, the researcher explicitly selects a source and
opens **Reusable equipment setup** in that source form. Saving creates a
definition only; applying fills pending settings only. Neither action launches
discovery, subscribes to a source, queues recording or schedules analysis.

The selected setup is compared with the current discovered source before
application. Exact stable metadata may match an outlet with a new live UID.
Changes in channel order/name/type/unit, native sample type, cadence, count,
source descriptor or complete channel metadata are displayed and block applying
the channel maps. The current source can instead be configured manually and
saved as a new revision. No channel remapping is guessed.

Application preserves the current clock identity and collection form identities.
It clears every criterion review for that source and the overall recording
approval. Criterion reviews bind the current live UID/full-metadata hash,
criterion, family, role and unit. The overall applied-setup review additionally
binds the current discovery, source configuration and exact setup reference;
changing settings invalidates approval. Start rechecks these bindings, the setup
hash, current metadata, ordinary study revision and explicit collection review.
The recorder still verifies the full live metadata and exact UID at subscription.
Metadata discovery is a snapshot, not a claim that a source remains available.

**Detach setup reference and review current settings** keeps the editable form
but clears its library reference and approvals. A saved setup never authorizes
a collection. Explicitly applied historical revisions remain valid references;
saving over a newer head requires a fresh current revision.

The acquisition catalog freezes per-stream setup ID/revision/body hash, original
setup source/configuration hashes, and the actual reviewed configuration hash
alongside the full current recording request. The recorder request format and
canonical recorded samples remain unchanged. Recording history exposes the exact
references in a disclosure. Original recording archives contain the complete
current request; setup library lineage is retained in the acquisition catalog.

## Executed acceptance

- `tests/acquisition/equipment_metadata.py`: **5 checks** against the production
  descriptor and original offline XML. Restart/origin separation, channel order,
  names, units, types, channel-container attributes, vendor extensions and native
  type are independently varied.
- `tests/platform-equipment-setups.R`: **25 checks** through actual workspace
  storage and two independent study acquisition queues. Covers immutable versions,
  stale CAS, substitution, seven mismatch classes, original text codes, exclusion of
  transient fields, explicit review, historical references and workspace reopen.
- `tests/researcher-equipment-setups.mjs`: **10 journey checks and 4 clean scans**.
  The actual researcher app authors/saves/applies a setup, explicitly detaches/reapplies pending settings, queues and cancels the
  first study, reuses it with a restarted UID in a second study, refuses unreviewed
  Start, clears approvals on edits, rejects a concurrent stale save, freezes the
  chosen historical revision, and rejects changed units in a third study.
  Its exact second-study request then runs through the production durable Writer;
  text `001`, complete source-code support and unqualified physiological status
  are retained. No manager or source subscription is used by this browser fixture.
- Existing `tests/platform-acquisition.R`: **53 checks** pass, including a real
  isolated original LSL outlet and manager, guarded preservation/dataset preparation,
  crash recovery and reopen. Existing `tests/platform-acquisition-window.R`:
  **25 actual Writer/model/rendering checks** pass after integration.

Full browser evidence is outside the repository at
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-equipment-setups-07/browser-evidence-1789884701959`.
The saved-workspace rendering follow-up passes **2 checks and 4 clean scans** at
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-equipment-setups-07/browser-evidence-1789884921492`.
Its narrow screenshots use ordinary viewport captures, avoiding Chromium's
offscreen fixed-element artifact in a tall element crop. Desktop and narrow
pending/difference screens were visually inspected. Both actual queued requests
and the durable replay inspection retain the final recorder SHA-256
`69996fd86ac1abffa7a140d79f8d923a6bfdd7eeb665084a3dde96465b29da8a`.
Desktop and 390-pixel scans report zero axe violations, page overflow or tested
controls below 44 pixels. Metadata differences expose Saved/Current values in
wrapped rows at narrow widths. The final interface also preserves the selected
setup during source-form mounting, refreshes library heads on study entry, scopes
pending references to the exact discovery and UID, and uses sequential recording
monitor headings. Screenshots are inspected separately from automated checks.
Earlier browser runs against the initial per-channel fingerprint are retained
only as development evidence; final acceptance regenerates discovery and queue
receipts against the complete-container descriptor and final recorder hash.

## Scope limits

The selector lists up to 1,000 current setup heads in the workspace. There is no
automatic source matching, implicit subscription, unit conversion, channel-map
repair, device calibration or carryover of approvals. Source metadata differences
require explicit manual configuration. Portable library export, fleet-wide device
profiles, physical timing/calibration and named-device qualification remain separate
work. Brohn's broader PC10 equipment-readiness requirement remains partial.
