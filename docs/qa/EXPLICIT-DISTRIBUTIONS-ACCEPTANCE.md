# Complete questionnaire and scale distributions

Brohn's saved questionnaire report now has **Explore response distributions**.
One supervised preparation reads the complete retained source, including scale
assessments beyond the report preview. The researcher then selects a question or
scale and an exact condition without rerunning scoring. The original report,
responses, scoring keys and complete source downloads remain available.

## Interpretation and source contract

- Quantitative question types are frozen `number`, `slider` and numeric-valued
  `rating` definitions. Numeric codes in nominal choices do not acquire a mean.
  Responses are checked against their original item definitions without coercion.
- Other values have typed category counts. Boolean false, numeric zero and text
  zero remain different. Arrays and objects are whole saved values, including their order;
  these are not checkbox-option or matrix-item marginal frequencies.
- Saved scale scores require the supported original recipe, matching frozen
  design/key hashes, original units and consistent scored/not-scoreable states.
  Distribution preparation never rescores, fills missing items or changes keys.
- Each plot counts eligible records within one item and exact saved condition.
  Source assessment counts require explicit person/session/assessment identities.
  A missing assessment identity withholds the total rather than inferring one.
  Person counts require complete explicit linkage. Repeat records within an
  assessment are disclosed; repeat visits do not become independent people.
- Omitted, not-displayed, unsubmitted, invalidated and other retained states stay
  separate. Answered/scored values rejected by typed validation have their own
  exclusion count. Absent expected records are not invented. A group with no
  eligible values has no fabricated zero-valued score or chart.
- Numeric plots have ten equal-width full-range bins: lower bounds included,
  upper bounds excluded except the final bound. A constant value has one bin.
  Mean, median and range describe eligible records, not an independent-person
  estimate, population norm, reliability coefficient or validated latent trait.

The complete questionnaire index reader verifies original artifact bytes and
revision evidence before exposing final effective records, including hidden
states retained in a revision. Packed scale observations are hydrated from the
complete artifact, never from its inline preview. Native guarded publication
pins report/project/revision/body, original retained objects, analysis identity
and implementation hashes. Reopening checks authority and retained output bytes.

## Interaction and export

The native item/condition selector supports keyboard use. Category charts and
exact tables show 20 rows per page, with explicit totals and previous/next
controls. Bar scales remain fixed across category pages. All chart labels have an accessible exact table; mobile figures are
rendered separately rather than shrinking desktop text.

CSV includes every distribution row, canonical typed values or exact numeric
bin boundaries, record denominator, source/assessment/person counts, exclusions,
linkage, missing states and source hashes. Formula-like human labels have a
spreadsheet-safe prefix; canonical values remain unchanged. UTF-8 fields are
written as quoted bytes so Windows C locale cannot transliterate responses.
An empty distribution produces a header-only CSV; its unavailable states and
support remain in the UI and complete distribution JSON. JSON retains the whole
selected group and policy; SVG retains the visible page and source metadata.

Preparation accepts at most 250,000 combined effective answer/score records,
10,000 distinct categories per group, 512 MiB complete source and an 8 MiB
serialized saved result. The supervised process has a 1 GiB sampled resident
memory/scratch profile and a 300-second deadline. CSV uses a conservative 32 MiB
upper bound before writing; larger exports are rejected without a partial CSV,
and the complete distribution JSON remains available. These are bounded support
profiles, not qualification of every possible input at their maximum sizes.

## Reproducible checks

- `tests/platform-explicit-distributions.R`: 29 focused checks pass under Windows
  `LC_ALL=C`, including independent arithmetic, typed values, missingness,
  denominators, mixed-key rejection, original source preservation, frozen scale
  provenance/eligibility, UTF-8 CSV bytes and pre-write export bounds.
- `tests/fixtures/researcher-explicit-distributions.R` prepares a fresh synthetic
  workspace, runs actual supervised jobs and records receipts. The source has
  180 answers and 60 original two-item scale assessments in two conditions,
  compared with zero scale rows in the inline preview. Thirty categories per
  condition include false/zero/text/Unicode/formula values. The original scoring
  key reverses its second item; an independent oracle expects twice the first
  item for each complete assessment. Missing/hidden items remain ineligible.
- `tests/researcher-explicit-distributions.mjs` follows the actual saved-study to
  report to distribution route and independently checks all eight groups, exact
  CSV/JSON downloads, SVG provenance, category paging, keyboard interaction,
  390-pixel reflow, automated accessibility and actual SVG text intersections.

## Executed connected evidence, 24 September 2026

The final corrected implementation passes 14 actual supervised-worker checks,
11 connected researcher-browser checks and six desktop/390-pixel scans. The
scans have zero axe violations, page overflow, controls below the tested 44-pixel
height or SVG text bounds/intersection defects. Full numeric, category and scale
chart screenshots were also visually inspected. The browser uses all eight
question/scale-condition selections, pages all 30 categories, downloads every
distribution and reopens the saved report without adding a job.

An independent Python standard-library audit recomputes the complete analysis
hash, validates all eight actual CSV exports (120 distribution rows), checks
numeric bins against source responses and independently keyed scale arithmetic,
retains typed Unicode/formula values, and parses provenance from all nine SVG
downloads, including the second category page. Reproduce with
`tests/verify-explicit-distribution-exports.py <fixture-folder> <browser-folder>`.

Local evidence is outside the repository:

`C:/Users/User/Documents/Codex/2026-09-05/make/work/test-runs/brohn-explicit-distributions-20260924-02`

- `worker-evidence.json`: final supervised receipts and 14 assertions.
- `worker-evidence-before-provenance-check.json`: retained earlier worker run.
- `snapshot.json`: unchanged original report hash, all jobs and resource audit.
- `browser-1790219063566/results.json`: final 11 checks, six scans and downloaded
  artifact list. SHA-256:
  `dea96fbcc0dabb0b2e9f13a9a22ead44ceab6aca02f92a3bb39d8740f8aedf7c`.
- `browser-1790219063566/independent-export-audit.json`: independent source/export
  receipt, SHA-256:
  `d73b7173c4de396cb25187dda237bc344abc3cdeac6b9258fea9f01cfa9751f4`.
- The same browser directory retains viewport and full-chart images, exact
  CSV/JSON/SVG downloads, six accessibility reports and the researcher log.

The final source analysis hash is
`6d5d0e9c0fc97313fd280d5df2f3da0739645b9b86dafa590bc23c41acfc69e5`;
the unchanged saved report hash is
`78557623cfaa2ff50b9b48063b87ac33e380e0c353e5994e9f6722b1099a0e2f`.
The final successful supervised preparation took 14.91 seconds, with sampled
peak resident memory of 163,045,376 bytes and sampled scratch of 264,892 bytes.
Those are measurements of this fixture, not maximum-size performance evidence.

Job accounting is explicit: the corrected fixture retains two successful
derived preparations, two queued cancellations and two intentional deadline
failures across the initial/final implementations. Both final complete browser
executions reused those saved outputs and created zero jobs. No jobs are queued
or running, and the owned researcher service on port 3883 was stopped. The
earlier incorrect fixture has one separate terminal derived job; no original
research store was used or changed.

Earlier attempts are retained outside the repository. The first synthetic
fixture incorrectly assigned conditions to end-of-study assessments; the
original scorer correctly marked them not-scoreable. The corrected source uses
explicit after-stimulus assessment identities. The first browser exports exposed
a real Unicode CSV transliteration defect; the UTF-8 byte serializer fixes it.
Neither correction changes original stored source data or scale scores.

This is synthetic application, numerical and automated accessibility evidence.
It is not human usability research, psychometric validation or device evidence.
