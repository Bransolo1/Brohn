# One-command local setup and recovery

24 September 2026. `scripts/setup-local.ps1` orchestrates the existing exact R
restore, namespace verification, native publication build and checked local
configuration. R, 64-bit Python and the complete TinyCC distribution remain
explicit prerequisites. It does not install them globally, activate hardware or
start collection. Read [installation instructions](../operations/LOCAL-INSTALLATION.md).

The new bootstrap reads the exact `renv` version from the lock and installs it in
a separate library. Versioned CRAN source URLs never substitute a latest version.
Setup retains an ownership marker, a mutually exclusive attempt lock, logs and a
ready receipt. The saved configuration appears only after all required checks.
Failed attempts keep their diagnostics and can be retried; an existing successful
configuration requires explicit replacement and survives failed preparation.

## Executed evidence

`tests/local-setup.ps1` passed 19 checks at
`make/work/test-runs/brohn-setup-check-20260924-02/results.json`:

- Fresh bootstrap and separate 46-package application library, actual native
  build and checked configuration, without creating a research workspace.
- Refusal of accidental configuration replacement, unrelated nonempty directory
  and conflicting ports, preserving original bytes.
- Actual invalid-compiler failure during a requested replacement, preserving
  the previous configuration and native manifest and releasing the setup lock.
- Restoration of all five changed environment variables after success/failure.
- Successful retry and the real PowerShell launcher's `-CheckOnly` route.

The first attempt exposed an existing PowerShell/.NET bug in
`configure-local.ps1`: a null backup argument became an empty path during atomic
replacement. Passing an explicit null string corrected it. The failed
`brohn-setup-check-20260924-01` attempt and its logs remain retained.

`tests/researcher-installed-runtime.mjs` then used that new application library,
native component and checked configuration through the real `run-brohn.R` entry
point. It passed ten browser/service checks and two clear automated accessibility
scans at `make/work/test-runs/brohn-installed-runtime-20260924-02/results.json`.
The researcher created a controlled-study draft, reopened the library and retained
the study across a complete service restart. The separate participant endpoint
answered and the real supervised analysis service started. Both shutdowns reported
all owned services stopped. Desktop and 390 px library states were captured;
no browser exception or narrow-page overflow occurred.
The narrow Studies screenshot was also visually inspected: navigation, search,
status and the retained study card remain legible without clipped content.

The first browser attempt stopped at a test-harness Axe context error before study
creation. Changing the harness to create an explicit browser context fixed it;
its failure and normal service-shutdown logs remain in the `-01` directory.

These runs use an existing Windows AMD64 host, R 4.6.1 and Python 3.12.10, with
some R packages restored from an existing dependency cache. They establish a
fresh application library and connected local setup, not a clean operating-system
installation, offline installer, optional-model installation, scientific accuracy
or every supported measurement journey. No research data or runtime binaries are
included in the repository. Clean-machine and broader platform qualification
remain open.
