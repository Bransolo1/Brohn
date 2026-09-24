# Optional facial runtime and saved installation

Executed 24 September 2026 on the existing Windows/Python3.12 installation.
This is software readiness and configuration evidence, not a clean-machine
restore, model-accuracy, acquisition or researcher-journey qualification.

The optional `facial-au` profile has a separate pinned Python environment. The
read-only doctor checks every one of its60 distributions, five model/config
assets, ten shared FFmpeg native files and75 installed provider source files.
Only after those asset checks pass does it import seven actual scientific/native
entry points. It checks dependency consistency, disables model network retrieval
and never constructs a detector or runs inference.

`brohn-facial-readiness-20260924-01/actual-runtime.json` reports ready:60 package
checks, seven imports,90 asset/source checks and successful dependency consistency.
Evidence directories live under `../../work/test-runs/` outside this repository.
Five independently authored standard-library tests additionally exercise exact
size/hash mismatch, missing files, path containment, required model/source assets,
and restoration of environment variables and DLL handles after an import error.

The version1 local installation remains backward compatible when `assets` is
absent. Selecting `facial-au` requires the two explicit `facial_models` and
`facial_ffmpeg` directories in that installation. Unknown asset keys or files
where a directory is required fail. Configuration and the launcher translate
these data-only values to scoped process variables and restore prior values.

`brohn-facial-configuration-20260924-02/results.json` records29 passing checks:
actual checked activation, persisted paths, launch-time reinspection, unchanged
prior configuration after a missing-model replacement fails, environment
restoration, and an unopened research workspace throughout. The initial `-01`
attempt stopped at a test assertion comparing forward-slash input paths with
correctly normalized Windows paths. That failure is retained; the corrected test
uses independent absolute-path normalization. No activation or inference ran in
that first attempt.

Reproduce with `python tests/facial-runtime-readiness.py`, then use
`tests/facial-configuration.ps1` with an existing checked installation, explicit
facial interpreter/model/shared-runtime paths and a fresh evidence directory.
The [installation guide](../operations/LOCAL-INSTALLATION.md) and
[model contract](../methods/FACIAL-AU-NATIVE-PROFILE.md) give setup commands and
precise model/interpretation boundaries. Model weights, videos and native binaries
are never committed with the source.
