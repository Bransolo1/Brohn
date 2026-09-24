# Reproduce the saved-media history journey

This is a continuation of the **original synthetic media acceptance fixture**,
not a universal fresh-install test. It requires an intact accepted regular/gap
workspace produced by `tests/researcher-media-review.mjs`, its successful final
`results.json` containing `regular` and `gap` references, and the configured
native publication/audio runtime. Do not point it at a real research workspace.
The source is read-only; all new jobs run in a fresh copied destination.

Supply every location explicitly. Create a runtime JSON with these fields:

```json
{
  "app_root": "C:/your/Brohn",
  "rscript": "C:/your/R/bin/Rscript.exe",
  "r_libs": "C:/your/R-library",
  "publication_python": "C:/your/publication-env/Scripts/python.exe",
  "publication_manifest": "C:/your/native/publication-guard.json",
  "researcher_port": 3967,
  "participant_port": 3968,
  "chrome_channel": "chrome"
}
```

Paths must be absolute and existing. Ports must be distinct and available.
`chrome_channel` can be `chrome` or `msedge`; install that browser and Brohn's
declared browser-test dependencies first. The participant port is reserved but
this read-only researcher journey does not start a participant service.

Set `$testDir` to the absolute `tests/media-history` directory in your checkout.
Set `$runtimeFile`, `$baselineWorkspace`, `$baselineReceipt`,
`$destination`, `$python` and `$node` to explicit caller-selected paths. The
destination must not exist and its basename must start
`brohn-media-history-browser-`.

```powershell
& $python "$testDir/prepare-browser-copy.py" $destination $baselineWorkspace $baselineReceipt $runtimeFile
$runtime = Get-Content -LiteralPath $runtimeFile -Raw | ConvertFrom-Json
$env:R_LIBS_USER = $runtime.r_libs
$env:LC_ALL = 'C'
$env:BROHN_PUBLICATION_PYTHON = $runtime.publication_python
$env:BROHN_PUBLICATION_NATIVE_MANIFEST = $runtime.publication_manifest
& $runtime.rscript --vanilla "$testDir/researcher-media-history-fixture.R" setup $destination
& $runtime.rscript --vanilla "$testDir/researcher-media-history-fixture.R" populate $destination
& $node "$testDir/researcher-media-history.mjs" $destination --run-after-freeze
```

The application root comes from the runtime manifest. The fixture resolves
regular/gap media, audio, report and parent IDs from the supplied successful
baseline receipt, then checks their relationships in the copy. There are no
developer-path or hard-coded original-ID fallbacks.

`populate` creates42 actual cursor reviews on the baseline's complete original
window, original video stream0, and its8kHz/160-frame analytic source. It stops
on a failed/cancelled request and preserves that request. It never substitutes
metadata clones for real saved worker results. A different baseline format,
sample interval or analytic media requires a separately declared fixture; do
not silently alter these expected values.

Run `verify-media-history.py DESTINATION` with an explicitly selected Python
that contains Pillow for the independent RGB decoder. Run
`preparation-timing.py DESTINATION` with standard Python. These only read the
workspace and write external receipts. They compare all original SQL rows,
object bytes, source-ledger timestamps and42 mappings/RGB frames. Their physical
synchronization limit remains explicit.

All production sources must remain stable during native jobs and the browser
phase. Preserve failures. Browser completion includes a process restart,
download equality, job/report equality and source closure. It creates no
new review jobs. Screenshots require human/agent visual inspection as well as
Axe and overflow checks.

The accepted25September run predates this path-only reusable packaging. Its
initial fixture used the documented developer baseline and known IDs. The
packaged explicit-input version received syntax and actual copy/setup smoke
checks on a separate isolated copy, with zero new jobs/services; its complete
42-job/browser sequence was not repeated. The production feature and browser
assertions are unchanged by packaging.
