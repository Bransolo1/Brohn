# Morlet baseline duration and event separation

20 September 2026. This is software/reference acceptance for a named analysis
policy. No hardware, device synchronization or universal research qualification
is claimed.

## Why the recipe changed

The earlier `eeg-morlet-epochs/1.0` recipe allowed a power baseline with two
samples, complete epoch-edge support and an endpoint at event onset. An
independent zero-before-event, impulse-at-onset construction demonstrates that
the nearby baseline can nevertheless contain wavelet energy from the event.
Successful computation did not establish a suitable pre-event reference.

[Keil et al. (2022), §3.2.6](https://onlinelibrary.wiley.com/doi/10.1111/psyp.14052)
discuss baseline length, temporal smearing and separation from event activity.
The guidance motivates displaying the actual duration and temporal resolution.
It does not supply one universal duration suitable for every protocol. Brohn's
new requirement for complete finite-kernel separation is a conservative
product policy; it is stronger than a one-temporal-standard-deviation rule and
must not be described as a universal consensus cutoff.

## Frozen contract

New researcher mappings select `eeg-morlet-epochs/1.1`. With an enabled power
baseline they must supply this additional object:

```json
"adequacy": {
  "policy": "complete-pre-event-wavelet-support/1.0",
  "minimum_cycles": 4,
  "rationale": "Study-specific justification goes here; four is an example, not a preset."
}
```

There is no populated UI default for either duration or rationale. The
researcher declares the minimum in cycles at the lowest analysed frequency.
The numeric bounds constrain the input representation, not scientific
adequacy. A baseline disabled as `{"mode":"none"}` needs no duration declaration
and cannot carry ignored settings.

For enabled baselines the worker requires:

1. At least two actual sampled centres, preserving the old computational bound.
2. The last sampled centre minus the first, multiplied by the lowest requested
   frequency, meets the explicit duration criterion. Declared endpoints outside
   sample centres do not create extra observed duration.
3. Every selected baseline coefficient has complete finite Morlet kernel
   support inside the epoch.
4. The latest source sample used by every such coefficient lies strictly before
   the event sample. A kernel touching the onset sample fails. Each requested
   frequency is checked, including higher frequencies with longer cycle counts.

The report retains frequency, wavelet cycle count, temporal sigma
`n_cycles/(2*pi*frequency)`, actual discrete kernel length/half-support, baseline
cycle coverage, centre separation in sigma units, latest kernel sample time,
edge support and event separation. It also retains the observed sample count,
first/last centre, duration convention, minimum, rationale and filter identity.
Duration and support failures publish unavailable results with these diagnostics;
no window is silently moved. The UI offers earlier baseline, longer epoch or no
power-baseline routes. The first remedy addresses event overlap; the second
addresses missing epoch support. Neither automatically establishes suitability.

The denominator floor remains separate. A perfectly separated zero-power
baseline still yields unavailable transformed values when it cannot support
the declared floor. Raw power remains available where otherwise supported.

The policy isolates **finite wavelet support only**. Acquisition filters and
the existing forward/backward zero-phase preprocessing can spread activity
backward before this step. Timing uncertainty, unrelated events, stationarity,
artifact handling and study-specific baseline assumptions still need review.
`scientifically_qualified` remains false.

## Historical results and presentation

Explicit `/1.0` requests remain registered for reproducibility. Their numerical
path and saved outputs are not silently upgraded. The saved plot labels the old
policy's missing checks; editing a new mapping selects `/1.1` and explains the
required review. This is not a retrospective claim that every older result is
invalid.

The `/1.1` report presents actual duration, cycles and per-frequency support
beside the plot, including unavailable results with no trace. The view checks
saved diagnostics against frozen grid and recipe metadata; it never recomputes
power or repairs the baseline. Complete CSV, structured channel export and SVG
description retain the policy/diagnostic record. Source and report hashes stay
unchanged through selection, download and reopen.

## Executable evidence

| Test | Independent expectation |
|---|---|
| `tests/workers/neural.py` | 33 checks pass, including an onset-only impulse that contaminates the legacy nearby baseline but is refused by `/1.1`; sufficiently early zero baseline stays below the denominator floor. |
| Exact grid boundary | At 100 Hz, the 10 Hz/three-cycle kernel has 23 samples of half-support; a baseline centre at −0.23 s reaches onset and fails, while −0.24 s can pass. |
| Actual duration | The nominal window [−1.005, −0.5] s contains centres spanning 0.5 s, or five 10 Hz cycles. A declared 5.01-cycle minimum fails. |
| Frequency-specific support | A higher requested frequency with a longer wavelet can fail even when the lowest frequency passes; eligibility is not inferred from frequency order. |
| Constant-amplitude sine | The saved baseline power ratio is independently expected to be one; phase and source-voltage units retain their existing checks. |
| `tests/platform-neural-baseline.R` | 27 checks pass: researcher controls → frozen mapping → two actual supervised jobs → successful and unavailable saved reports → diagnostic/plot/download checks → reopen; no fabricated result fixtures. |
| `tests/platform-neural.R` | Existing 44 contract, labelled control and actual ERP supervisor checks pass. |
| `tests/platform-neural-views-plots.R` | 67 checks pass for actual ERP, historical/reviewed Morlet and tagging results, complete maps, typed masks, exports, readable baseline support and Shiny source guards. |
| `tests/researcher-neural-baseline-map.mjs` | Fresh actual researcher/browser journey passes 21 checks and six accessibility/layout scans, including missing-declaration recovery, unavailable near-onset result, corrected new report, maps/slices/downloads and both saved reports reopened unchanged. See [map acceptance and exact evidence path](NEURAL-TIME-FREQUENCY-MAP-ACCEPTANCE.md). |
| `tests/researcher-neural-plots.mjs` | Browser harness now declares duration/rationale explicitly and asserts observed cycles, separation and visible caveats. Its new assertions require a fresh application run; earlier browser evidence does not prove them. |

For the wider per-measurement limits and remaining reference/hardware gaps, see
[the academic acceptance audit](MEASUREMENT-ACADEMIC-ACCEPTANCE.md).
