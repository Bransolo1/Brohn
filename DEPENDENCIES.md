# Dependencies and validation

## Connected local platform

The current runtime lock contains **46 exact CRAN package versions**, including
SQLite, subprocess supervision, cryptography and archive support. Direct runtime
dependencies are listed once in `scripts/runtime-dependencies.R`; the lock
includes their transitive dependencies. R 4.6.1 on Windows is the executed native
profile. A fresh isolated restore and namespace/source/license check passed for
all 46 packages with zero extras. This check concerns dependency metadata and
loadability, not scientific or redistribution qualification.

Use [local installation](docs/operations/LOCAL-INSTALLATION.md) for explicit
restore and readiness commands. `run-local.ps1` launches the connected workspace
by default; `-Legacy` runs the old prototype. `tests/platform-*.R` and the
researcher browser journeys cover the connected platform; `tests/all.R` retains
the historical 773-check suite and does not run every new platform test.

Scientific jobs invoke separately configured Python environments. Their exact
requirement files live in `scripts/benchmarks/requirements-methods.txt` and
`scripts/readiness/requirements-{acquisition,media,segmentation}.txt`.
Vision models and codecs are separate assets outside the repository. The
participant runner uses original JavaScript and browser APIs. The jsPsych
development packages below are preparation/reference tools.

## Historical preparation and prototype checks

The [large-build toolkit](docs/preparation/LARGE-BUILD-READINESS.md) adds isolated
acquisition/neuroscience, R storage/statistics, SurveyJS/jsPsych, vision/audio and
compatible segmentation environments. Exact pins, downloads and commands are in
[acquisition](docs/preparation/ACQUISITION-TOOLING.md),
[platform](docs/preparation/PLATFORM-TOOLING.md),
[media](docs/preparation/MEDIA-TOOLING.md) and
[segmentation](docs/preparation/SEGMENTATION-TOOLING.md) records. Their 101 new
reference assertions are separate from the earlier 81 scientific references and
the application checks below. Models and package caches remain outside the repo;
these environments are not activated application dependencies.

[Brand assets](docs/brand/BRAND-SYSTEM.md) include a local Manrope variable font
under its included SIL Open Font License and original SVGs. The static preview's
31 contrast-pair checks and desktop/narrow axe scans are visual-development
evidence, not whole-product accessibility certification. See
[verification.json](docs/brand/verification.json).

Optional scientific development tools now have separate isolated environments:
MNE 1.12.1, NeuroKit2 0.2.13, CVXOPT 1.3.2 and R gaze/implicit libraries.
[Benchmark setup](scripts/benchmarks/README.md) records exact versions, commands,
81 targeted assertions and scope. These do not change the application dependencies
below or enable physiology processing in the UI. See the
[analysis register](docs/methods/reuse/README.md) before adding runtime wrappers.

| Direct dependency | Tested version | Purpose |
|---|---|---|
| jsonlite | 2.0.0 | JSON and portable image base64 |
| shiny | 1.14.0 | Researcher application and server tests |
| bslib | 0.12.0 | Bootstrap theme |
| png | 0.1-9 | PNG validation/fixtures |
| digest | 0.6.39 | Image, source and protocol content SHA-256 |

In R: `install.packages(c("jsonlite", "shiny", "bslib", "png", "digest"))`.
This installs available versions, not version pins. Prefer the tested renv.lock
and explicit restore/check scripts in docs/preparation/R-TOOLING.md for exact
versions. The lock contains 32 CRAN packages and their licence declarations;
full redistribution review and the project's source licence remain release work.
Wire tests use built-in Node modules; browser tests now use pinned dev dependencies
from package.json/pnpm-lock.yaml. See docs/preparation/TOOLING.md.

Native Windows testing uses R 4.6.1 and Node 24.19.0. The isolated R executable is
../../work/native-r/bin/Rscript.exe and packages are in ../../work/r-library.
run-local.ps1 locates that fallback without changing the global PATH. Earlier
contract checks also passed through webR 0.6.0 / R 4.6.0; its temporary runtime
remains in work/sprint1-runtime. No device/timing qualification is implied.

From the repository root with native R and Node available, PowerShell:

```powershell
$env:CONTRACT_FIXTURE_DIR = Join-Path ([System.IO.Path]::GetTempPath()) 'research-platform-contracts'
Rscript tests/all.R
if ($LASTEXITCODE -ne 0) { throw 'R checks failed' }
node tests/check-wire.mjs "$env:CONTRACT_FIXTURE_DIR"
if ($LASTEXITCODE -ne 0) { throw 'JavaScript checks failed' }
Rscript tests/verify-return.R
if ($LASTEXITCODE -ne 0) { throw 'Return-to-R check failed' }
Rscript examples/sample.R
Rscript examples/reproduce-sample.R "$env:CONTRACT_FIXTURE_DIR/sample-report.node.json"
Rscript examples/reproduce-import.R "$env:CONTRACT_FIXTURE_DIR/import-report.node.json"
```

The environment variable enables export of synthetic fixture JSON only. Without
it, `Rscript tests/all.R` runs R checks without writing fixture files. JavaScript
checks arrays (including singleton and empty arrays), nulls, response identities,
origin and a timestamp larger than its safe integer range. It re-encodes the
bundle; R then validates and compares it with the original. The report fixture
also preserves control/presentation settings and is recalculated from the
JavaScript-returned inputs. tests/all.R includes Shiny workflow checks.
Protocol fixtures also preserve a canonical content hash across R/JavaScript/R,
including Unicode and maximum portable question revisions. The suite now has
773 counted domain/numerical checks plus storage/report/JSON/server assertions.
On 2026-09-08 the complete R/wire/reproduction suite passed against a fresh
restored library. Six desktop/narrow browser checks also passed, including axe
scans of Library/Review and a synthetic jsPsych execution check. That scan coverage
is not a whole-product WCAG assessment or physical timing qualification.
