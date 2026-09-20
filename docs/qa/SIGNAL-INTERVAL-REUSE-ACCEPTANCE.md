# Reusing intervals on an exact target recording

20 September 2026. This connects saved original interval versions to a new
target-bound set, using a researcher-declared time translation. It copies labels,
categories, notes and boundaries. It never copies observations, scores, source
person/session associations or review approval into the target result.

The original set and scientific artifacts remain unchanged. The new set records
the exact original annotation revision/hash, both report/artifact/catalog/table
identities and clocks, both anchors, mapping rationale, new window identities and
reviewed preview hash. Original identities retained within provenance describe
the source of the labels; the active table and subsequent calculations belong
only to the target. Reuse provenance describes the initial copy in saved revision1;
later edits create new revisions and do not claim those edited bounds still equal
the initial translation. Historical results keep their original annotation revisions.

Every half-open window appears in the preview with round-trip exact boundary
strings. Windows outside the observed target range are not clamped. Unknown
extent stays unknown; observed time extent is not a claim of continuous coverage.
An explicit Apply creates a fresh set within one catalog transaction after
rechecking project authority, original/current source heads, target heads and
the exact reviewed transformation. Changing a source or preview input cannot
silently apply an old transformation. Earlier original versions can be explicitly
selected and reviewed again.

The offset is computed before adding it to individual boundaries, with finite
binary64 residual and duration checks described in the
[method](../methods/SIGNAL-INTERVAL-REUSE.md). This prevents equal huge anchors
from shifting otherwise small intervals. The editor preserves 17-digit boundary
strings, including when an interval is edited and saved unchanged. No clock drift,
physical timing accuracy or synchronization is inferred.

## Executed evidence

- `tests/platform-signal-reuse.R`: **28 checks pass**, including five supervised
  catalog/summary jobs. Three complete independent numerical sources include
  different people, sessions, clocks and values, plus an all-missing-coordinate
  table. Known target means are0 and40; the latter has sample SD20. Real zero,
  missing and excluded samples remain distinct. A separate out-of-range summary
  retains null means rather than inventing zero. Unicode, overlap, positive,
  negative and fractional mappings, equal huge anchors, representational loss,
  malicious preview substitution, stale heads, foreign/archived project refusal,
  unchanged sources and reopening are exercised.
- `tests/platform-signal-reuse-views.R`: **15 checks pass** through actual Shiny
  handlers, after two real catalog jobs. Covers pinned source/target, rationale
  recovery, complete preview, safe text, stale actions, older source versions,
  external changes, navigation and exact-value unchanged editing.
- Independent review: **14 pure numerical/render checks and6 Shiny checks pass**.
  It found both precision defects before acceptance. Received same-value inputs
  retain preview; immediate changed-input/old-Apply batches cannot write. These
  component checks do not establish browser input-debounce ordering.
- `tests/researcher-interval-reuse.mjs`: **15 actual browser checks and3 clear
  desktop/390-pixel scans pass**. Exercises immediate edit/Preview recovery,
  stale Apply, same-value rebinding, complete unclamped preview, keyboard Apply,
  actual target-data summary, JSON/CSV/SVG exports, exact fractional Edit/Save,
  preserved original sources and fresh-session reopen. The source fixtures were
  reused after failed preview-only attempts; the successful run creates exactly
  one new target set and one target-data result. No pending source mutations or
  previous successful calculations were carried into that run.
- Existing `tests/platform-signal-annotations-views.R`: **15 checks pass** after
  integration, including ordinary creation, editing, removal, history restoration,
  cancellation/retry and source-bound navigation.

Evidence roots:

- `C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-interval-reuse-domain-02/acceptance.json`
- `C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-interval-reuse-views-02/views-acceptance.json`
- `C:/Users/User/Documents/Codex/2026-09-20/oka/work/interval-reuse-adversarial-review.json`
- `C:/Users/User/Documents/Codex/2026-09-20/oka/work/interval-reuse-observer-review.json`
- Final browser: `C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-interval-reuse-browser-02/browser-1789884319504/results.json`

The first actual browser runs exposed a different issue: the native numeric
debouncer could send a changed anchor after the Preview click. The server safely
cleared that obsolete preview, but another click was required. The final scoped
`signal-reuse-ui.js` sends the editable visible field values before Preview/Apply;
unchanged rebindings retain the same review. An intermediate attempt resent the
source selector too, which needlessly rerendered the form and reset typed anchors.
The final bridge leaves that already-immediate selector untouched. Failed runs
and measured WebSocket order are retained under `brohn-interval-reuse-browser-01`
and `-02`; the final complete journey exercises recovery and exact visible inputs.

All final scans report no axe violations, page overflow or tested controls under
44 pixels. The exported comparison chart was visually inspected. Owned app,
worker and browser handles closed. All fixtures are original numerical values,
not biological recordings or evidence of human usability.

This does not implement inferred synchronization, multimodal/media replay,
drift correction, pooled-person inference, scientific baseline correction or
device qualification. The current source chooser exposes100 recent nonempty sets
within one project; larger searchable annotation-library work remains separate.
