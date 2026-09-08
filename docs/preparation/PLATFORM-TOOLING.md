# Brohn platform build tools

Prepared 2026-09-08. These installed, pinned tools support the larger build's
storage, isolated jobs, statistics, questionnaire engine and browser tasks.
They are development references outside the application environment. The current
Shiny app, its `renv.lock`, and its JavaScript dependencies were not changed.

## Installed and exercised

| Area | Exact selected packages | Concrete evidence | Build use |
|---|---|---|---|
| Local metadata/journal | DBI 1.3.0, RSQLite 3.53.3 | Transaction, replay, conflicting replay, rollback, foreign key and decimal timestamp probes | Transactional study/session/job/event indexes; raw streams remain content-addressed files |
| Isolated work | processx 3.9.0 | External R success/failure; real R-to-Python JSON request/reply | Separate worker process with bounded request, timeout, captured logs and explicit exit status |
| Analysis graph | targets 1.12.0 | Known result and zero outdated targets after execution | Reuse unchanged preprocessing/analysis outputs when explicit inputs match |
| R workers | crew 1.3.2 | One actual local worker returns a synthetic sum | Bounded local concurrency behind the durable job contract |
| Inference | lme4 2.0-6, emmeans 2.0.4, effectsize 1.0.3 | Paired B-A estimate, SE and d-z equal hand arithmetic; upstream mixed-model example replay | Prespecified contrasts, hierarchical models and named effect-size conventions |
| Questionnaire statistics | psych 2.6.5 | Raw alpha equals independent variance formula, 0.9375 | Explicit scale recipes, reliability diagnostics; package arithmetic does not validate a scale |
| Questionnaire execution | survey-core + survey-js-ui 2.5.41 | Rendering, branches, required rules, zero/false, hidden-answer clearing, matrix data, completion and definition roundtrip | MIT Form Library behind Brohn's own accessible questionnaire builder |
| Browser tasks | jspsych 8.3.0 + 15 exact plugins | Every selected browser bundle loads with matching name/version | Reusable trial primitives for a versioned protocol compiler |

There are **66 isolated R packages**, including dependencies, and **26 JavaScript
packages**. The **22 R and 29 browser assertions pass**. These 51 assertions are
library/integration references, separate from earlier scientific benchmark counts.
Results: [R](platform-results-r.json), [browser](platform-results-web.json).

The R/Python seam preserves `raw_tick="9007199254740993"`, explicit JSON `null`,
the declared `microvolt` unit, and a known numeric result. It uses a small request
file and standard-output JSON reply through `processx`; no production job API is
being claimed. The Python executable is the already isolated methods environment;
only its standard library is used by this probe.

## Architecture choices for the big build

**R remains authoritative.** R validates the frozen study, analysis recipe,
units, contrasts, masks, exclusions and output schema. A process worker performs
expensive R or Python calculations and returns typed results plus provenance.
The Shiny session observes job progress; it does not run a blocking EEG job inside
a button callback. Use database-backed job identity, status, attempts, leases,
cancellation and output commit rules. `crew` dispatch and `targets` caching sit
behind that contract; installing them does not supply crash recovery or exactly-once
execution. The current probes exercise one worker and one database connection.
[targets architecture](https://books.ropensci.org/targets/crew.html),
[DBI transaction API](https://dbi.r-dbi.org/reference/dbWithTransaction.html).

Use a unique operation ID plus canonical payload hash. A replay with the same
payload can return the prior outcome; reusing an ID with different content must
fail. Keep raw device ticks as decimal text and carry clock mapping separately.
The synthetic journal tests both rules. SQLite is a local metadata choice; large
signal arrays belong in immutable file storage with hashes and chunk indexes.
Concurrent writes, migrations, simulated termination and recovery are later
acceptance tests, not conclusions from these simple probes.

Cache identities must include raw data hash, recipe and engine versions,
parameters, unit/clock mapping, AOI/mask revisions, baseline/control definitions,
and output schema. A cached result becomes stale when any of those change.
Do not rely on a package upgrade alone invalidating a graph. Keep statistical
contrasts prespecified and named, with participant/stimulus structure, missingness
policy, confidence intervals and model diagnostics. Preserve B-A direction; do
not use automatic pairwise defaults to choose the scientific question.
[emmeans contrast API](https://rvlenth.github.io/emmeans/reference/contrast.html).

**Survey execution and authoring are separate components.** The installed MIT
Form Library supports a declarative questionnaire engine. Survey Creator,
Dashboard and PDF Generator have separate commercial licensing and were not
downloaded. Brohn should build its own authoring interactions over its canonical
R questionnaire schema and compile supported definitions to the execution engine.
The current registry probe finds 19 question types, including text, comment,
choice, checkbox, dropdown/tagbox, boolean, rating, ranking, matrix variants,
repeating panels, multiple text, image choice and expression. File/signature
registration is only a capability inventory; upload storage and permissions need
their own design. [SurveyJS licensing](https://surveyjs.io/licensing).

The official npm `v2-lts` version is **2.5.41**; latest is **3.0.3** at inspection.
The jsPsych survey plugin 4.0.0 depends on SurveyJS `^2.3.12`. Pinning both Form
Library packages to 2.5.41 gives one compatible version rather than introducing
an unreviewed major-version migration. Exact registry metadata is represented in
the lockfile; revisit this selection as a deliberate upgrade.

The probe explicitly uses `clearInvisibleValues="onHidden"`. This clears an
answer when branching hides its question. Therefore Brohn must retain a separate
append-only exposure/response/revision journal. An absent answer by itself cannot
distinguish not shown, skipped, declined, invalid, interrupted or cleared after
a branch change. Preserve valid numeric zero and boolean false. Assign stable
question/option/row IDs; join responses to protocol phase and stimulus exposure
without inferring relationships from display order. Use declared reverse coding,
minimum answered items and scale version in R; no automatic scale validation claim.
[SurveyJS branching semantics](https://surveyjs.io/form-library/examples/conditional-logic-and-branching-in-surveys/documentation).

Selected jsPsych primitives include HTML/image keyboard, HTML button/slider,
canvas keyboard, audio/video keyboard, HTML/image IAT, survey, browser check,
fullscreen, preload, reconstruction and serial reaction time. Exact versions are
in [package.json](../../scripts/readiness/package.json). They can support task
templates such as priming, interference, inhibition and memory; the template still
needs its own stimulus mapping, balancing, controls, event log and scoring method.
The existing IAT review found first-response latency is not sufficient for the
selected correction-inclusive scoring procedure. Preserve that adapter requirement
from [IMPLICIT-REUSE](../methods/reuse/IMPLICIT-REUSE.md). Loading plugins establishes
availability, not display timing or response-device qualification.
[jsPsych plugin interface](https://www.jspsych.org/v8/overview/plugins/).

## Restore and run

Run from the repository root. All generated data and binaries stay outside the
repository under `../../work`. JavaScript restore uses the exact package manifest
and `pnpm-lock.yaml` under `scripts/readiness`; copy both to
`../../work/tooling/research-web-tools`, then run:

```powershell
pnpm --dir ../../work/tooling/research-web-tools install --frozen-lockfile
node scripts/readiness/platform-web-reference.mjs
```

The browser probe uses the existing root Playwright installation and installed
Chrome in an isolated headless context. `PLAYWRIGHT_CHANNEL` can select a supported
alternative. No persistent user browser profile or real participant data is used.

R package identities, versions, licenses and exact CRAN Windows binary URLs are in
[platform-r-packages.json](../../scripts/readiness/platform-r-packages.json).
Pinned Windows R 4.6 binary ZIPs are cached in
`../../work/tooling/research-web-tools/r-binaries`; their SHA-256 values and sizes
are in [the download manifest](platform-results-downloads.json). This is a local
byte fingerprint, not an upstream signature. Preserve the cache for an offline
restore; CRAN's current binary URLs may stop serving older versions.

Use R 4.6.1 with `R_LIBS_USER` set to the isolated target library. In R, after
creating that library, a cached restore is:

```r
lib <- normalizePath("../../work/r-library-platform", winslash = "/")
zips <- list.files("../../work/tooling/research-web-tools/r-binaries",
                   pattern = "\\.zip$", full.names = TRUE)
install.packages(zips, lib = lib, repos = NULL, type = "win.binary")
```

Verify ZIP hashes against the download manifest before restoring. For another OS
or R minor version, resolve/build the same versions separately; these Windows
binaries are not cross-platform archives. Restore commands are provided; an
independent fresh restore of this new 66-package environment has not been run.

```powershell
$env:R_LIBS_USER = (Resolve-Path ../../work/r-library-platform).Path
$env:R_USER = (Resolve-Path ../../work).Path
$env:LC_ALL = 'C'
& ../../work/native-r/bin/Rscript.exe --vanilla scripts/readiness/platform-reference.R
```

`--library`, `--python` and `--output` can select explicit paths for the R probe.
All selected packages installed successfully. During initial probe construction,
the crew wait call was corrected to its installed public argument name
`seconds_timeout`; the final local-worker check passed. No application code,
runtime lockfile, paid service credentials or participant media were changed.
