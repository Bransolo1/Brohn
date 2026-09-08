# Contributing to Brohn

The implementation is paused at the **8 September 2026** checkpoint. Read
[John's handoff](docs/HANDOFF-JOHN.md), [STATUS.md](STATUS.md), [AGENTS.md](AGENTS.md)
and the relevant section of the [master architecture](docs/MASTER-ARCHITECTURE.md)
before changing a workflow. The roadmap describes intended scope; it is not a
list of completed features.

## Prepare an isolated installation

Use [LOCAL-INSTALLATION.md](docs/operations/LOCAL-INSTALLATION.md) to restore the
exact R library and configure explicit local executables. The exercised profile
is Windows AMD64, R 4.6.1 and separately installed optional Python environments.
The development `../../work` directories are not shipped. A clone does not
contain R, Python environments, the TinyCC compiler, compiled publication guard,
model weights or retained browser evidence.

On Windows, even R-only report workflows require the native publication guard
and its standard-library Python helper. Build the guard with the guide's
verified TinyCC distribution and set `BROHN_PUBLICATION_NATIVE_MANIFEST` and
`BROHN_PUBLICATION_PYTHON`. Configure `BROHN_PYTHON` for design portability and
only the scientific profiles needed by the change. Do not replace pinned
dependencies with global packages or update locks opportunistically.

Keep application libraries, caches, QA output and research workspaces outside
the checkout. Use a dedicated QA workspace and distinct loopback ports. Never
point a fixture harness at a colleague's research workspace. Starting only a
Shiny page does not start the connected collection and processing services;
use `run-local.ps1` with explicit paths as shown in the installation guide.

## Make a bounded, reviewable change

Describe the concrete researcher problem and the expected study-to-report
behavior. Keep existing frozen releases, source files, hashes and historical
receipts intact. Version protocol or scoring changes explicitly; demonstrate
how existing saved studies continue to behave.

R owns scientific/domain rules. Browser timing, acquisition and supervised jobs
have separate responsibilities. Researcher styling must not alter controlled
participant stimuli. Keep sample/preview/pilot/live origin separate from
completion and data quality, and retain null/missing values and exact typed
responses. New numerical methods need independent expected results and clear
support/limitation reporting, rather than only tests that repeat the algorithm.

Use original synthetic fixtures. Do not commit credentials, personal participant
data, recordings, competitor screenshots, proprietary SDKs or model weights.
Avoid posting sensitive defects or research data in public issues; contact the
repository maintainer privately before sharing details. Source contributions
are made under the repository's [MIT license](LICENSE); third-party material
needs its own compatible permission and attribution.

## Run the relevant checks

After the installation doctor passes, use the current selected check runner
from the repository root. Adapt the paths and choose a new output directory:

```powershell
$rscript = 'C:/Program Files/R/R-4.6.1/bin/Rscript.exe'
$env:R_LIBS_USER = 'C:/Brohn/r-library'

& $rscript --vanilla scripts/run-checks.R --list
& $rscript --vanilla scripts/run-checks.R --test core `
  --output 'C:/Brohn/qa/core-run-001'
if ($LASTEXITCODE -ne 0) { throw 'Selected Brohn check failed.' }
```

The full `domain`, `scientific`, `operations` and `interchange` suites are not
promised as fresh-clone commands. Several tests still require external
`../../work` fixtures, reference data or development tool paths, including some
domain tests. Inspect each selected script and prepare its prerequisites before
using `--suite`. The [check guide](docs/qa/RUNNING-CHECKS.md)
explains the catalog, isolated child processes, timeouts, logs and `results.json`.
The catalog is a selected set, not every test. `tests/run.R` and
`npm run test:browser` belong to the historical prototype and are not sufficient
acceptance for the connected app.

Browser and native-worker checks have their own fixtures and documented launch
order in [researcher QA](docs/qa/RESEARCHER-QA.md). Read the relevant journey
before running it; some older harnesses refer to external prepared paths or
retained stores and are not turnkey fresh-clone commands. Do not edit worker
source during active jobs: source identities are part of saved evidence. Run
appropriate checks once, then repeat only for a change, failure or unresolved
concern. A skipped prerequisite is not a passed workflow.

## Record the handoff honestly

Summarize the final behavior, affected contracts, exact checks run and remaining
limits in the pull request. Update the applicable documentation, status and
change record. Preserve failed attempts as separate evidence and distinguish
component tests, actual saved-worker publications, browser checks, accessibility
scans, human research and physical-device qualification.

The paused questionnaire explorer illustrates this boundary: its **unregistered
index has 49 standalone checks**, **storage acceptance is 0**, and **the UI is
not available**. Do not register its draft adapter or advertise complete in-app
browsing without completing the source binding, publication, cache/authorization
and researcher acceptance in the [explorer contract](docs/qa/QUESTIONNAIRE-COMPLETE-EXPLORER-CONTRACT.md).
The existing full-artifact report downloads are a separate completed workflow.
