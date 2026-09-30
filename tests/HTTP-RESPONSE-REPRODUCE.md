# Repeatable saved-download checks

Run from a complete Brohn checkout with its intended R library, Node dependencies and Chrome installed. Each output directory must be new and outside the source checkout.

```sh
Rscript tests/http-response.R R/platform-http-response.R ../brohn-http-unit-01
node tests/http-response-wire.mjs /path/to/Rscript ../brohn-http-wire-01 R/platform-http-response.R package.json
node tests/http-routes.mjs /path/to/Rscript . ../brohn-http-routes-01
```

Replace `/path/to/Rscript` with the actual executable path. On Windows use the x64 executable directly for service tests, rather than an executable wrapper that spawns a detached child. Select the installed R packages through the normal R library environment. Unit prerequisites include Shiny, httpuv, jsonlite and digest; wire/route checks also use later, Node, `@playwright/test` and Chrome (`channel: chrome`). Missing prerequisites fail; they are not passing skips.

The helper wire command takes an explicit package.json for dependency resolution. The route command optionally accepts a fourth dependency-root directory; otherwise it uses the source root. Both own random loopback services and headless browsers and close them after the run. The helpers are sibling test files: `http-response-wire.R` and `http-routes.R`. No research store, credentials, model or scientific worker is needed.

- `http-response.R`: 106 deterministic synthetic checks of status/body/header preservation, exact lengths, input refusal, private S3 registration and unchanged runtime options/functions.
- `http-response-wire.mjs`: 130 actual HTTP checks of ten synthetic representations, empty HEAD, unchanged GET bytes, exact lengths and sequential connection reuse. Wire files, source hashes and cleanup are retained.
- `http-routes.mjs`: 197 checks on 19 exact source callback ASTs/24 variants and the real hosted guard. File/AST hashes are retained. Backend/current-selection/native checks are explicit private spies; this is not independent qualification of those dependencies. Original callback predicates, error mapping and actual HTTP are exercised. Synthetic file bodies are transport fixtures, not valid images or scientific datasets.

Commands write `results.json` or a retained failure receipt and return a nonzero exit status on failure. They are direct argument-taking tests, not no-argument QA-catalog entries.

For targeted existing access/resource regression, from the repository:

```sh
Rscript tests/platform-hosted-http.R ../brohn-hosted-http-01
Rscript tests/platform-material-views.R
```

The first creates its synthetic session evidence at the supplied new path; the material test creates an isolated temporary workspace and uses the checked-in sample images. These 13 and 19 checks are separate from genuine saved-study/browser qualification. See the [checkpoint record](../docs/qa/PUBLICATION-SAVED-DOWNLOADS-20260927.md) for native paired exports, historical-report compatibility, source phases and remaining scope.
