# Saved-report comprehension

The report presentation now uses the saved outcome label when available, then
the exact question or scale in the report's frozen design, restricted to its
registered questionnaire metric namespace. A temperature channel that happens
to share a question ID cannot inherit that question's prompt. A small named metric
dictionary describes supported physical quantities. Unknown measures retain an
explicit source ID instead of receiving a guessed construct. Canonical values
are unchanged; display notation uses °C, m/s² and m/s³ where applicable.

Unavailable comparisons state the actual reason and an appropriate source-review
step. Duplicate participant/session/condition/exposure identities are explained
as uncombined records; fragments keep their real presentation identity. A
descriptive effect can remain visible while the card explains why an uncertainty
interval is unavailable. People, paired sessions, exclusions, intervals,
multiplicity and statistical limitations retain their original values.

Combined-report coverage now describes available reports and the declared
comparisons with an uncertainty interval and p-value. This wording follows the
actual stored `estimable_comparison_count`, which counts available tests, not
every non-null descriptive effect. Each measure's separate eligibility remains
explicit. All original quality fields, including counts and booleans, remain in
**Inspect complete coverage counts**. Source metric IDs, original units and
reason codes remain in **How this comparison was calculated** and unchanged
data exports.

## Executed checks

- **22 scoped R checks** exercise frozen labels, priority/fallback behavior,
  units, exact effect/interval/count display, unavailable and descriptive cases,
  technical details, unknown support reasons, escaping and rendering purity.
  Four follow-up cases cover physical-channel/question/scale ID collisions
  found during independent parent review; the saved browser fixture's labels
  remain unchanged by that namespace correction.
- The existing **10 offline HTML checks** pass without changed expectations.
- **17 actual browser checks and five accessibility scans** pass against the
  existing peripheral study. The app and standalone HTML both pass desktop and
  390-pixel checks; expanded technical counts also pass at 390 pixels.

The saved report still shows the independent 8°C difference across three people
and four paired sessions, and 2.25 rating points across four people and five paired
sessions. The fragmented acceleration comparison remains unavailable within the
three-comparison Holm family. The liking title comes from the saved original
question, and the physical titles name the actual quantities without an emotion,
arousal, health or latent-trait interpretation.

The retake used Shiny only and launched no scientific worker. Its JSON remained
equal to the original immutable report, and its CSV bytes matched the earlier
researcher download. All five report envelopes and hashes, dataset revisions and
source hashes, and complete job histories were equal before and after. Original
temperature and acceleration reports also reopened unchanged. The owned Shiny
process stopped after the checks.

Evidence:
`../../work/test-runs/brohn-peripheral-ui-leyspE/presentation-retake/results.json`

SHA-256:
`e5f366b3cfa40c96e889fd85e36e69f001f51d2bdc7e971b476fdba69cbb0072`

This is presentation acceptance using original synthetic study data. It does not
claim observed human comprehension, device accuracy or new scientific validation.
The retained scientific result was never regenerated to obtain this evidence.

Files:
[presentation](../../R/platform-data-views.R),
[scoped checks](../../tests/platform-report-comprehension.R),
[browser retake](../../tests/researcher-report-comprehension.mjs),
[read-only service fixture](../../tests/fixtures/researcher-report-comprehension.R).
