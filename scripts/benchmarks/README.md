# Method reference benchmarks

Research preparation recorded 2026-09-08. Run from the repository root. These scripts use public upstream examples, independent arithmetic and synthetic contract probes; they are not loaded by the application. Results contain aggregates and provenance, not source participant rows. See the [method register](../../docs/methods/reuse/README.md) for scientific scope and adoption decisions.

## Installed environments

| Environment | Location from repository root | Pin / evidence |
|---|---|---|
| Python 3.12.10 venv | `../../work/tooling/methods-venv` | [38 pinned packages](requirements-methods.txt); MNE 1.12.1, NeuroKit2 0.2.13, CVXOPT 1.3.2. `pip check` passed. Version pins are not a wheel hash lock or a fresh-machine restore test. |
| R 4.6.1 | `../../work/native-r/bin/Rscript.exe` | Application helper library `../../work/r-library` supplies jsonlite/digest. |
| Gaze library | `../../work/r-library-methods` | saccades 0.2-1 at commit `bb55d203a09eb6b942058d08f4df697bdb440486`, zoom 2.0.6. Detector/helper hash checked. |
| Implicit library | `../../work/r-library-implicit-methods` | IATscores 0.2.8, implicitMeasures 1.0.0; 57 installed packages/version declarations in the result artifact. Scorer hashes checked. Transitive R dependencies are observed, not separately locked/restored. |
| Node 24.19.0 | Existing local runtime or PATH | Facial contract uses built-in modules only. |

No global PATH, application library, camera or device configuration was changed. The Python venv and R libraries are local preparation dependencies, not runtime requirements in Brohn's application `renv.lock`.

## Rerun commands

PowerShell, using the installed workspace paths:

```powershell
$methodPython = '../../work/tooling/methods-venv/Scripts/python.exe'
$methodRscript = '../../work/native-r/bin/Rscript.exe'
$env:R_USER = (Resolve-Path '../../work').Path
$env:R_LIBS_USER = (Resolve-Path '../../work/r-library').Path
$env:LC_ALL = 'C'

& $methodPython scripts/benchmarks/physiology-reference.py --data-dir ../../work/method-reference-data --output docs/methods/reuse/physiology-reference-results.json
if ($LASTEXITCODE -ne 0) { throw 'Physiology reference mismatch' }
& $methodPython scripts/benchmarks/eda-deconvolution-reference.py --output docs/methods/reuse/eda-deconvolution-results.json
if ($LASTEXITCODE -ne 0) { throw 'EDA decomposition reference mismatch' }
& $methodRscript --vanilla scripts/benchmarks/gaze-reference.R
if ($LASTEXITCODE -ne 0) { throw 'Gaze reference mismatch' }
& $methodRscript --vanilla scripts/benchmarks/implicit-reference.R
if ($LASTEXITCODE -ne 0) { throw 'Implicit reference mismatch' }
node scripts/benchmarks/facial-contract.mjs
if ($LASTEXITCODE -ne 0) { throw 'Facial contract mismatch' }
```

The physiology script downloads two bounded public examples only if absent, validates SHA-256, and keeps them in the supplied external cache. Always give `--data-dir` a path outside the repository. Both files are pinned to NeuroKit commit `ff419d983568ef492eb8d229af643c0ef0100b32`. Package-bundled R examples remain in the external R libraries. Never copy those raw rows into the repository.

To recreate Python tooling in a **new** isolated environment, use Python 3.12, then install `scripts/benchmarks/requirements-methods.txt` and run `pip check` followed by the benchmarks. Platform wheel availability is not established on Linux/macOS. The gaze script's optional `--install` targets its isolated library and pinned source commit. Recreate implicit libraries with exact package archives and compatible dependencies; do not upgrade the app library or assume an unpinned `install.packages()` restores this environment.

## Results and interpretation

| Script | Result artifact | Passed | Scope |
|---|---|---:|---|
| `physiology-reference.py` | [Physiology](../../docs/methods/reuse/physiology-reference-results.json) | 18 | Analytic EEG/HRV; public EDA regression; ECG/RSP smoke. |
| `eda-deconvolution-reference.py` | [Deconvolution](../../docs/methods/reuse/eda-deconvolution-results.json) | 6 | Noiseless synthetic recovery plus default/kwargs behavior. |
| `gaze-reference.R` | [Gaze](../../docs/methods/reuse/gaze-reference-results.json) | 20 | Pinned upstream fixture/settings and segmentation sensitivity. |
| `implicit-reference.R` | [Implicit](../../docs/methods/reuse/implicit-reference-results.json) | 29 | 162 bundled D1 values, hand cases and reproduced package limitations. |
| `facial-contract.mjs` | [Facial](../../docs/methods/reuse/facial-contract-results.json) | 8 | Published time example, synthetic shape/missingness; no inference. |

Total: **81 assertions**. Known upstream failures are tested as observations; they do not mean those behaviors are acceptable in Brohn. A changed package/source hash, numerical mismatch or unexpected warning must be investigated before updating an expectation. Preserve tolerances and evidence type in the output.

The original pNN50 analytic expectation used a successive-difference denominator. Source inspection established the pinned NeuroKit denominator instead; the results retain both conventions and the correction rationale. The cvxEDA check similarly records effective helper defaults because the public wrapper drops custom kwargs. Neither finding was hidden by claiming a generic successful API call.
