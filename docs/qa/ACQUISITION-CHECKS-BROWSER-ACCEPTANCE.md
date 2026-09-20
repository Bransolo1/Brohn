# Acquisition criteria authoring and monitoring browser acceptance

Executed 20 September 2026 with restored native R and local Chrome. This is software acceptance using original synthetic sources; no physical device or person was used.

`tests/fixtures/researcher-acquisition-checks.R` creates an isolated study and an explicitly synthetic metadata-only discovery. `tests/researcher-acquisition-checks.mjs` drives the actual Collect form and public queue command, then replays that exact saved request through the production Python Writer. The fixture does not launch an acquisition manager or claim an outlet subscription test; the independent manager suite supplies that coverage.

The full pass recorded **7 checks and 5 clean scans**:

- Adding a criterion preserves prior authored values; new numeric support fields start blank.
- Original units and text code `001` survive review and the saved request without numeric coercion.
- Changing an approved threshold clears its exact-review approval; unreviewed Start preserves the form and queues nothing.
- The actual public queue freezes the reviewed rules, source units, typed codes and sample origin.
- Two replayed sources independently produce an unmet range check, passing finite-value check and passing exact text-code check. Each result uses 500 committed samples over 4.99 seconds. Stale and closed sources become unknown.
- Authoring and monitoring at desktop/390 pixels pass axe, page-overflow and 44-pixel control checks.

Evidence: `C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-acquisition-checks-03/browser-evidence-1789880511641`.

Visual review led to a final presentation refinement: monitoring keeps observed status/support visible and collapses each exact rule table under **Exact saved criterion**. The subsequent `--monitor-only` pass reused the saved model and rerendered current production UI: **3 checks, 3 clean scans**, including keyboard opening/closing of that disclosure. Desktop, narrow, stale and dedicated narrow waveform screenshots were inspected.

Final renderer evidence: `C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-acquisition-checks-03/browser-evidence-1789881360500`.

The earlier retained failed runs identified and corrected stale exact-review approval, duplicate accessible region labels and intrinsic grid overflow. Selectize hit targets are measured on the clickable control rather than its internal text input. Standalone monitoring pages reproduce the application container and border-box reset, and show one state per recording.

Reproduce from the repository root:

```powershell
node tests/researcher-acquisition-checks.mjs C:/path/to/brohn-acquisition-checks-new
node tests/researcher-acquisition-checks.mjs C:/path/to/brohn-acquisition-checks-new --monitor-only
```

The full command requires a new directory and the prepared runtimes at `../../work/native-r` and `../../work/r-library-brohn-restore`. The second command requires the first command's retained saved model. Owned app processes stop at completion; renderer-only mode launches no R app server.

Remaining product limitation: criteria are authored for each recording. Reusable reviewed acquisition setups, with fresh source/unit review on reuse, are a future workflow improvement. All measurement quality remains unqualified; selected checks do not establish physiological or physical-device validity.
