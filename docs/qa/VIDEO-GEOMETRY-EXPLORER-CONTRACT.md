# Saved video geometry explorer: proposed bounded contract

20 September 2026. Read-only audit and implementation proposal. No explorer
production code or successful-person/pose/hand fixture has been implemented or
qualified by this document. The preceding cardiac review interface is accepted
separately in `CARDIAC-ARTIFACT-REVIEW-UI.md`.

## Observed starting point

- `scripts/workers/vision.py` already writes the complete immutable
  `vision-observations` JSONL. Every analysed frame has its original zero-based
  decoded frame index, decimal source PTS string, recording-relative seconds,
  model timestamp in milliseconds, and selected face/pose/hands observations.
  Native landmark arrays remain in that artifact. The report contains only the
  first 2000 compact observations or 2 MiB, whichever comes first.
- The worker accepts source files up to 512 MiB, 2–36000 decoded frames, at most 600 seconds of source PTS
  span, at most 4K pixels per frame and at most 2 GiB of complete observations.
  It rejects missing/reversed/duplicate PTS, model-millisecond collisions,
  non-square pixels, encoded rotation and changing frame dimensions. Relative
  time subtracts the first source PTS; it is not a participant/browser clock.
- Saved parameters include original dimensions, no-autorotation policy,
  selected channels, model settings, support-gap cutoff and PTS origin. Saved
  engine provenance includes MediaPipe 1.0.1, model hashes, Python/packages and
  matching FFmpeg/FFprobe versions. This is evidence already written by the
  current worker, not a proposal to change models or numerical analysis.
- Generic report tables/downloads expose saved features, a bounded observation
  preview and the complete artifact. `platform-vision-views.R` implements AOI
  proposal review; it is not a saved face/pose/hand result explorer. No connected
  successful-geometry timeline, complete frame page or image-bound landmark view
  was found. Existing generated non-face camera evidence correctly demonstrates
  insufficient support, not successful geometry visualization.

## Minimal complete researcher workflow

1. From a saved video report choose **Explore video measurements**. Open its
   complete, verified artifact and show the selected source, analysed interval,
   model/version and complete frame count. Reports without a complete artifact
   explain why the explorer is unavailable; never expand the compact preview
   into supposed complete data.
2. Choose face, pose or hands, then one actually saved metric. Show a labelled
   numeric time plot, units, valid frame/time support and a separate frame-state
   timeline. An unavailable metric stays unavailable; no missing-to-zero
   conversion. Empty/absent-only data still has a useful state timeline and table.
3. Select a frame by exact frame index, keyboard previous/next or a paged table.
   Show exact source PTS, recording-relative time, model time, saved states and
   values. A plot click is a convenience selecting an actual saved frame; it
   cannot invent an interpolated frame. Native numeric landmark detail and exact
   frame JSON remain accessible without relying on a chart.
4. Show the actual decoded recorded frame with optional saved landmark overlay
   only after exact frame binding passes. A normalized coordinate-plane view is
   useful when video bytes are unavailable, but must visibly say that no recorded
   frame is displayed. Missing/multiple/invalid detections have their own state
   and do not acquire an invented skeleton.
5. Download exact selected metric rows, original selected frame records and a
   labelled view figure. Advertise complete/selected/exported counts and source
   identity. A figure export includes units, interval, support and display
   reduction; it is not the complete numeric dataset.

The first implementation covers all three enabled geometry families and custom
channel selection. It does not require continuous video playback, tracking a
person across frames, cross-recording overlays or new inference.

## Source authority, derived index and bounded access

Use new vision-specific modules; do not pass this distinct JSONL through the
physiology artifact reader. A supervised catalog job makes a derived immutable
index once. Read in bounded lines rather than loading the JSONL into R or the
browser. The index contains original frame/PTS identity, channel states, exact
metric values, source line offsets/lengths/hashes and a small channel catalog;
native landmark arrays remain in the original artifact and are fetched one
verified frame at a time. An index failure leaves the original report available.

The immutable binding includes project, report ID/revision/body hash, dataset
ID/revision/body hash where present, original source object hash/bytes, complete
observation object hash/bytes, selected saved parameters/engine and explorer
schema/recipe/code hashes. Resolve all records from the store; never accept a
browser-supplied path or scalar as source authority. Native camera-derived video
retains its existing assembly/dataset/report lineage. Historical report binding
uses its saved source version and cannot silently switch to a remapped dataset.

Validate the complete stream before publishing the index: declared channels,
strictly increasing original frame indices and decimal PTS, source bounds,
recording-relative/model clock relationship, finite/null field types, permitted
states, landmark shapes and complete frame/channel state/valid counts against the
saved report. Preserve original numeric lexemes for exact export/detail; floating
display coordinates do not become the numeric authority. Refuse duplicate keys,
unknown incompatible schemas, oversized lines and mismatched counts/hashes.

Proposed engineering bounds to qualify: original source bounds unchanged; 1 MiB
maximum observation line, 128 distinct saved metrics, 100 frame rows per page,
one full native frame per detail response, at most 2 MiB per browser response,
and at most 2000 displayed numeric points. Index byte bound and row overhead must
be established with an adversarial maximum supported fixture before release;
no acceptance may call memory/storage bounded solely because preview rows are
bounded. If any response needs more, return an explicit narrower request/detail
download state rather than silently truncating.

Catalog publication uses existing staged parent-owned publication, short writer
transactions, cancelled/stale job fences and deterministic reader closure.
Reopen verifies index structure/counts/hash and exact source binding. Retained
native read handles must prevent source/index mutation during page, range and
frame reads. Cursor tokens bind index, source, channel/filter and ordering.
Changing report/channel/range clears current selection and pending output
authority. Retry can reuse only an identical frozen request. Corrupt index
rebuild is explicit; no corrupt/incomplete cache may be displayed.

## Plot and state semantics

Plot only saved metric values that pass that metric's saved validity rule.
Segments break at invalid/missing endpoints, nonconsecutive analysed frames or
the saved maximum-support-gap boundary. Preserve separate fragments under
reduction. Within each contiguous valid fragment, chronological first/min/max/
last representatives can bound the display; label reduction and original counts.
If fragments alone exceed the display budget, request a narrower interval.
Never merge across invalid samples merely to meet the display limit.

The state timeline reports counts per time bucket and saved state, distinguishing
mixed buckets, absent, multiple, invalid/border geometry and insufficient visible
joints. It must not paint a mixed/unknown bucket as valid. The final frame has no
invented duration. Time support uses the saved adjacent-endpoint/gap policy;
frame counts and supported seconds are different measures. Family-valid and
metric-valid denominators also remain distinct.

Display the existing `valid` flag as **Passes saved geometry rules**, with those
rules available, not as physical accuracy or physiological usability. Model
detection/presence/tracking settings and per-point visibility are distinct
quantities. Missing model confidence must not be fabricated. A count at the
configured detector cap is a lower bound, displayed as such.

## Exact recorded-frame and landmark binding

A separate supervised frame extraction request freezes the catalog/report,
original video hash, original decoded frame index and exact source PTS. Verify
against the original decoded stream, not a seek time estimated from FPS. Decode
the same video stream and encoded-pixel orientation under the saved compatible
FFmpeg/FFprobe profile, verify actual PTS and dimensions, and retain the decoder
version/hash and extraction receipt. Reject unsupported decoder mismatch rather
than claiming an exact image/landmark match.

Publish the selected frame as an immutable PNG with source-frame provenance.
Preserve original aspect ratio and record any explicit image downscale transform;
overlay x/y transform by the same image rectangle. No CSS mirroring, implicit
rotation or arbitrary aspect stretch. Original image dimensions plus exact
landmark coordinates remain visible in the numeric route. Image-plane z is a
native model coordinate, not calibrated depth; no 3-D metric distances are
invented. Native pose/hand world arrays are not currently saved by this worker
and cannot be reconstructed from the normalized arrays.

Face points/geometry and native blendshape coefficients retain their saved names.
Pose bones connect only actually saved, valid endpoints; validity and clipped
points remain explicit. Hand overlays use each frame's native handedness and
score. Duplicate same-hand labels may still be individually inspected as frame
observations, but cannot become a continuous left/right metric series. There is
no stable identity tracking. Border-invalid native points may be inspected with
their invalid status; they are not silently corrected or treated as valid.

## Provider references and pinned scope

Checked 20 September 2026 against primary provider documentation:

- [MediaPipe Face Landmarker](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker)
  describes 478 estimated landmarks and 52 blendshape coefficients, including
  rendering uses. The saved worker requests two faces and masks multiple-face
  metric output. Its native coefficients remain coefficients; this explorer
  adds no FACS, emotion, attention, happiness, calibrated gaze or rPPG claims.
- [MediaPipe Pose Landmarker](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker)
  distinguishes 33 normalized image landmarks from world-coordinate outputs.
  Brohn currently saves normalized landmarks and image-plane elbow angles;
  do not relabel them calibrated biomechanical joint angles or world positions.
- [MediaPipe Hand Landmarker](https://developers.google.com/edge/mediapipe/solutions/vision/hand_landmarker)
  distinguishes handedness, image coordinates and world coordinates. Its
  detection/presence/tracking confidence settings serve different pipeline
  purposes. Brohn's saved geometry is an image-plane distance ratio, not force,
  dexterity, physical hand size or a tracked person identity.

Use the existing versioned model manifest `docs/preparation/media-models.json`,
not its mutable `latest` URL alone:

| Model | Provider generation | SHA-256 |
| --- | --- | --- |
| Face landmarker | 1683136941468629 | `64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff` |
| Pose landmarker lite | 1682624738331272 | `59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a` |
| Hand landmarker | 1682480005356399 | `fbc2a30080c3c557093b5ddfc334698132eb341044ccee322ccf8bcf3607cde1` |

The explorer reads the report's recorded pins and never silently upgrades them.
This audit does not claim provider recommendations qualify Brohn measurements.

## Concrete acceptance required

1. Independent JSONL oracles: more than 2000 frames; nonzero/large decimal PTS
   origin; nonuniform intervals; valid, absent, multiple, border, low-visibility,
   duplicate-handedness and missing-metric frames. Check complete counts, exact
   scalar/page/export equality, final frame, gaps and no fabricated zero/line.
   Use hand-calculated geometry/denominators in addition to native-output replay;
   do not compare two calls to the same production mapper.
2. Recorded successful face, pose and hand cases through the current pinned
   worker, saved report, explorer and export. Use permitted public/reference
   fixtures stored outside the repository with source/license/hash attribution.
   Inspect actual overlays and compare every rendered selected landmark/value
   to its complete saved JSONL record. This proves software/source agreement,
   not model accuracy on a population. Retain non-face insufficient support.
3. Exact image binding: nonzero PTS, frame skipping at selected interval start,
   variable cadence and visibly distinct frame markers. Verify selected pixels
   against an independently decoded reference and original index/PTS, including
   first/final analysed frames. Reject mismatched source, rotation, dimensions,
   PTS and decoder profile. No browser capture clock is substituted.
4. Store/process acceptance: native writable-before/denied-during/writable-after
   controls, missing/corrupt artifact/index, cross-project/source/cursor changes,
   retry/rebuild reuse, stale/cancelled publication, crash rollback, reopen and
   backup/restore. Stream a maximum-support artifact to measure actual memory,
   index storage and bounded browser payload; close readers on error as well.
5. Actual researcher browser: open successful and absent reports; switch channel
   and interval; inspect a frame beyond compact preview; keyboard previous/next;
   exact values and full selected export; saved image/overlay and figure download;
   changed selection while a job finishes; desktop and 390 px axe/reflow/44 px
   scans plus visual inspection. Exact tables must stay legible and horizontally
   scroll with the keyboard where necessary.

No physical camera, gaze calibration, emotion inference or detector-accuracy
qualification is implied by these software/reference tests.

## Proposed ownership and integration

New isolated files: `R/platform-vision-explorer.R`, a pure index reader/builder if
needed, `R/platform-vision-explorer-views.R`,
`scripts/workers/vision_explorer.py`, focused worker/store/browser tests and this
QA contract. Keep existing vision numerical code unchanged unless a demonstrated
source defect is separately reviewed.

Root-owned coordinated wiring: loader/child source closure; registered catalog
and frame job dispatch/resource supervision/publication artifacts; saved report
entry point and renderer installation. Agree exact request/receipt schemas and
artifact/index byte limits before wiring. No shared source changes while the
current combined participant journey holds the scientific source freeze.
