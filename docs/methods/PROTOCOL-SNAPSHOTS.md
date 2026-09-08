# Saved protocol snapshots — Sprint 01L

In Review, **Save protocol snapshot** keeps the current study plan in one portable
file. Both PNGs must be present; AOIs are optional for saving the presentation plan.
The file includes the full study: images and their hashes, any AOIs, controls and
rationale, question wording/options/revisions, and presentation settings.

The interface restores an exact matching snapshot when the draft reopens. Later
draft edits clear the current snapshot indicator while retaining the earlier file.
Saving again creates a snapshot for the new revision. A history browser and
restoring a draft from a protocol export remain future work.

## Contract

`study-protocol/0.1.0` has exactly five root fields: `schema_version`, `status`
(`planned`), `study`, `registry` and `content_sha256`. R owns validation and
registry generation. There is no participant/session record or observed timestamp.

| Registry | Meaning |
| --- | --- |
| trials | One planned trial per A/B condition, with stimulus and exposure references |
| exposures | One planned image exposure per trial |
| epochs | Passive viewing, then optional active response for each trial |
| orders | AB and BA alternatives, or the selected fixed order; each lists trial IDs |

IDs are stable within a protocol: `trial-a`, `exposure-a`, `epoch-a-view` and
`epoch-a-response`, with equivalent B IDs. They are scoped by protocol identity;
they are not globally unique recording IDs. AB/BA reuse the same trial definitions.
The registry arrays define viewing before response within each trial. Viewing
has the planned duration and explicit null question references. Active response
has a null planned duration and the frozen question ID/revision. No question
means no response phase.

The validator regenerates the registry and rejects divergent phases, durations,
IDs, references, orders and question revisions, even if a changed file is rehashed.
Earlier drafts without presentation settings resolve to the versioned five-second
AB/BA preset. Controls retain their A/B identity across order reversal. These
defaults are authoring presets, not a method qualification or recommendation for
every study. Keep passive viewing separate from rating activity during analysis.

## Integrity and local storage

The SHA-256 covers the canonical UTF-8 JSON payload excluding `content_sha256`.
Canonical encoding sorts object keys, retains array order and uses the R encoder's
17-digit number representation. Re-encoded JavaScript JSON is decoded, validated
and canonically re-encoded in R before hashing. Do not hash arbitrary JSON text
and expect an equivalent result. This is the versioned project encoding, not a
claim of RFC 8785 interoperability.

Files are saved beside a draft in `<draft.json>.protocols/<full-sha256>.json`.
Saving identical content is idempotent; the application refuses to overwrite a
different or unreadable snapshot. Cooperating writers use a lock and a
same-directory temporary rename. Reads/writes are bounded to 16 MiB; reads reject
empty, malformed UTF-8, NUL-containing, corrupt or invalid documents.

This is application-level preservation, not a filesystem write lock, signature,
authorship proof or preregistration. External software can still alter/delete
files. Hashes detect content differences; they do not establish who approved a
plan. Normal backup and power-loss durability remain separate work.

## Boundary and next increment

The snapshot preserves intended procedure. It does not play stimuli, allocate
participants, establish achieved counterbalancing, measure onset, introduce
repeated exposures or certify an analysis recipe. Existing observation events
are not yet validated against this planned registry. Before acquisition, bind
sessions/events to an exact protocol hash and validate their references; implement
participant preview, persistent order allocation and observed timing separately.

Native tests cover registry corruption, study/image changes, phase separation,
control roles, fixed/counterbalanced orders, no-question studies, Unicode and
portable integer limits. Storage and Shiny tests cover idempotence, errors,
reopening and preservation after edits. Cross-language checks retain the content
hash. These are implementation checks, not participant or scientific validation.
