# Reproduce saved-source catalogue and controller checks

Use this guide after the catalogue helper, report views/controller, browser script, application entry, source manifest and six tests have been promoted together. Use one complete, stable checkout. Do not mix newer R modules with an older assigned-delivery source manifest, or edit the worker-hashed `R/platform-load.R` to load the UI helper.

Prepare the selected R installation and separate application library using the [local installation guide](../docs/operations/LOCAL-INSTALLATION.md). The recorded profile uses R 4.6.1 and the versions in `renv.lock`; a different platform or installation needs its own evidence. Use that installation's `Rscript`, not whichever executable happens to be first on PATH. These checks need the installed R dependencies, but no browser, participant data or downloaded biosignal dataset.

The tests have explicit positional arguments. `scripts/run-checks.R` currently supplies none, so adding these files to its catalogue is insufficient. Invoke them directly as below; this documents the existing interface and does not introduce another runner.

```powershell
# Replace these example locations with your own absolute paths.
$checkout = (Resolve-Path 'C:/Brohn/source').Path
$rscript = (Resolve-Path 'C:/Program Files/R/R-4.6.1/bin/Rscript.exe').Path
$applicationLibrary = (Resolve-Path 'C:/Brohn/r-library').Path
$evidenceParent = 'C:/Brohn/qa/source-catalogue-001'

if (Test-Path -LiteralPath $evidenceParent) {
    throw 'Choose a new evidence directory; retain the previous results.'
}
New-Item -ItemType Directory -Path $evidenceParent -ErrorAction Stop | Out-Null
$evidenceParent = (Resolve-Path -LiteralPath $evidenceParent).Path
if ($evidenceParent.Equals($checkout, [StringComparison]::OrdinalIgnoreCase) -or
    $evidenceParent.StartsWith($checkout.TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Evidence must be outside the checkout.'
}

$env:R_LIBS_USER = $applicationLibrary
& $rscript --vanilla (Join-Path $checkout 'scripts/check-dependencies.R') $applicationLibrary
if ($LASTEXITCODE -ne 0) { throw 'The selected R library failed its dependency check.' }

$tests = @(
    'lazy-report-source-catalog',
    'lazy-report-source-ui-state',
    'report-package-ui-state',
    'report-task-package-ui-state',
    'report-choice-package-ui-state',
    'report-eda-package-ui-state'
)
foreach ($test in $tests) {
    $caseOutput = Join-Path $evidenceParent $test
    if (Test-Path -LiteralPath $caseOutput) { throw "Case already exists: $caseOutput" }
    & $rscript --vanilla (Join-Path $checkout "tests/$test.R") $checkout $caseOutput $checkout
    if ($LASTEXITCODE -ne 0) { throw "Failed: $test. Preserve $caseOutput before investigating." }
    $receipt = Get-Content -LiteralPath (Join-Path $caseOutput 'results.json') -Raw -ErrorAction Stop |
        ConvertFrom-Json -ErrorAction Stop
    if ($receipt.passed -ne $true) { throw "Missing or failed semantic result: $test" }
}
```

Every case receives `<source-checkout> <fresh-case-output> <loader-checkout>`. The catalogue test requires all three. The other tests also support their documented shorter form, but using the same absolute checkout twice avoids accidentally loading another version. EDA retains an optional five-argument support-file form for historical qualification; the complete promoted checkout needs no extra support files. Each test creates its case directory itself, so leave it nonexistent.

Inspect and retain each `results.json`, including its source hashes, individual checks, scenarios and any failure. A zero exit code alone is insufficient. On failure, stop at that case; diagnose before attempting a fresh directory. These direct commands do not reproduce the private process supervisor or independently prove process closure. The recorded supervised limits were 60 seconds per case, shared 120 seconds for the two focused tests and shared 240 seconds for the four regressions, within their original 300-second outer ceiling. Preserve those limits and owned-process cleanup if integrating this interface into a future reviewed runner; do not widen them to turn a failure into a pass.

| Test | What it establishes |
|---|---|
| `lazy-report-source-catalog.R` | Actual disposable SQLite catalogue and original local project/study authority, exact saved references, paging, malformed label handling and scope/hash refusal. Report bodies are deliberately synthetic; one full-read seam is controlled. It cannot establish scientific report validity or hosted authentication. |
| `lazy-report-source-ui-state.R` | Actual Shiny controller with explicit backend/source/resource spies: pending Add, cancellation, failure, stale tickets, edit preservation, held-view handling and removal of unavailable sources. |
| `report-package-ui-state.R` | General report controller/history/preparation regressions using explicit in-memory spies. |
| `report-task-package-ui-state.R` | Task-profile and selector/dependency regressions using the original controlled fixtures. |
| `report-choice-package-ui-state.R` | Choice-profile, saved-selector and historical behavior with controlled fixtures. |
| `report-eda-package-ui-state.R` | EDA controller/windows/selectors and original pure normalizers. New requests use outer report profile 0.3; historical outer profiles 0.1 and 0.2 remain unchanged. This is distinct from the EDA preparation profile's version. |

The original focused component run passed 27 catalogue and 34 controller checks against lazy-source01. The four adapted regressions passed 239 checks across 47 scenarios against accessible-source02. Their catalogue/controller modules are identical to disclosure-source03, but the view bytes differ: source02 adds specific accessible names; source03 adds the disclosure marker and browser state preservation. These predecessor receipts must not be relabelled as six test runs against source03.

Separate actual source03 browser evidence covers ordinary app entry, one saved PPG source Add/Remove, edited titles, keyboard interaction, disclosure preservation/reset, desktop/phone layout and two Axe scans. It used copied original saved data, checked exact schema additions and unchanged historical rows/files, and created no jobs. Neither these six tests nor that browser slice qualify saved-history downloads, a new Prepare→worker→report journey, cold restart, physical devices or scientific interpretation.
