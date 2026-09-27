# Pure task report-package regression

Install these two scripts as `tests/report-task-package.R` and `tests/report-task-package-oracle.py`. Run from the Brohn repository root using its installed R library and qualified Python/Pillow runtime. The input is the **models** directory produced by the public `tests/report-task-display.py` qualification; it contains generated synthetic records, not researcher data. The model stage's `results.json` must report `passed: true`.

```powershell
$env:R_LIBS_USER = 'C:/path/to/installed/R/library'
& 'C:/path/to/Rscript.exe' tests/report-task-package.R 'C:/path/to/task-display-evidence/models' 'C:/path/to/fresh-package-evidence' 'C:/path/to/qualified/python.exe'
& 'C:/path/to/qualified/python.exe' tests/report-task-package-oracle.py 'C:/path/to/fresh-package-evidence' 'C:/path/to/fresh-package-evidence/scientific-oracle.json'
```

Both output paths must be new. The test reads four existing public generated choice-RT models (native, import, repeat import and linked cohort); it does not rerun the seven-profile corpus. It makes one explicitly synthetic unlinked cohort from those original attempts before replacing all scientific/replay entry points with failure stubs. This is an export regression, not another scientific worker or native authority qualification.

The R script checks saved500ms,39/40 omissions and null SD; immutable complete inputs; exact panel counts; zero-figure score sections; deterministic archives; focused figures with identical full numerical companions; explicit null identities in both identifier modes; and refusal without artifacts when the panel limit is exceeded. The Python verifier independently compares every scientific value/type/null/order against the original input, checks aliases and complete CSV records, computes histogram membership and SVG coordinates, and checks offline HTML/ZIP hashes and metadata. It also requires unique complete section labels, focusable scroll regions with resolved help, and one unshrunk viewport per task figure.

No browser, network service, study workspace or live device is opened. Markup checks do not establish visual readability or keyboard behavior: those have separate actual390px/1280px browser evidence. Packed mixtures, unselected source-row sentinels and early unavailable GNAT have additional external genuine source/worker/oracle qualification; this compact portable suite does not claim to reproduce those sources.

## Intent and controller checks

These separately owned installed tests use new evidence directories and do not require the generated source corpus:

```powershell
& 'C:/path/to/Rscript.exe' tests/report-task-package-intents.R 'C:/path/to/Brohn' 'C:/path/to/fresh-intent-evidence'
& 'C:/path/to/Rscript.exe' tests/report-task-package-ui-state.R 'C:/path/to/Brohn' 'C:/path/to/fresh-ui-evidence'
```

The intent test's recorded scope is28 checks using real SQLite with explicit boundary spies; the UI state test's recorded scope is53 checks using backend spies. These counts describe their separate retained receipts, not reruns performed by the pure package test above. Actual browser downloads, genuine supervised worker publication, source holds and current-reader authority checks remain in the external connected checkpoint evidence.
