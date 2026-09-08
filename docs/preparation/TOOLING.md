# Development tools — 2026-09-08

**Expanded inventory:** [LARGE-BUILD-READINESS.md](LARGE-BUILD-READINESS.md) indexes
the later acquisition, platform/statistics, survey/task, vision/audio and compatible
segmentation packs, seven external model artifacts and 101 new reference assertions.
This file retains the original app-development setup; consult the expanded records
for current installed versions and inference evidence. App dependencies are unchanged.

## Installed locally

| Tool | Version | Purpose |
| --- | --- | --- |
| renv | 1.2.4 | Exact 32-package R snapshot/restore; no app-package upgrades or automatic activation. |
| Playwright test | 1.63.0 | Browser regressions, traces, downloads and screenshots. |
| axe Playwright integration | 4.13.0 | Automated accessibility scans of rendered app states. |
| jsPsych | 8.3.0 | Candidate participant runtime, separate from R/Shiny timing. |
| jsPsych plugins | HTML/image keyboard and survey-likert 2.2.0; preload 2.1.0 | Small compatible stimulus/response starting set. Not a BIAT/AAT scorer or general survey builder. |
| Quarto | 1.10.18 | Portable report renderer at ../../work/tooling/quarto-1.10.18. |
| MNE / NeuroKit2 / CVXOPT | 1.12.1 / 0.2.13 / 1.3.2 | Isolated Python 3.12.10 method environment; 38 package pins, reference scripts and `pip check` pass. Not an activated app worker. |
| R method libraries | saccades 0.2-1, zoom 2.0.6; IATscores 0.2.8, implicitMeasures 1.0.0 | Separate gaze/implicit research libraries; source hashes and reference comparisons recorded. |

Existing R 4.6.1, Node 24.19.0, pnpm 11.19.0 and Git are reused. JavaScript tools
are pinned development dependencies in package.json/pnpm-lock.yaml. Declared
licences: Playwright Apache-2.0, axe integration MPL-2.0, jsPsych/plugins MIT.
R source/licence declarations and fresh-restore evidence are in [R-TOOLING.md](R-TOOLING.md).
Dependency declarations do not select a project licence or complete a redistribution review.

The managed Chromium download timed out. Browser checks use installed Chrome
152.0.7977.82 in a fresh headless profile and isolated app on port 3849. The
Chrome version is observed, not pinned. User browser sessions and port 3838 are
not reused. Synthetic drafts live in ignored data/browser-tests folders.

Quarto's [official release](https://github.com/quarto-dev/quarto-cli/releases/tag/v1.10.18)
Windows archive was checked before extraction against SHA-256
`4e824652ff0da3f646868277582ed59c0872d1456e35350b7d7cdc4243ee18c2`.
No global PATH setting changed. R-executed templates and PDF/TeX are separate work.

Verification: a standalone synthetic HTML document rendered successfully with
embedded resources. All six browser checks passed after repairing the missing
page title/language and invalid default download-icon attributes. Library/Review
axe scans reported no violations for the tested tags and viewports; incomplete
checks and untested flows still require manual review. The installed jsPsych
plugins loaded, and a synthetic keyboard trial completed at both viewport sizes.

## Commands

Use configured Rscript/Node/pnpm from the repository root. R snapshot/restore
commands are in [R-TOOLING.md](R-TOOLING.md).

```powershell
pnpm install --frozen-lockfile
pnpm check:tools
$env:PLAYWRIGHT_CHANNEL = 'chrome'
pnpm test:browser
```

Set RESEARCH_RSCRIPT for a custom R executable. Otherwise the test server uses
this workspace's native R/library fallback, or Rscript on PATH. It refuses an
occupied test port. Results are in test-results/browser-results.json with axe
attachments. Coverage is library/Review, protocol save/export/reopen and synthetic
jsPsych execution at desktop/narrow sizes. It is not a whole-app accessibility audit.

When the network allows, `pnpm exec playwright install chromium` installs the
managed browser; unset PLAYWRIGHT_CHANNEL to use it. PLAYWRIGHT_BROWSERS_PATH can
select a local cache. [Playwright describes axe and manual testing](https://playwright.dev/docs/accessibility-testing).
[renv supports snapshots without project activation](https://rstudio.github.io/renv/reference/snapshot.html).

## Investigated for later waves

| Candidate | Decision and next check |
| --- | --- |
| MediaPipe Face Landmarker | Now installed with its model; isolated negative-frame smoke checks are in [MEDIA-TOOLING.md](MEDIA-TOOLING.md). No camera capture or product adapter is enabled. Quality/timestamp mapping and interpretation remain method-specific. [Official outputs](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker). |
| WebGazer | Interchangeable candidate, not a sole dependency: maintainer says updates are no longer guaranteed from February 24, 2026. Check calibration and held-out error. [Maintainer notice](https://webgazer.cs.brown.edu/). |
| LSL | Installed with a synthetic, exact-source local loopback check in [ACQUISITION-TOOLING.md](ACQUISITION-TOOLING.md). Named-device clocks, offsets/drift, gaps and sidecar recovery still require configuration evidence; simulation cannot establish physical onset accuracy. [Introduction](https://labstreaminglayer.readthedocs.io/info/intro.html). |
| MNE-Python / NeuroKit2 | Installed and reference-tested; [method register](../methods/reuse/README.md) and [commands](../../scripts/benchmarks/README.md) define the evidence and next worker integration. R retains contract/recipe authority. |
| SQLite + R workers; Arrow/Parquet | Proposed experiments for transactional allocation/jobs and bounded typed recordings. Test against run manifests before choosing final package versions. Not installed capabilities. |
| SurveyJS | Form Library is MIT; Creator/Dashboard/PDF have separate terms. Keep an open schema/executor and accessible authoring UI. Its open-source exception does not make Creator MIT. [Licensing](https://surveyjs.io/licensing), [FAQ](https://surveyjs.io/faq/licensing). |
| GitHub | Existing Git supports local work. Account connection, destination and project licence remain publication inputs. No remote, paid subscription or plugin connection created. |

jsPsych's [timing guidance](https://www.jspsych.org/latest/overview/timing-accuracy/)
requires care over presentation/input accuracy; the smoke check proves execution
compatibility only. Existing search/browser tools can fill specific competitor
flow gaps: preserve permitted screenshots with provenance, never tutorial MP4s.
