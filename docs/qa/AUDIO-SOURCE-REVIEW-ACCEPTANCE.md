# Audio source review

This slice adds a source waveform and spectrogram to a saved acoustic report.
The existing `audio-praat-acoustics/1.0` analysis, pitch, RMS and centroid results
remain unchanged. The connected researcher route has separate domain, native
worker, browser journey and fresh-process evidence. This establishes the
software workflow on original synthetic sources, not human acoustic validity.

The review decodes the exact retained WAV/FLAC/OGG and the same channel selected
in the saved report. It uses native sample indices and digital full scale (FS),
without channel mixing, resampling, amplitude calibration or nonfinite-value
replacement. SoundFile's documented frame and channel model underlies this
reader. [SoundFile 0.13.1](https://python-soundfile.readthedocs.io/en/0.13.1/).

The spectral view uses full periodic-Hann windows, no detrending or padding,
and one-sided density in FS²/Hz. Interior positive-frequency bins are doubled;
DC and the even-length Nyquist bin are not. Time labels identify original
source samples and full-window centres. Complete native spectral cells export
separately from the display's contiguous arithmetic-mean bins. The independent
reference uses SciPy's periodogram with the same declared window and scaling.
[SciPy periodogram](https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.periodogram.html).

Waveform envelopes retain each bin's minimum/maximum and their actual sample
positions. The exact selected sample CSV includes every original decoded value.
Silence stays zero; a selection shorter than one complete window has an empty
spectral result. Neither view supplies speech activity, emotion, attention,
speaker identity, calibrated sound pressure or perceived loudness.

## Executed worker checks

`tests/audio-review-worker.py` passes **34 checks**, including:

- PCM16 integer-to-FS decoding and explicit stereo-channel selection.
- All 128,000 selected samples and 161,398 native spectral cells beyond display
  bins; exact exported means, sample positions and contiguous coverage.
- Analytic DC/sinusoid frequency and integrated power; independent SciPy
  comparison and odd/even one-sided edge-bin scaling.
- Exact decimal half-open boundaries, short windows, silence and over-full-scale
  floating-point samples; source and manifest hashes.
- Invalid headers/channels/hash/windows, nonfinite source, duplicate request
  fields, output collision, and preallocation sample/cell bounds.
- Actual command-line success and structured error handling.

Final evidence: `make/work/test-runs/brohn-audio-worker-20260924-02/results.json`.
Fixtures are original analytic signals, not participant speech or an acoustic
sensor accuracy benchmark. The first attempt's near-zero density comparison
used an overly strict absolute tolerance. Its retained diagnostic records a
maximum absolute difference of `1.3877787807814457e-17`; the corrected test uses
a floating-point roundoff bound scaled to the reference density. The worker's
calculation was unchanged by that correction.

Initial bounds are 512 MiB encoded source, 20 million total decoded channel
values, two million selected samples, two million native spectral cells, and
128 MiB per exact CSV. Display bounds are 1,000 waveform bins, 120 time bins and
80 frequency bins. Larger or differently encoded sources need their own profile;
no truncated analysis is substituted for a refused request.

## Source authority and domain checks

`tests/platform-audio-review.R` passes **28 checks** in
`../../work/test-runs/brohn-audio-domain-20260924-05/results.json`.
The test writes PCM16 bytes independently of the production decoder and checks
all selected values, half-open sample bounds, complete spectral support, source
and project substitution refusal, saved channel/method binding, missing source
support, figure provenance and exact numerical alternatives. Standalone Data
library audio retains absent study provenance; an invented frozen study fails.
Warm structural-validation caching does not cache source or project authority.

The original recipe stores effective parameters under its sole recording ID.
The review verifies that recording-specific block and keeps its saved spectral
frame length, hop and selected channel. It neither rescores the acoustic report
nor changes its original dataset. Source and retained artifact read guards stay
open for active session downloads, with fresh project/catalog checks at each
action. Selection changes, navigation and forged URL tokens revoke access.

## Connected researcher evidence

The reproducible fixture/harness are `tests/fixtures/researcher-audio-review.R`
and `tests/researcher-audio-review.mjs`. All source media, workspaces, exported
data, screenshots and receipts remain outside the repository in
`../../work/test-runs/brohn-audio-browser-20260924-01/`.

The source fixture contains a three-second original stereo PCM16 tone and a
separate standalone silent recording. Two actual acoustic jobs generated the
saved reports. Four actual review jobs and two saved signal-catalog jobs later
completed successfully; the original acoustic report hashes remain unchanged.

Browser attempt `browser-1790222983717/failure.json` retains **21 completed
checks** and four axe/reflow scans with zero violations or page overflow:
desktop tone, mobile tone, eight-sample window and standalone mobile silence.
The completed checks include every one of 24,000 selected stereo sample values
against original integer bytes, all native spectrum rows, SVG source identity
and exact minimum-sample x positions, stale/forged download refusal, half-open
window changes, the explicit empty spectrum for short input, identical saved
reopening, and links to the same report's saved RMS/centroid and pitch frames.
Numerical pagination keeps its disclosure open, restores keyboard focus and
retains the same plot DOM nodes. Current desktop/mobile/short/silence figures
and the paged numerical table were visually inspected.

That attempt then failed its default five-second heading assertion after a
cold application restart. It is **not an all-in-one passing run**. A separate
fresh-process check in `browser-1790223410351/results.json` reopened the exact
complete manifest and byte-identical sample CSV, confirmed all eight jobs
terminal, and created no new jobs. Cold reopening measured **8.23 seconds**;
this remains a performance limitation. The focused harness now records elapsed
reopening time and permits 30 seconds rather than claiming a five-second SLA.

Additional focused receipt `browser-1790223675726/results.json` confirms actual
mobile SVG label bounds. The waveform has viewBox `0 0 320 310`, rendered size
350 by 339.0625 CSS pixels; every text box is within that viewBox. Its time-axis
title ends at native y=294.657, below the 310 boundary. The actual screenshot
includes all time ticks and "Seconds from source start" without clipping.
`mobile-waveform-geometry.json` retains live native and screen rectangles plus
the displayed SVG. These focused runs repeat reopening, not acoustic scoring
or the earlier accessibility scans.

Earlier retained attempts document harness defects: element screenshots cannot
target Shiny's `display: contents` output wrapper; the underlying selectize
`select` is intentionally hidden; an SVGRect needs explicit x/y/width/height
serialization rather than `toJSON`. Those corrections changed test observation,
not acoustic arithmetic. No failed receipt was overwritten.

Accepted visual/domain source hashes for the split evidence above:

- `R/platform-audio-review.R`: `1c002be5ad3e8fa7a083702ebe57a2d91a30e0d3350e61c232df4725c3ebea50`
- `R/platform-audio-review-views.R`: `b23f63d1efaef8475a0050c5853c0d10b67f1dba7589629d063cf102368380b1`
- `scripts/workers/audio_review.py`: `728a4d7ae363b9e6dbad5d5e9ebbe3a8166b43968762baaf952844b35d0bc09d`

The subsequent video-audio integration adds derived-source lineage to the R
domain. Its connected acceptance is tracked separately in
`VIDEO-AUDIO-EXTRACTION-ACCEPTANCE.md`; the earlier hash is historical evidence,
not a claim that this later source extension was covered by those browser runs.
