# Saved-media reopening feedback qualification

This is a fixture-specific connected qualification, not a universal fresh-install
test. It reads an existing, independently checked synthetic source corpus with
42 prepared media reviews and the retained original regular/gap review receipts.
It creates no scientific or media-review jobs. Never point it at a live research
workspace. `browser-fixture.py copy` creates a new isolated store using SQLite's
backup API and verifies its catalog and source-object bytes against the supplied
baseline. Source and target must be different directories.

Prerequisites: a configured Brohn checkout with its R and JavaScript dependencies,
qualified native publication helper, Python, and an installed Chrome channel.
Pass every machine-specific path explicitly in your own runtime JSON based on
`runtime.example.json`; no developer-path fallback is used. Reserve both ports
and keep application sources unchanged until the browser receipt is terminal.
The participant port is recorded for the existing fixture; this qualification
starts only the researcher service.

The supplied baseline folder must contain `fixture.json`, `copy-receipt.json`
with its `baseline_receipt`, `population-results.json` showing exactly 42
successful prepared review jobs, and `workspace/catalog.sqlite` plus all object
files. It can be a verified copy of the corpus described in
`docs/qa/MEDIA-HISTORY-ACCEPTANCE.md`. Original report and review IDs come from
that retained receipt. The harness intentionally relies on its regular/gap
materials, exact original sample window and prepared history; arbitrary data
does not qualify. Obtain or recreate that prior fixture separately if missing.
Do not invent replacement receipts or regenerate acoustic analyses to make this
feedback test pass.

From the repository root, PowerShell examples (replace all explicit paths):

```powershell
$qaRoot = 'C:/absolute/path/to/new-qa-output'
$baseline = 'C:/absolute/path/to/verified-populated-media-history'
$runtimeFile = 'C:/absolute/path/to/runtime.json'
$runtime = Get-Content -LiteralPath $runtimeFile -Raw | ConvertFrom-Json
$pythonExe = $runtime.publication_python
$nodeExe = 'C:/absolute/path/to/node.exe'
$target = Join-Path $qaRoot 'brohn-media-history-browser-feedback-new'
New-Item -ItemType Directory -Path $qaRoot -Force | Out-Null
& $pythonExe tests/media-feedback/browser-fixture.py copy $target $baseline $runtimeFile
& $nodeExe tests/media-feedback/researcher-media-history.mjs $target --run-after-freeze
```

The default caller reproduces the final 8-check natural-viewport follow-up at
390 x 844 with reduced motion. After initial report/audio navigation, opening
the saved history, paging and reopening use actual Tab/Shift+Tab/Enter. The
saved-row route uses no pointer, locator focus or harness scroll. It verifies
progress and completion focus with actual viewport bounds, exact mapping and
complete selected sample exports, genuine cursor-change URL invalidation,
restart, accessibility and zero new jobs. This does not claim that the entire
platform journey is keyboard-only.

For the broader 15-check functional journey, use a separate new target copied
in the same way, then run
`tests/media-feedback/functional/researcher-media-history.mjs` with that target
and `--run-after-freeze`. Its original source phase checks exact PNG/mapping/
sample exports, an actual gap, pending close, stale cursor URLs, current project
revocation, visible failure with controls re-enabled, restoration and restart.
Its layout-visible measurements are not natural-viewport proof. The original
accepted functional and final focus runs have separate source hashes; running
the functional harness on another source phase produces a new receipt and does
not retroactively change the earlier acceptance.

Every invocation creates a new `browser-<timestamp>` receipt containing exact
executed harness files, source hashes, process logs, screenshots, checks and
catalog preservation. Failure evidence is retained. Only its own researcher
service is stopped, through that copied fixture's stop sentinel. The revocation
case changes only the isolated current catalog temporarily; `finally` restores
ownership. A hard external process kill may require `browser-fixture.py restore
<target>` before comparing the copied catalog. Never delete failure receipts.

Component checks can run separately without a browser or service:

```powershell
& $nodeExe tests/media-feedback/check-paint.mjs www/media-review-ui.js "$qaRoot/paint-results.json"
$env:R_LIBS_USER = $runtime.r_libs
$env:LC_ALL = 'C'
$env:BROHN_PUBLICATION_PYTHON = $runtime.publication_python
$env:BROHN_PUBLICATION_NATIVE_MANIFEST = $runtime.publication_manifest
$componentOutput = Join-Path $qaRoot 'shiny-component'
New-Item -ItemType Directory -Path $componentOutput | Out-Null
& $runtime.rscript --vanilla tests/media-feedback/test-feedback.R $runtime.app_root $target $componentOutput
```

The 21 JavaScript checks use a fake DOM and test frame scheduling, bounded
control restoration, stale tickets, focus/scroll yielding and field locking.
The 17 Shiny checks use the genuine copied source readers but bypass one native
successful transition solely to inspect state. Neither component suite alone
proves actual native opening, rendering or browser focus; those claims require
the connected receipts. Run the R command with the repository as the current
directory. `test-feedback.R`'s first argument selects the view's source root;
passing the checkout tests the installed view, and an external candidate root
can be supplied for a future isolated comparison.

The final ready screenshot captures the result heading and links as native
opening completes. The independently served frame image can still be loading;
do not treat a blank image placeholder as a pixel-validation receipt. The
earlier functional PNG export and source oracle establish pixel identity.
Opening remains roughly 13-14 seconds on the qualified local corpus, with
accurate feedback visible earlier. No maximum-scale performance, scientific
validity, external-device alignment or physical synchronization claim is made.
