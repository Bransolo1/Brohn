# Connected researcher and participant regression

This test starts the ordinary `scripts/run-brohn.R` launcher. A real browser
creates a comparison study, saves a shared control and a version group, explicitly
turns off unrequested equipment checks, releases the study through **Collect**, and
opens the generated participant link. The participant completes instructions,
baseline/fixation/stimulus screens, a rating, answer review and Finish. The normal
continuous worker must produce the report shown in the researcher's Results page.
The test downloads that report and independently joins it to the original saved
design, protocol, requests, events, job and sealed output.

The runner uses fresh external directories. It never resets a previous study or
test run. Start it when no other R process is running and both selected ports are
free. This source is prepared for the connected checkpoint; a run passes only
when its own `AFTER-CLOSED.json` says `passed: true`. Successful software tests do
not establish physical device timing, camera/emotion validity or scientific
qualification. This journey uses text stimuli and a questionnaire.

## Setup

Use the repository's documented R installation, restore `renv.lock` into one
selected library, and configure its publication guard and methods/acquisition
Python environments as described in `docs/operations/LOCAL-INSTALLATION.md`.
The launcher performs its real readiness checks; this test does not replace them.

Install the existing browser dependencies with `pnpm install --frozen-lockfile`
at the checkout root. Use Python 3.10 or newer with `psutil==7.2.2` for the test
supervisor. Browser dependencies use the repository's existing `package.json`
and `pnpm-lock.yaml`; no second browser lock is provided. Supply an installed
Chrome/Chromium executable. The native application profile currently qualified
for this workflow is Windows; relocating paths is supported without implying
additional operating-system qualification.

Example from a checkout, with paths supplied by your installation:

```powershell
python -B tests/connected/run.py `
  --checkout . `
  --rscript "C:/R/bin/x64/Rscript.exe" `
  --r-library "C:/Brohn-dependencies/R-library" `
  --node "C:/Program Files/nodejs/node.exe" `
  --chrome "C:/Program Files/Google/Chrome/Application/chrome.exe" `
  --methods-python "C:/Brohn-dependencies/methods/Scripts/python.exe" `
  --acquisition-python "C:/Brohn-dependencies/acquisition/Scripts/python.exe" `
  --publication-native-manifest "C:/Brohn-dependencies/publication-guard.json" `
  --workspace "C:/Brohn-tests/connected-workspace-01" `
  --output "C:/Brohn-tests/connected-results-01"
```

Use short workspace paths on Windows because acquisition archives retain the
application's existing path limits. `--researcher-port` and `--participant-port`
default to 48010 and 48011 and must differ. `--browser-package` can point to an
already installed copy of the same locked development package; its lock must
match the tested checkout. Relative command-line paths resolve from the invoking shell directory; an omitted
browser package uses the resolved checkout root. There is no private development-machine fallback.

## Results and limits

The app/browser lifecycle has a 240-second ceiling, with the entire native phase
observed for at most 285 seconds and owned shutdown bounded within 300 seconds.
These include service startup and shutdown. Post-close source inspection has a
separate 30-second limit. The fresh independent closer has a 45-second outer
bound including hashing and physical process/port checks.

The output retains source/tool hashes, commands, exact observed process identities,
service health, original browser requests, screenshots, downloaded JSON and failure
logs. `PROCESS-RESULTS.json` records the native phase; `AFTER-CLOSED.json` records
independent closure and the saved-source oracle. Both must pass. The original
launcher normally stops its own participant and worker services; that is recorded
separately from a forced test timeout. Unknown processes are never terminated.

On failure, preserve the workspace and output. Diagnose the first failure before
running again with new directory names. Do not reuse a failed workspace, increase
timeouts to hide slow interactions, inject service readiness or edit the report.

The connected journey also checks the real cross-port study anchor/redirect, the exact stored HTML identity and its document CSP. After normal service shutdown, `document-guards.R` tests assigned/legacy publication and refusal of other request shapes in a separate disposable workspace. These checks stay inside the original240-second phase budget. `test_supervisor.py` supplies mock-only alias and process-observation failure regressions; it starts no native app, child process or listening socket. Run it with the selected Python environment before the connected qualification.

The selected executables, lock files, source files and listed package metadata are recorded; this is not a transitive hash of every installed dependency. Source aliases, symlinks and reparse points are refused. Uncertain process ownership produces retained failure evidence and cannot qualify a successful closure.

Before the complete journey, run the focused checks with the same selected Python:

```powershell
python -B tests/connected/test_supervisor.py
python -B tests/connected/test_catalogue_snapshot.py
```

The second check uses an isolated real SQLite fixture. Report inspection copies the closed catalogue and every present WAL/SHM sidecar into the output directory, verifies their original bytes, and reads only that copy in read-only mode. It never checkpoints or opens the original database; the original workspace files must remain byte-for-byte unchanged.
