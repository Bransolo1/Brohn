# Known constant-signal EDA counterexamples

28 September 2026. **Open BWP09 / PC16 scientific-method finding.** Reproducing a counterexample is not acceptance of the current detector or a replacement. This evidence does not qualify devices, physical timing, participant inference or an EDA–liking estimator. The [versioned remedy plan](../methods/EDA-CONSTANT-SIGNAL-NEXT.md) remains pending internal scientific evidence/design review.

## Recorded behavior

The unchanged `eda-neurokit-highpass/1.0` producer at baseline `dd4afb6b28326626c49b1e03d10e988a05d7ca4f` records an `exact_flatline` flag but continues scoring. It detects peaks using prominence relative to the largest prominence, without an absolute conductance threshold. Exact-constant input can acquire floating-point variation during cleaning and decomposition, which the relative detector can count. This establishes a numerical counterexample; it does not identify the contribution of every filter operation or establish a scientific noise floor.

An earlier genuine synthetic source containing 500,100 samples at 10 Hz and constant 5 µS produced 166,634 candidates. Its original report retained the flatline flag, `scientifically_qualified:false` and `requires_research_review:true`. The original freeze SHA256 is `a1640b0e4d634915cfaf3fadc30969dda552a27a248be25ca096ac3dab5e7378`. That large source was used for resource/lifetime testing; its faithful export is not detector validation. It is not bundled into the repository.

The portable diagnostic uses five formula-generated arrays of 1,200 samples at 10 Hz. Counts below are after the unchanged recipe's edge exclusions:

| Input | Observed current 1.0 result |
|---|---|
| Exactly 0 µS | Both direct detector and recipe call raise an empty-maximum `ValueError`. |
| Exactly 0.5 µS | 500 retained candidates. |
| Exactly 5 µS | 334 retained candidates; cleaned range ≈8.88e-16 µS, phasic range ≈1.80e-15 µS. |
| Exactly 500 µS | 333 retained candidates; a numerical stress case, not a representative participant recording. |
| Alternating 5 and its next representable float | 250 retained candidates; one-ULP input range, not a real-response witness. |

The zero-input exception is observed at direct function level; this diagnostic does not create a report or exercise the outer worker's unavailable-result conversion. No source data, algorithm, threshold, saved scientific result or historical export was repaired. In particular, it does not replace candidate counts with zero or classify a constant recording as a valid nonresponse.

## Reproduce separately from readiness tests

Use the prepared methods interpreter with CPython **3.12.10**, NumPy **2.5.3**, SciPy **1.18.1** and NeuroKit2 **0.2.13**. From the repository root:

```text
python -B tests/eda-flatline-counterexamples.py . ../qa-output/eda-flatline-new
```

`REPO` may instead be any repository checkout path. `FRESH_OUT` must not already exist and must be outside that checkout. The script disables bytecode writes before third-party imports, creates only its external evidence directory, hashes the worker and six installed NeuroKit source files before/after, and preserves inputs. It opens no store or service and uses no external dataset.

**Exit 0 means `known_counterexamples_reproduced`.** Both scientific and replacement qualification fields remain false. This is an explicit diagnostic, not a readiness check or a target that a new recipe must reproduce. Another runtime, changed method or unexpected outcome exits nonzero with a retained diagnostic receipt; assess it rather than deleting the assertions to obtain a pass.

One fresh run completed **23 checks across five cases** in the recorded Windows methods environment. All seven inspected source hashes were unchanged. Reproduction receipts may differ in host metadata, paths supplied by a caller, or checkout line endings; scientific outcomes and the exact inspected implementation must be assessed together.

| Evidence | SHA256 |
|---|---|
| Portable script, as executed | `5d822d7404ba920ccd9fd03b55a6082ab8a73493cda5af3a2639590ded6304ac` |
| Fresh portable `results.json` | `e4b11135910ee93234c63d6338f418cc7913c0fa8090c67b3c52eab62b290b0a` |
| Inspected `scripts/workers/physiology.py` | `64a98a8b8efa4445543dd9dfe4033285643d5559841d4eceab3d401a7f16a9db` |
| Earlier small-witness closure | `8b9374da25eefc3fac6fac62bbe46388b79db0754dfeb0d4132ccb22c85bbc4a` |

The earlier preflight created an import bytecode cache; it was preserved with that external evidence and removed from the baseline. The final portable run disables cache writes. A separate earlier console-summary attempt failed on locale-default decoding of UTF-8 prose; it did not affect numerical results and was retained. These phases are not relabelled as replacement-method acceptance.

Until the new method's numerical and scientific gates are met, preserve the original flags and saved values, explain the limitation, and keep historical 1.0 bytes unchanged. The [cardiac package plan](../architecture/SAVED-CARDIAC-REPORT-NEXT.md) is an independent pending export slice and does not resolve this finding.
