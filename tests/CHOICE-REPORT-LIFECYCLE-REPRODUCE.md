# Choice report lifecycle checks

Use the configured R library and methods Python from the installation guide.
Each output directory must be new and outside the repository or a real research
workspace. The component tests create their own synthetic SQLite records.

```text
Rscript tests/report-choice-package-intents.R <repo-root> <fresh-intent-evidence>
Rscript tests/report-choice-package-ui-state.R <repo-root> <fresh-ui-evidence>
Rscript tests/report-choice-shared-cancellation.R <repo-root> <fresh-sharing-evidence>
Rscript tests/report-task-package-intents.R <repo-root> <fresh-legacy-intent-evidence>
```

The choice intent test covers 29 checks with real stored intents/jobs and
explicit preparation/scientific boundary spies. It checks source admission,
exact preparation versions, mandatory complete evidence, dependency order,
sharing, cancellation, retry, panel review and immutable implementation plans.
The UI test has 29 controller/view checks with declared backend spies. The
separate shared-cancellation test reproduces a failed consumer retaining shared
running dependencies: cancelling their owner preserves those jobs until the
remaining consumer explicitly cancels. These are component checks, not browser
or scientific qualification. The existing task intent test retains its 28
checks; its preparation stub accepts the newly explicit optional profile.

## Actual child cancellation and lease replacement

First run `tests/choice-display-backend.R` as described in
[the source/preparation guide](CHOICE-DISPLAY-REPRODUCE.md). Its `originals/`
directory contains generated synthetic sources with two completed scientific
jobs and no display preparations. Then run:

```text
Rscript tests/choice-display-lifetime.R <repo-root> <generated-evidence/originals> <fresh-lifetime-evidence>
```

This test requires `BROHN_PUBLICATION_NATIVE_MANIFEST`,
`BROHN_PUBLICATION_PYTHON`, `BROHN_PYTHON_METHODS` and the installed R library.
It copies the generated workspace into its new output directory. It never runs
against the input workspace or a participant dataset.

The recorded 15-check execution starts the genuine, unchanged native choice
worker. Parent-process instrumentation observes the first poll while that child
is alive, then injects normal API cancellation or normal lease reclamation under
a temporary test clock. A release wrapper observes the child already stopped
while the original source, protocol, journal and input-bundle guards remain
live, then delegates normal release. It checks scratch cleanup, refusal of
obsolete publication before artifact access, no overwrite of the replacement
lease, no saved display/object, and unchanged original science and source bytes.

This is an instrumented supervisor test. It does not establish real wall-clock
expiry, hosted identity-provider behavior, physical timing or successful choice
preparation. Successful preparation, independent numerical exports and actual
browser cancellation/recovery have separate evidence. Every attempt and its
diagnostics remain available; no test output belongs in Git.

Use [the pure report guide](CHOICE-REPORT-REPRODUCE.md) for complete source-to-ZIP
checks. Read the [acceptance record](../docs/qa/CHOICE-REPORT-PACKAGE-ACCEPTANCE.md)
for the exact source phases and limitations of the connected researcher test.
