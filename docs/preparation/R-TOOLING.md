# R dependency preparation

Prepared 2026-09-08 on Windows with R 4.6.1 (ucrt). The repository now has an
explicit [renv.lock](../../renv.lock): 32 installed CRAN packages covering
`shiny`, `bslib`, `jsonlite`, `png`, `digest`, `renv`, and their recursive runtime
dependencies. R itself is recorded as 4.6.1; it is not downloaded by these scripts.

`renv` 1.2.4 was installed from the official CRAN Windows binary into the existing
workspace library, `../../work/r-library`. All 31 existing package versions,
repository declarations and license declarations remained unchanged. No
`.Rprofile` activation or global settings changes were made. The dependency setup
itself did not change application behavior; the separate accessibility repair is
recorded in CHANGELOG.md.

## Commands

From the repository root in PowerShell, use the existing local R installation:

```powershell
$rscript = (Resolve-Path '../../work/native-r/bin/Rscript.exe').Path
$bootstrapLibrary = (Resolve-Path '../../work/r-library').Path
$env:R_LIBS_USER = $bootstrapLibrary
$env:R_USER = (Resolve-Path '../../work').Path
$env:LC_ALL = 'C'

# Restore exact versions to the separate, gitignored renv/library directory.
& $rscript --vanilla scripts/restore-dependencies.R
if ($LASTEXITCODE -ne 0) { throw 'R restore failed' }
& $rscript --vanilla scripts/check-dependencies.R
if ($LASTEXITCODE -ne 0) { throw 'R dependency check failed' }
```

Both commands accept an optional target-library path as their final argument.
Relative paths are resolved from the current working directory. The scripts
locate the lockfile relative to their own location, so they can also be invoked
from elsewhere. The existing launcher continues to use its current library.
To run R tests or the application against the restored library, explicitly set
`R_LIBS_USER` to that library before starting a fresh R process.

If `renv` is absent, the restore script stops with bootstrap instructions. Install
it explicitly into a chosen bootstrap library first, without updating other
packages; for example, with the variables above:

```powershell
& $rscript --vanilla -e 'install.packages("renv", lib=Sys.getenv("R_LIBS_USER"), repos="https://cloud.r-project.org", dependencies=FALSE)'
if ($LASTEXITCODE -ne 0) { throw 'renv bootstrap failed' }
```

The restore is transactional, retains unrelated packages in its target, and
disables retrying with newer versions. It requires the recorded R version.
Unless `RENV_PATHS_ROOT` is already set, its cache/state root is under gitignored
`renv/library/.renv-state`; this setting lasts only for the script process.
These behaviours use the documented [renv restore API](https://rstudio.github.io/renv/reference/restore.html).

Update the lock deliberately only after testing a changed source library:

```powershell
& $rscript --vanilla scripts/snapshot-dependencies.R $bootstrapLibrary
if ($LASTEXITCODE -ne 0) { throw 'R snapshot failed' }
& $rscript --vanilla scripts/check-dependencies.R $bootstrapLibrary
if ($LASTEXITCODE -ne 0) { throw 'R dependency check failed' }
git diff -- renv.lock
```

Snapshot requires an explicit source-library argument and installs nothing.
It uses the documented [renv snapshot API](https://rstudio.github.io/renv/reference/snapshot.html)
for a project without renv activation, with an explicit package list and recursive
dependencies. Review the lock diff, rerun the existing application checks for
dependency changes, and refresh the inventory below before accepting an update.

## Verification

The installed workspace library passed a fresh-process check for all 32 exact
versions and namespace loads. The checker restricts lookup to the selected
library plus R's base library, checks each loaded namespace path/version, and
compares package source and license declarations with the lockfile. It reports
extra packages separately. This verifies dependency tooling; the existing
scientific and device qualification gates remain open.

A fresh isolated restore to `../../work/r-library-restored-20260908` succeeded:
32 exact CRAN Windows binaries downloaded and installed, followed by a new R
process passing all 32 version, namespace location/load, source, and license
checks, with zero extra packages. This run used `RENV_PATHS_ROOT` set to
`../../work/renv-state` (as an absolute path) to keep its download/cache state in
the workspace. The original application library's 31 package metadata records
were compared again after restore and were unchanged. Missing bootstrap,
missing target library, and omitted snapshot-source argument also produced the
intended clear failures. The subsequent full application check used the restored
library: tests/all.R passed all 773 counted checks plus storage/JSON/protocol/Shiny
workflows; JavaScript wire checks, return-to-R hash validation and both report
reproductions passed. Both fictional report fixtures reproduced 3 pairs, no
exclusions and a 20 percentage-point average difference. This verifies software
reproduction, not scientific qualification.

## Recorded package declarations

All packages below declare `Repository: CRAN`; the lock records
`https://cloud.r-project.org` as the retrieval repository. Versions and license
strings come from installed package `DESCRIPTION` metadata, also preserved in
the lockfile. Base R packages are supplied by the recorded R distribution.

| Package | Version | Declared license |
|---|---|---|
| R6 | 2.6.1 | MIT + file LICENSE |
| Rcpp | 1.1.2 | GPL (>= 2) |
| base64enc | 0.1-6 | GPL-2 \| GPL-3 |
| bslib | 0.12.0 | MIT + file LICENSE |
| cachem | 1.1.0 | MIT + file LICENSE |
| cli | 3.6.6 | MIT + file LICENSE |
| commonmark | 2.0.0 | BSD_2_clause + file LICENSE |
| digest | 0.6.39 | GPL (>= 2) |
| fastmap | 1.2.0 | MIT + file LICENSE |
| fontawesome | 0.5.3 | MIT + file LICENSE |
| fs | 2.1.0 | MIT + file LICENSE |
| glue | 1.8.1 | MIT + file LICENSE |
| htmltools | 0.5.9 | GPL (>= 2) |
| httpuv | 1.6.17 | GPL (>= 2) \| file LICENSE |
| jquerylib | 0.1.4 | MIT + file LICENSE |
| jsonlite | 2.0.0 | MIT + file LICENSE |
| later | 1.4.8 | MIT + file LICENSE |
| lifecycle | 1.0.5 | MIT + file LICENSE |
| magrittr | 2.0.5 | MIT + file LICENSE |
| memoise | 2.0.1 | MIT + file LICENSE |
| mime | 0.13 | GPL |
| otel | 0.2.0 | MIT + file LICENSE |
| png | 0.1-9 | GPL-2 \| GPL-3 |
| promises | 1.5.0 | MIT + file LICENSE |
| rappdirs | 0.3.4 | MIT + file LICENSE |
| renv | 1.2.4 | MIT + file LICENSE |
| rlang | 1.3.0 | MIT + file LICENSE |
| sass | 0.4.10 | MIT + file LICENSE |
| shiny | 1.14.0 | MIT + file LICENSE |
| sourcetools | 0.1.7-2 | MIT + file LICENSE |
| withr | 3.0.3 | MIT + file LICENSE |
| xtable | 1.8-8 | GPL (>= 2) |

This inventory records declarations, not a complete redistribution review of
bundled assets and native components. Preserve applicable package LICENSE and
notice files when distributing dependencies. Restoration requires available
package artifacts; the lock does not vendor binaries, pin the operating system,
or establish cross-platform reproducibility. Some packages contain native code,
so source restoration on another platform may need a compatible compiler and
system libraries.
