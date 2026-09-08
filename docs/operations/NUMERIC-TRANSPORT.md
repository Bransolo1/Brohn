# Exact numerical transport

Brohn uses the same 17-digit finite binary64 encoding for new protocol/report
JSON, catalog scalars, job requests and numerical cells in machine CSV exports.
Human-readable tables may round their display; retained results and downloads do
not use those display strings as their source.

This corrects a real integration defect: the pinned JSON library's `digits=NA`
scalar encoding rounded some catalog values that the report envelope retained.
Independent arithmetic tolerance cannot justify a serialization difference.
`tests/platform-json-precision.R` passes 24 checks, including 525 ordinary,
extreme, subnormal and generated numbers, adjacent representable values and
exact CSV round trips. Fresh MaxDiff report and import browser journeys verify
exact catalog/envelope/download agreement with the corrected writes.

Historical catalog JSON and its hashes stay byte-for-byte unchanged. Existing
operation receipts can replay only their retained decoded values, original
identity, project and expected revision. A nearby value already rounded away in
an old record cannot be recovered or treated as equivalent. Historical job
requests must pass their original raw hash before compatibility comparison.
Comparison space can accommodate a longer modern encoding of a near-limit old
record; new writes still obey the existing 16 MiB entity and 4 MiB job bounds.

This is a transport contract. It does not establish the correctness of an
analysis algorithm, acquisition clock or model interpretation. Those retain
their independent reference examples and method-specific evidence.
