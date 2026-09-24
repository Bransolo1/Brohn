# Local installation and readiness

The connected local profile runs the researcher interface, participant HTTP
service and supervised analysis process against one durable workspace. Windows
AMD64, native R 4.6.1 and isolated Python 3.12.10 environments are the currently
exercised installation. Other operating systems and hosting arrangements need
their own installation and operational evidence.

Core study design, questionnaires, implicit tasks and supported R gaze workflows
do not require the scientific Python packages. On Windows, report publication
requires the small locally compiled R guard and a working 64-bit Python 3.10+
standard-library interpreter described below. Portable design ZIP handling
uses Python 3.9+ with standard-library modules only. Physiology, native recording
inspection, multistream preservation, video/audio analysis and assisted AOIs use
the explicitly selected optional profiles below. Device support remains specific
to an implemented and tested adapter; installing an acquisition library does not
qualify a physical device.

## Prepare a local installation with one command

With the pinned R version, 64-bit Python 3.10+ and the TinyCC toolchain described
below already installed, run this from the repository root:

```powershell
./scripts/setup-local.ps1 -InstallationRoot 'C:/Brohn/local' `
  -RscriptPath 'C:/Program Files/R/R-4.6.1/bin/Rscript.exe' `
  -PythonPath 'C:/Python312/python.exe' `
  -CompilerPath 'C:/Brohn/tooling/tcc/tcc.exe'
./run-local.ps1 -ConfigurationPath 'C:/Brohn/local/local-installation.json'
```

Setup bootstraps the exact locked `renv` version, restores the 46-package R lock
into a separate application library, checks every namespace, builds the protected
report-storage component and saves a checked local configuration. Dependencies
may be downloaded from CRAN. R, Python and the compiler are explicit prerequisites;
the command does not change global packages, start services or create participant
data. The installation directory must be outside the checkout and either empty
or already owned by this setup. Keep the complete TinyCC distribution together.

Run the same command to recover from a failed setup. Existing completed
configurations require `-ReplaceConfiguration`; failed preparation preserves the
old configuration and native manifest. Setup keeps per-attempt logs and a ready
receipt in `setup-logs`. A lock prevents two setups writing the same installation.
After a forcibly terminated setup, ensure it is no longer running before removing
only its `.setup.lock` file and retrying. Do not delete the installation to retry.

Optional `-Workspace`, `-Port`, `-ParticipantPort` and `-CacheRoot` select explicit
local locations and distinct service ports. `-ScientificProfiles` accepts the
same prepared interpreter map as `configure-local.ps1` below; it checks those
profiles and does not silently install models or enable devices. The default
workspace is `workspaces/default` inside the installation directory. Manual setup
remains available below. See [executed setup and recovery evidence](../qa/LOCAL-SETUP-ACCEPTANCE.md).

## Restore the core R application manually

Install the R version recorded in `renv.lock`. Use a separate bootstrap library
containing `renv`, and a separate application library. The explicit restore does
not activate renv in the repository or upgrade global packages. The current lock
contains 46 packages, including all 14 connected direct dependencies declared in
`scripts/runtime-dependencies.R`.

From the repository root in PowerShell, replace these paths with local choices:

```powershell
$rscript = 'C:/Program Files/R/R-4.6.1/bin/Rscript.exe'
$bootstrap = 'C:/Brohn/r-bootstrap'
$applicationLibrary = 'C:/Brohn/r-library'
$workspace = 'C:/Brohn/workspaces/default'
New-Item -ItemType Directory -Path $bootstrap -Force | Out-Null
$env:R_LIBS_USER = $bootstrap
$env:RENV_PATHS_ROOT = 'C:/Brohn/renv-cache'
$env:LC_ALL = 'C'

# Only if the bootstrap library does not already contain renv:
& $rscript --vanilla -e 'install.packages("renv", lib=Sys.getenv("R_LIBS_USER"), repos="https://cloud.r-project.org", dependencies=FALSE)'
if ($LASTEXITCODE -ne 0) { throw 'renv bootstrap failed' }

& $rscript --vanilla scripts/restore-dependencies.R $applicationLibrary
if ($LASTEXITCODE -ne 0) { throw 'Exact R restore failed' }
& $rscript --vanilla scripts/check-dependencies.R $applicationLibrary
if ($LASTEXITCODE -ne 0) { throw 'Restored namespace check failed' }
$env:R_LIBS_USER = $applicationLibrary
```

The namespace check uses only the selected library plus R's base library,
verifies versions, paths, CRAN source and license declarations, and reports extra
packages separately. A missing or different package is a failed check, not an
invitation to load a global substitute. `renv.lock` records package versions and
source declarations; this is not a signed supply-chain attestation.

## Prepare Windows report publication

Brohn prepares and verifies large output files before its final database write.
R retains native Windows read handles through the commit, so a terminated Python
helper cannot leave report bytes open to replacement during publication. The
launcher and worker refuse missing or incompatible dependencies before starting
services or claiming jobs. Other operating systems currently use the older
transactional copy path and do not inherit this Windows qualification.

Use the official [TinyCC 0.9.27 Windows 64-bit archive](https://download.savannah.gnu.org/releases/tinycc/tcc-0.9.27-win64-bin.zip).
The inspected archive SHA-256 is
`34a721949a2583fdff725312da092fa0f5f1f284b702e6f811c6954714faabb2`.
Download and verify the archive before extracting the complete toolchain outside
the repository. The explicit build command does not download or install tools:

```powershell
$env:BROHN_PUBLICATION_PYTHON = 'C:/Python312/python.exe'
$env:BROHN_PUBLICATION_NATIVE_MANIFEST = 'C:/Brohn/tooling/native/publication-guard.json'
& $rscript --vanilla scripts/build-publication-guard.R `
  'C:/Brohn/tooling/tcc/tcc.exe' 'C:/Brohn/tooling/native'
if ($LASTEXITCODE -ne 0) { throw 'Publication guard build failed' }
& $rscript --vanilla scripts/doctor.R --library $applicationLibrary --profiles none
if ($LASTEXITCODE -ne 0) { throw 'Required local runtime is not ready' }
```

The DLL and its immutable manifest are keyed by the C source, exact R version,
architecture, R DLL, headers and compiler distribution. Rebuilding with changed
inputs creates a new file; a damaged cache fails rather than being relabelled.
Keep the selected manifest and matching DLL together. The doctor verifies their
hashes, loads the actual R symbols, and runs a ten-second supervised Python
standard-library check. It distinguishes native rebuild instructions from a
Python configuration error; it never compiles or restores dependencies itself.

`BROHN_PUBLICATION_PYTHON` can point to the prepared methods environment, but no
scientific packages are needed by this helper. Without an explicit path, the
development checkout tries `BROHN_PYTHON_METHODS`, then its external prepared
methods environment. Set the explicit absolute paths for other installations.

## Start and stop

### Save a checked installation once

After restoring the dependencies and preparing the publication guard above,
save their paths in one local configuration. This verifies the actual pinned
R library, publication helper and portable-design interpreter before saving:

```powershell
./scripts/configure-local.ps1 -RscriptPath $rscript -LibraryPath $applicationLibrary `
  -PublicationPythonPath 'C:/Python312/python.exe' `
  -PublicationManifestPath 'C:/Brohn/tooling/native/publication-guard.json' `
  -Workspace $workspace
./run-local.ps1 -CheckOnly
./run-local.ps1
```

The default configuration is `.brohn/local-installation.json`, excluded from
source control. To place it elsewhere, pass `-ConfigurationPath PATH` to both
commands. Relative paths in an imported configuration resolve against that
file's folder. Explicit launcher paths and ports override configured defaults.
`-CheckOnly` reruns readiness without starting services or opening a research
workspace. Use `-Replace` when intentionally updating an existing configuration;
a failed check preserves its previous bytes.

Optional scientific environments can be saved with
`-ScientificProfiles @{methods='C:/Brohn/tooling/methods-venv/Scripts/python.exe'}`
(also `acquisition`, `vision-audio` and `segmentation`). Every supplied profile
must pass its actual dependency/model check before the configuration is saved.
The configuration records paths and ports, not participant data or credentials.
This command connects an installed runtime; it does not install dependencies.

### Launch with explicit paths

```powershell
./run-local.ps1 -RscriptPath $rscript -LibraryPath $applicationLibrary `
  -Workspace $workspace -Port 3838 -ParticipantPort 3840
```

Open `http://127.0.0.1:3838/`. The ports must be distinct. The launcher defaults
to the connected platform, preserves the selected workspace and restores its
process environment when it returns. Relative executable, library and workspace
paths are resolved before changing into the repository. Stop the launcher with
Ctrl+C; the supervisor owns its participant and processing children. Do not
start a second supervisor over the same workspace and ports.

This is a local loopback deployment. A browser running elsewhere cannot reach
the researcher's loopback participant link. Authenticated remote hosting,
transport security and operational access controls require a separate deployment
profile; changing a host address alone does not establish one.

The historical prototype remains explicit:

```powershell
./run-local.ps1 -Legacy -RscriptPath $rscript -LibraryPath $applicationLibrary -Port 3838
```

`scripts/run-local.R` is the legacy entry point. `app.R` defaults to the platform;
use `run-local.ps1` / `scripts/run-brohn.R` for the connected supervisor. Do not
assume that starting only a Shiny page also started collection and processing.

## Optional Python environments

| Profile | Exact requirements | Configure executable | Capabilities using the profile |
| --- | --- | --- | --- |
| methods | `scripts/benchmarks/requirements-methods.txt` | `BROHN_PYTHON_METHODS` | Peripheral physiology, EEG and associated typed signal processing |
| acquisition | `scripts/readiness/requirements-acquisition.txt` | `BROHN_PYTHON_ACQUISITION` | XDF/bundle preservation, fNIRS/native supporting formats and implemented acquisition tools |
| vision-audio | `scripts/readiness/requirements-media.txt` | `BROHN_PYTHON_VISION_AUDIO` | Imported/captured video geometry and audio analysis |
| segmentation | `scripts/readiness/requirements-segmentation.txt` | `BROHN_PYTHON_SEGMENTATION` | Reviewed point-assisted AOI proposals |

Keep all four environments separate. The working vision and segmentation
profiles deliberately use different MediaPipe and NumPy versions. A newer
version is not a compatible replacement unless its relevant contracts pass.

The optional installer requires an explicit Python 3.12 executable, named
profiles and a destination outside the repository:

```powershell
./scripts/install-python-profiles.ps1 `
  -PythonPath 'C:/Python312/python.exe' -Destination 'C:/Brohn/tooling' `
  -Profiles methods,acquisition,vision-audio,segmentation
```

It creates new virtual environments only, refuses existing target directories,
installs the exact requirement names/versions with binary wheels and no
additional dependency resolution, then runs `pip check`. It does not activate
environments, change global packages, fetch models or start acquisition. A
missing platform wheel fails visibly. Partial installation directories remain
for inspection; the script never recursively deletes or replaces them. Python
requirements are version freezes, not wheel-hash locks or evidence of a fresh
restore on every operating system. Positive fresh installer execution has not
been claimed by the readiness checks.

Configure the chosen environments before launching Brohn:

```powershell
$env:BROHN_PYTHON = 'C:/Python312/python.exe'  # standard-library design portability
$env:BROHN_PYTHON_METHODS = 'C:/Brohn/tooling/methods-venv/Scripts/python.exe'
$env:BROHN_PYTHON_ACQUISITION = 'C:/Brohn/tooling/acquisition-venv/Scripts/python.exe'
$env:BROHN_PYTHON_VISION_AUDIO = 'C:/Brohn/tooling/vision-audio-venv/Scripts/python.exe'
$env:BROHN_PYTHON_SEGMENTATION = 'C:/Brohn/tooling/segmentation-venv/Scripts/python.exe'
```

An explicitly configured missing executable fails rather than using a different
scientific profile. The original development checkout also recognizes prepared
`../../work/tooling/<profile>-venv` paths. Those directories are not distributed
with the repository; configure absolute paths for a portable installation.

## Model and codec prerequisites

Face/pose/hand models are pinned in `docs/preparation/media-models.json` and
checked against the vision worker's literal model identities. Store weights
outside the repository and set `BROHN_MEDIA_MODEL_DIR`. The active files are
`face_landmarker.task`, `pose_landmarker_lite.task` and `hand_landmarker.task`.
Only use the manifest's generation-pinned download URLs and verify both size
and SHA-256. The existing `scripts/readiness/prepare-media-models.py` is an
explicit downloader for the broader six-model preparation cache; if using it,
copy the pinned manifest to an external cache first and pass that copy as
`--manifest`. Do not overwrite the repository manifest with new observed hashes.

Segmentation uses **MagicTouch v1**, independently from that broader media cache.
Set `BROHN_SEGMENTATION_MODEL_PATH` to `magic_touch_v1.tflite`. Its exact official
URL/generation, 6,227,884-byte size and SHA-256 are recorded in
[SEGMENTATION-TOOLING.md](../preparation/SEGMENTATION-TOOLING.md). The doctor reads
the preparation record and verifies agreement with the worker's pinned hash.
MagicTouch v2 is not the active segmentation model.

Browser recording assembly requires `ffprobe`; video analysis also requires
`ffmpeg`. Both are currently resolved on `PATH`; no separate Brohn path variable
is implemented for either. Add the selected FFmpeg installation's `bin` directory
to `PATH` before running the doctor and launcher. The doctor invokes only
`-version`; it does not decode an input or activate a camera. Codec/version
availability alone does not qualify an arbitrary recording format.

## Readiness and support reports

```powershell
# Inspect core and all available optional environments, without making them mandatory.
& $rscript --vanilla scripts/doctor.R --library $applicationLibrary

# Require only the capabilities this installation promises to support.
& $rscript --vanilla scripts/doctor.R --library $applicationLibrary `
  --required-profiles methods,vision-audio --require-portability --require-ffprobe

# Machine-readable report; exit 0 means all required components are ready.
& $rscript --vanilla scripts/doctor.R --library $applicationLibrary --json
```

`--profiles none` skips optional scientific inspection; required report
publication is still checked. Required profiles are
always added to the checked set. Missing optional components remain visible but
do not fail core readiness; missing/mismatched required components return exit
code 1. `--require-portability` requires the standard-library ZIP helper and
`--require-ffprobe` requires recording assembly's decoder executable.

The Python inspector can also be run directly in the environment being checked:

```powershell
& $env:BROHN_PYTHON_METHODS -B scripts/check-scientific-runtime.py --profile methods
```

Reports include every pinned package's installed version, named worker API
imports, dependency consistency, model identities, interpreter paths and codec
support. They contain local installation paths but no participant database or
recording contents. Review paths before sharing a report publicly. Checks
perform no installation, network download, device discovery, camera/microphone
activation or model inference. Imports can load native libraries and ordinary
interpreter caches; they do not constitute acquisition.

## Evidence boundary

A fresh external R library was restored from the current 46-package lock and
passed fresh-process namespace, source and license checks with zero extras.
The doctor also inspected the existing four prepared Python 3.12.10 environments,
their full 38/54/43/26 package freezes, pinned active models and local codecs.
`tests/platform-installation.R` records required/optional failure behavior,
missing or altered library/pin/model/import evidence and installer refusal to
write inside the repository or replace an existing profile. It does not install
new Python environments or repeat scientific-method tests. Physical hardware,
camera consent comprehension, model accuracy and public hosting retain their
separate acceptance requirements.
