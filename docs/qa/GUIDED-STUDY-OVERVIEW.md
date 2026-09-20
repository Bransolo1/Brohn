# Guided study entry and saved overview

Executed 20 September 2026 on the local Windows R / Chrome profile. This is a
focused BWP-15 implementation checkpoint, not a claim of human usability,
scientific, sensor or timing qualification.

## Connected behavior

- Home offers a visible preview of Brohn's original fictional packaging design,
  an explicit practice-design action, a personal-study action and the existing
  reusable-design library. Merely viewing Home creates no study or observation.
- New comparison, questionnaire and custom-study choices explain their real
  starting structure. New, cloned and template-based studies continue in Plan.
  A short Plan introduction connects the draft to its overview.
- Opening an existing or practice study enters Overview. Saved design validation,
  material content, linked source metadata and release/session records drive its
  next action. Empty materials and questionnaires lead directly to their relevant
  controls. Imported data needing mapping takes priority over saved reports.
- Original practice designs default collection to `sample`; creating or previewing
  the design does not publish a release or allocate a participant session.
- Overview shows study intent, selected measures, actual dataset/report/session
  counts, labelled origins and earlier immutable releases. Measure selection is
  explicitly separate from a usable collection route. Sessions are labelled as
  visits, without implying distinct people or scientifically valid observations.
- Collection routes and version/reuse details use native disclosure controls.
  Archived studies retain inspection and a clear History recovery path.
- Participant-sequence preview compiles the exact saved design with example
  allocation 1. It is a read-only list of outer study steps, paged in groups of 25.
  It includes exact question/instruction text and response choices. Configured
  task blocks direct researchers to Tasks for their full trial timeline. It does
  not represent a participant rendering, assigned session or timing test.

The view installer is `brohn_install_guidance_ui()`. Root registration uses
`brohn_guided_home_ui()`, `brohn_start_study_ui()` and
`brohn_study_overview_ui()`. R retains validation, compilation and storage rules;
the researcher UI does not alter the independently served participant renderer.

## Executed evidence

`tests/platform-guidance-views.R` passed **32 checks**, using real temporary SQLite
storage and Shiny components. Coverage includes original no-data practice entry,
actual readiness corrections, sample default, exact project/origin aggregates,
no report/dataset body hydration for counts, pinned release versions, exact
compiler output, HTML escaping, bounded paging, stale/foreign command rejection,
access/source revocation clearing preview, archived recovery and unchanged
participant allocation.

`tests/researcher-guidance.mjs` passed **8 end-to-end assertions** and **8 automated
accessibility/layout scans** against the actual researcher app. The journey used
keyboard practice creation; opened and closed a saved preview with focus return;
checked sample origin; created and completed a text comparison; created a
questionnaire; reused its template as a new draft; and paged a 60-question source
beyond the first 50 steps. Final fixture counts were five studies, zero participant
sessions, zero datasets and zero reports.

All eight scans returned zero axe violations, horizontal overflow, undersized
native controls in the guided surfaces and broken example images. Views covered
1440-pixel desktop and 390-pixel narrow Home, Overview, creation dialog, saved
preview and return Home. Radio controls retain a 44-pixel labelled hit area;
the question-type picker is native so directed keyboard focus reaches it.

Retained local evidence:

```text
C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-guidance-20260920-04/
  browser-evidence-1789876441133/results.json
  browser-evidence-1789876441133/*-axe.json
  browser-evidence-1789876441133/*.png
  browser-evidence-1789876441133/researcher.log
  browser-evidence-1789876650357/visual-results.json
  browser-evidence-1789876650357/saved-*.png
```

The automated run exposed a real hidden-select focus failure, corrected by using
the native question-type select. Visual review corrected spacing after the next
action card. Harness-only failures from whitespace matching and an outdated
template-button label were corrected without changing product semantics.
The final read-only visual refresh passed another **5 scans** of saved Home,
Overview and participant-sequence preview; the desktop and narrow captures were
visually inspected after correcting the full-page capture scroll position.

## Reproduction and boundaries

```powershell
$env:R_LIBS_USER=(Resolve-Path ../../work/r-library-brohn-restore).Path
$env:LC_ALL='C'
& ../../work/native-r/bin/Rscript.exe --vanilla tests/platform-guidance-views.R
node tests/researcher-guidance.mjs <fresh-folder-named-brohn-guidance-...>
```

The fixture uses its own fresh workspace and starts only a loopback researcher
app. No participant service, acquisition device or scientific worker is started.
`--screenshots` reopens a completed fixture for a read-only visual refresh without
replaying study mutations. The initial full-page captures may show the keyboard
bypass link at the capture scroll position; the refresh mode resets the page
before each capture. This is a screenshot artifact, not an additional UI action.

Readiness reports the domain validator's current message, which can expose further
checks after a correction. It does not invent a complete checklist, task-duration
estimate, recruitment recommendation or device qualification. Multi-person
usability research, assistive-technology sessions and other viewport/browser
profiles remain unexecuted. Existing scientific method acceptance is unchanged.
