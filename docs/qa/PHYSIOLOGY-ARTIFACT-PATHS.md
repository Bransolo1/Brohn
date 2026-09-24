# Complete physiology artifacts on long Windows paths

24 September2026. The actual EDA researcher journey exposed a publication
failure after successful analysis: its scratch directory accepted the temporary
file, but appending a modality name and64-character hash exceeded the supported
Windows path length. The exact source/request succeeded from a shorter directory
and failed again at the original native path length. The failed browser run and
three direct diagnostic calls are recorded in
[EDA event review acceptance](EDA-EVENT-REVIEW-ACCEPTANCE.md).

`TableWriter.finish` now uses the first16 hash characters plus `.ndjson` for its
attempt-local filename. This is shorter than the writer's temporary filename.
The full SHA-256, artifact kind, typed contents and provenance remain in the
manifest and header; the permanent object store still uses the complete hash.
An existing prefix is accepted only when full bytes/hash match. A collision or
corruption fails without overwriting that file. Repeated identical publication
remains idempotent. No scientific computation, table schema or original artifact
is rewritten.

The27 existing `tests/workers/physiology_artifacts.py` tests pass using their
appropriate environments:25 in the methods profile, the actual acoustic case
in the media profile and the actual fNIRS case in the acquisition profile.
`tests/workers/physiology_artifact_paths.py` independently checks a215-character
directory, identical complete short/long-path bytes, typed verification,
idempotent repetition and absence of abandoned temporary files. The subsequent
actual long-path EDA import, analysis and first derived review all published
successfully; its remaining browser acceptance has its own record.

These checks cover this filename-growth failure. They do not claim support for
arbitrarily long workspace roots or every external tool's filesystem limits.
