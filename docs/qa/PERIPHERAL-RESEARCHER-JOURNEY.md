# Calibrated peripheral data: actual researcher journey

This browser journey uses original synthetic values, Chrome, the actual Shiny
researcher application, durable source ingestion and production analysis/view
workers in an isolated workspace. It does not use mocked APIs, physical devices
or observed human participants. Numerical foundations and reference sources are
documented in the [independent method review](PERIPHERAL-INDEPENDENT-REVIEW.md).

The completed journey passes **48 assertions and eight accessibility scans**.
Fourteen actual durable jobs settled: five source ingestions, five individual
analyses, one combined analysis, one signal catalog and two signal previews.
Thirteen succeeded; the deliberately duplicated-clock analysis failed as
expected with its source retained and no report. All five successful report
catalog bodies exactly match their retained publication envelopes and hashes.

Evidence is retained at
`../../work/test-runs/brohn-peripheral-ui-leyspE/evidence/results.json`, SHA-256
`198759423034fa89333d141beb39b50b8fa5ed7148c7293c11d0ff257b0494c5`.
All owned runtime processes stopped after the checks; no queued or running job
remained in this workspace.

## Original study and arithmetic

The researcher creates a controlled comparison through the UI, names standard
and easy-grip refill packs, authors both text stimuli and the liking question,
and selects temperature, movement and questionnaire measures. The experimental
control remains separate from the physiological baseline setting.

The source generator writes fresh CSV cells after reading that saved design's
actual IDs. Source prefixes `temp-`, `motion-` and `like-` distinguish modalities;
the reviewed identity mapping later links four fictional people (`001`–`004`)
and five visits. Person `001` has two visits; source rows and visits are never
treated as extra people.

| Source | Independent expected result |
|---|---|
| Temperature in °F | Thirty original rows, 27 usable, three missing; nine supported three-sample intervals spanning 18 observed seconds. Converted Celsius means are 30,32,30,36,30,38,30,42,30. |
| Temperature excursions | Explicit entry at or above35°C, strict recovery below34°C, one-second observed minimum. Three two-second censored excursions; no default physiological interpretation. |
| Temperature comparison | Visit differences2,6 for001,8 for002,12 for003;004 has no usable test interval. Equal-person estimate8°C, three people and four paired visits. |
| Ordered acceleration in g | Thirty-one rows,28 usable, ten supported intervals. The first control exposure has two fragments separated by an eight-second nominal missing interval. Constant vectors have zero within-interval derivative. |
| Acceleration plot | First source table has four measured samples at0,1,10,11seconds, all magnitude9.80665m/s². The full view contains two fragments; inclusive1–10seconds retains two separate points. |
| Explicit liking | Ten ratings; visit differences1,3 for001,2 for002,4 for003,1 for004. Equal-person estimate2.25points, four people and five paired visits. |
| Combined analysis | Temperature and liking keep their different valid denominators. Fragmented acceleration within the same actual exposure makes that comparison unavailable. All three declared hypotheses remain in the Holm family. |
| First-time slow import | Three original Fahrenheit samples at0,10,20seconds convert to a21°C mean. A blank support field at0.1Hz automatically freezes10seconds, retains20observed seconds and leaves the unrequested event count unavailable. |

The acceleration fragmentation is deliberate: this tests the absence of silent
within-exposure averaging. It does not propose a segmentation or pooling recipe
for consumer research.

## Actual operations checked

The harness verifies that file transfer alone creates neither an ingestion nor
a dataset. It waits for the displayed upload review and its bound identity,
clicks **Import this file**, then observes background preservation and automatic
navigation into the prepared source mapping. Imports from the Data library stay
unlinked until the researcher explicitly chooses the saved study revision.

A duplicated temperature clock is preserved but fails analysis with an explicit
reason and no report. The corrected source is a separate original. Missing
temperature conditions/settling context is rejected before queueing; the
researcher can explicitly record that the context is unknown. ENMO refuses a
gravity-removed source declaration; correcting it preserves the exact ordered
source axes. Calibration, source filters, signed axes and context are original
generator declarations, not independently established sensor properties.

Successful reports are checked against retained source hashes and exact
catalog-versus-publication-envelope contents. Complete typed sample/event
artifacts, feature CSV, JSON/provenance and standalone HTML are downloaded.
The actual signal explorer uses immutable full artifacts, preserves gaps and
custom range controls through worker completion and viewport changes, and
exports its chart and view provenance.

The combined-study route explicitly selects three immutable reports, uploads a
reviewed15-row person/session crosswalk, records its evidence and declares three
comparisons. A fresh browser session must reopen the original mapping, source
download and unchanged report. Desktop and390-pixel checks inspect accessibility,
page bounds and visible Shiny errors.

## Findings and retained continuation

The actual low-frequency browser route found a product defect: a visibly blank
numeric support field arrived through Shiny's numeric binding as `null`; the R
adapter rejected the resulting logical missing value. The UI promised an
automatic duration but rejected confirmation. No mapping, analysis job or report
was created by that failed action. The original source remained unchanged.

The adapter now accepts that scalar missing value while keeping explicit
too-short values and malformed inputs invalid. A narrow browser continuation
confirmed the same saved source without entering a duration, processed its
independent21°C result, then reopened the mapping showing the resolved10seconds
and unchanged original bytes. The original failure is retained as
`original-slow-blank-failure.json` and `.png`; the actual browser binding is
recorded in `slow-mapping-bound-inputs.json`.

This is a cumulative checked journey, not a claim that one uninterrupted script
passed on the first attempt. The first source checkpoint retained24 assertions
and four scans. A harness label correction resumed the exact verified source
reports and completed the plot, liking and comparison path. The blank-input
retake resumed42 assertions and eight scans after independently rechecking all
four prior report envelopes and source identities. Checkpoints, failed evidence
and the final result remain together. No source or report was regenerated to
replace a failed result. Export filenames now include dataset IDs to prevent
same-modality downloads from overwriting each other during later runs.

## Harness and limits

- [Browser harness](../../tests/researcher-peripheral.mjs)
- [Original source generator and owned service fixture](../../tests/fixtures/researcher-peripheral.R)

Run from the repository root with the prepared Node runtime:

```powershell
& 'C:/Users/User/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe' tests/researcher-peripheral.mjs
```

The fixture starts its own researcher, participant, worker and acquisition
manager processes, uses dynamic loopback ports and stops only those owned
processes. It leaves its original workspace and evidence for audit. It neither
records from a device nor claims scientific qualification, human comprehension
or a production deployment.
