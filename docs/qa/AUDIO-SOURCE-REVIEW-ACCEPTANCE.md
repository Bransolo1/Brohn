# Audio source review — active integration

This slice adds a source waveform and spectrogram to a saved acoustic report.
The existing `audio-praat-acoustics/1.0` analysis, pitch, RMS and centroid results
remain unchanged. R/browser integration is in progress; the worker evidence
below does not establish a completed researcher journey.

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
