# Questionnaire export and artifact integrity

Questionnaire observation CSVs contain readable display columns and a
`response_record_json` column. Display columns retain Brohn's existing
spreadsheet-safe prefixes for formula-like text. They are not a type-preserving
interchange format by themselves: numeric `0` and text `"0"`, logical `false`
and text `"false"`, or null and empty text can have identical display cells.

Parse `response_record_json` as JSON to recover each complete original response
row, including native value types, participant/session/assessment identity,
missingness and source fields. The JSON record precedes any spreadsheet display
prefix. It does not contain its own export column. A source field already named
`response_record_json` causes an explicit error instead of an overwrite.
Questionnaire files are written as explicit UTF-8 bytes, including under a
Windows C locale. Non-questionnaire exports retain their previous behavior.

For artifact-backed reports, the download handler first verifies and hydrates
the full analysis. The complete JSON download and original typed NDJSON artifact
also preserve full analysis, including features, distributions, scales and
revision history. On-screen tables and standalone HTML remain explicitly
bounded previews; they must not be used as scientific input.

Publication and hydration require both the source-bound artifact verification
and an exact deterministic comparison of the compact report against its full
analysis. This prevents altered status, usability, counts, titles, displayed
values or extra scientific arrays from changing a valid artifact's meaning.
A questionnaire artifact cannot be published under another analysis family.
Direct promotion requires the frozen report context.

## Scoped evidence

- `tests/platform-questionnaire-artifacts.R`: 62 codec checks, including exact
  reconstruction of a 22,963,103-byte original synthetic report, typed values,
  source binding, explicit limits, cleanup and compact semantic validation.
- `tests/platform-questionnaire-artifact-integrity-review.R`: ten independent
  publication-boundary probes. The initial seven compact corruptions and
  disguised analysis-family case were accepted before their fixes; all now
  reject. The valid original remains accepted.
- `tests/platform-questionnaire-csv.R`: 15 original CSV checks for typed values,
  formula-like text, Unicode, nested values, exact source identities, unchanged
  non-questionnaire output, reserved-field refusal and no report mutation.
- `tests/platform-tabular-utf8.R`: 28 import checks under Windows `LC_ALL=C`,
  including CSV/TSV with and without a BOM, Unicode headers and multiline values,
  malformed UTF-8 and NUL refusal, source limits, valid final rows without a
  terminal newline, and the actual typed questionnaire CSV roundtrip.

These checks start no scientific workers or browser services. Actual supervised
publication, researcher downloads and synthesis have separate integration
evidence. Brohn's tabular reader now marks source bytes as UTF-8 rather than
transliterating them to the process locale, validates encoding, and explicitly
handles an initial UTF-8 BOM. It rejects malformed encoding and parser failures
without repairing the source; valid files without a terminal newline remain
readable. A source-byte upper bound also avoids reserving millions of rows per
column for a tiny file while retaining the declared row limit.
