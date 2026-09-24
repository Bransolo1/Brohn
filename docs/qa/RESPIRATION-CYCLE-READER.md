# Saved respiration cycle reader

24 September 2026. This is the independent complete-source reader evidence;
the connected researcher journey is a separate acceptance gate.

The reader selects one exact recording, continuous segment and channel from a
saved `respiration-displacement-khodadad/1.0` report. It verifies the complete
sample/event artifacts, original recording and retained report references.
Source quantity, inspiration polarity, original clock, effective parameters,
units, source-row bounds and complete-cycle counts must match. It does not run
cleaning, detection or scoring again.

The chart source is the saved **polarity-normalized cleaned waveform**. Its
complete selected sample export preserves original source indices, times,
values and retained/excluded flags. It is not an original signed-input overlay.
Each displayed trough/peak/next-trough marker must match an exact retained
sample in the same continuous segment. Saved phase durations must match their
extrema index differences divided by the declared rate; saved amplitude must
match the original processed extrema. Original timestamps position markers;
these checks do not establish physical synchronization or airflow phase onset.

Selection uses a closed decimal source-time window. A cycle touching the window
retains its complete original boundaries and metrics, including markers outside
the viewport. Empty selections and no detected complete cycles remain different
states; neither invents a zero breathing rate. Display envelopes use actual
endpoints/extrema and separate retained/excluded runs. Complete CSVs contain
all selected samples, intersecting saved cycles and exact marker references.

The supported bounds are500,000 selected samples,5,000 intersecting cycles,
200 support runs,128 MiB per complete CSV,16 MiB result JSON and1 MiB request.
A larger selection fails visibly instead of publishing a truncated result.

`tests/workers/respiration_review.py` passes **16 grouped tests**. Final receipt:
`make/work/test-runs/brohn-respiration-reader-20260924-03/results.json`.
It retains source hashes and the full named-test output outside the repository.

- Every one of6,001 analytic samples,19 hand-labelled asymmetric cycles and
  original source-row indices matches the complete export. Another source
  channel stays excluded; its rows remain in complete-artifact verification.
- Exact2-second inspiration/3-second expiration, amplitudes, marker values,
  display extrema and edge-support runs match independent construction.
- Decimal bounds just beyond a saved sample exclude that sample without
  rounding the request. A partial viewport keeps the full original cycle.
- Empty/no-cycle sources, missing/altered extrema, changed phase metrics,
  clock disagreement, internal gaps, wrong identity/origin/source bytes,
  bounds, file collisions and duplicate request fields are exercised.
- The actual command-line route preserves its result on an output collision.

The first fixture attempt stopped before reading because it lacked the fixture
generator's required implementation hash. That metadata was corrected; there
was no detector run. Receipt01 passes15 groups;02 adds clock-declaration
disagreement;03 adds actual-summary bounds/unit fields needed by the R selector.
Production reader source is unchanged between02 and03. The fixture can be
materialized with `--fixture <new-directory>` for independent R authority tests.

These original analytic signals are not participant recordings, reference
sensor accuracy evidence, tidal-volume calibration or a clinical benchmark.
