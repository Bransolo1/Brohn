# Reproduce report-package component checks

Run from a complete Brohn checkout with its normal pinned R packages and the
configured methods environment: CPython **3.12.10**, Pillow **12.3.0**. These
tests create synthetic data in new external evidence directories. No private
store, participant data, external service, device or model weights are required.
The separate HTTP test below starts and stops its own temporary loopback service.

Example PowerShell; replace executable/library paths with your installation:

```powershell
$rscript = 'C:/Program Files/R/R-4.6.1/bin/Rscript.exe'
$methods = 'C:/Brohn/tooling/methods-venv/Scripts/python.exe'
$env:R_LIBS_USER = 'C:/Brohn/r-library'
$env:LC_ALL = 'C'
& $rscript tests/test-report-package.R ../brohn-package-pure-01 $methods
& $methods tests/test-report-package-oracle.py ../brohn-package-pure-01
& $methods -B tests/test-report-package-landmarks.py --output ../brohn-package-pure-01/landmark-check.json ../brohn-package-pure-01/first ../brohn-package-pure-01/focused ../brohn-package-pure-01/duplicate-panels ../brohn-package-pure-01/source-identifiers
& $rscript tests/test-report-package-aliases.R ../brohn-package-alias-01
& $methods tests/test-report-package-helpers.py ../brohn-package-helpers-01
& $rscript tests/report-package-ui-state.R . ../brohn-package-ui-01
node tests/report-package-ui.mjs . ../brohn-package-client-01
```

Run each command sequentially and inspect its exit code before continuing.
Each suite's output directory must be fresh. The numerical oracle and landmark
checker deliberately read the preceding pure suite's completed output; neither
performs a second render. The landmark receipt path must not already exist.

| Test | What it establishes | What it does not establish |
| --- | --- | --- |
| Pure R renderer + Python oracle | Complete synthetic source projection, typed JSON/CSV, selected-page HTML/SVG, deterministic ZIP and bounded failures. | Store authority, genuine jobs, connected study workflow or device validity. |
| Exact alias references | Identical bodies at different revisions stay separate; combined/crosswalk identities join the exact source; ambiguous/foreign refs refuse. | Authorization for those refs. |
| Archive/raster helpers | Generated archive/image boundaries, fixed metadata, decoding and refusal behavior. | All image formats, arbitrary workload or physical stimulus timing. |
| Semantic landmarks | Distinct accessible section-region names, matching visible source context and stable content bindings across multiple reports or repeated panels. | Browser layout, assistive-technology use or complete accessibility conformance. |
| Shiny controller | Explicit backend/resource-spy checks including durable stages, stale inputs, history, reactive ready links and direct successful/refused HEAD body behavior. The checkpoint identifies each source phase's executed count. | Native storage, real backend, HTTP or browser acceptance. |
| Node feedback | 13 simulated DOM/frame checks for feedback, stale ACK, focus ownership and passive completion. Uses Node built-ins only. | Actual browser paint, keyboard or assistive-technology behavior. |

The UI R test also accepts an external packet as argument one and an explicit
loader checkout as argument three. The JS test accepts an explicit asset file
instead of the source root. Neither test embeds a developer-specific path.

## Actual HTTP transport regression

The portable pair is `tests/report-package-http.mjs` (launcher) and
`tests/report-package-http.R` (synthetic server). Run from the repository root
with the same configured R packages and an actual Rscript executable:

```powershell
node tests/report-package-http.mjs $rscript . ../brohn-package-http-01
```

The output directory must be fresh. This requires Node, `@playwright/test` and installed Google Chrome
(the Playwright `chrome` channel). `R_LIBS_USER` must point to the configured
Brohn R package library. An optional fourth argument selects an explicit dependency
root; otherwise dependencies resolve from the repository. On Windows, `$rscript`
must name the actual x64 Rscript executable, not a wrapper that leaves a detached
child. The launcher owns random loopback ports, a bounded service lifetime and
cleanup; it writes `results.json` and exits nonzero on failure.

The qualified source runs 15 checks with the report helper loaded into a private
source environment. It covers synthetic HTML/ZIP-like transport bytes and an
exact 100,000-byte body, identity/gzip negotiation, decimal lengths, empty HEAD,
unchanged GET, refusals and reused connections. Legacy failing framing is
retained as diagnostic evidence. These are transport fixtures, not valid
scientific packages or proof of native source authorization.

The actual Shiny/httpuv probe starts an owned bounded synthetic server and tests
response bytes over HTTP, including sequential requests on a reused connection.
The two UI commands above do not reproduce it. Source/authority spies, actual
synthetic transport and the final connected study-package browser run remain
separate evidence. No result here extends the report-specific HEAD correction
to every other download callback.

Preserved source-based browser/native qualification stores remain external.
The [checkpoint](../docs/qa/PUBLICATION-REPORT-HANDOFF-20260927.md) identifies
their executed phases and limitations. A passing component suite does not close
the connected researcher journey, public hosting or whole-platform release.
