# Local guided application

For the connected platform, follow [local installation](operations/LOCAL-INSTALLATION.md)
and run `./run-local.ps1` or `Rscript --vanilla scripts/run-brohn.R` from the repo.
The [active sprint](sprints/02-full-platform.md) and [researcher QA](qa/RESEARCHER-QA.md)
track its current behavior. The sections below describe the retained historical
prototype, available with `./run-local.ps1 -Legacy`.

From the repository root in PowerShell: `./run-local.ps1`.
Open http://127.0.0.1:3838 in a browser. Stop the server with Ctrl+C.
Use `-Port 3840` for another local port or `-RscriptPath` for a particular Rscript.
The launcher uses Rscript from PATH, then this workspace's isolated test runtime.
With R already available on another system: `Rscript scripts/run-local.R`.

## Implemented flow

1. Create a study or open the explicitly labelled guided sample.
2. Name the study, select a control if relevant, and add two PNG images in Plan.
3. Define named image areas by drawing or entering percentages. Matching names
   are paired across designs. Plan viewing duration and order independently.
4. Keep, remove or reword the linked seven-point liking question.
5. Review both planned sequences (or a selected fixed order) with control roles.
6. In a guided sample, open Results for the fictional AOI calculation. Export
   the report and use examples/reproduce-sample.R to recalculate it independently.
7. In Collect, create a working copy of a sample or use an existing preview draft.
   Choose a prepared interval CSV to check/calculate/save automatically. Results
   export original CSV bytes and the study snapshot; reopening restores the latest
   matching analysis. See methods/PREPARED-CSV.md for format and resource limits.
8. Save explicitly or navigate to save automatically. Return to My studies and
   reopen a saved draft, or export/import its JSON.

Study IDs stay stable when names change. Meaningful draft changes increment the
study revision; changed question wording also increments its question revision.
Re-adding a removed question receives a new identity. Existing extra modality
selections and question metadata are preserved when editing. Bundles containing
recording metadata, or pilot/live origin, are read-only in this editor.

Collect explains what is still being built. Review checks draft structure and
previews intended sequences; no order assignment or timing is active. The sample
has no participant recording or calibrated device. Its explicitly fictional
intervals yield a draft calculation: default Brand mark differences 20, 30 and
10 percentage points, mean 20. It is not a qualified scientific finding. AOI
changes recalculate against the same fictional inputs. Replacement of either
sample image blocks this demonstration; open a fresh guided sample to restore it.

## Storage and errors

The default folder is data/drafts, ignored by Git. Set RESEARCH_PLATFORM_DATA to
use another local folder. JSON import makes a local copy on the next save; it does
not overwrite the uploaded source. Export includes current valid form changes.
Files are limited to 16 MB and parsed as UTF-8.

In Review, save a protocol snapshot after adding both images. Export downloads
the frozen study and planned registry. Snapshots live in `<draft.json>.protocols`;
reopening restores the matching copy, and edits retain the previous files.
See methods/PROTOCOL-SNAPSHOTS.md for integrity and remaining runner work.

A save validates first, writes a temporary file in the destination folder, then
renames it into place. Failed writes/replacements retain the old file. Existing
files require explicit overwrite, matching study/run/origin and, in the app, the
fingerprint observed at open/last save. Fingerprints detect stale edits; they are
not cryptographic authorship proofs. Locks coordinate this app's writers, not
arbitrary external editors. Atomic rename is not a promise of power-loss durability
or network-filesystem behavior. After a crash, inspect any remaining .lock directory
and confirm there is no active save before removing that lock.

Errors stay visible without replacing the saved draft. Unsaved form edits are
marked, and closing/reloading the page with edits triggers a browser guard.
Fast navigation flushes form values before Shiny's action event, avoiding the
default text-input debounce race.

## Verification and remaining work

Native Windows contract and storage tests and Shiny server workflow tests pass.
Browser verification covers rapid name/question edits, save/reopen, both PNG
uploads, pointer and keyboard AOIs, control choice, sample calculation and export,
prepared CSV import, automatic analysis save/reopen and report reproduction.
Narrow and desktop layouts were inspected. Controls use labels, visible focus,
a skip link, keyboard-focusable scrolling tables and live status
messages. This is not a WCAG audit or undergraduate usability qualification.

Production packaging, a dependency lock, multi-user authentication, backups,
participant collection, device timing and validated automated analyses remain
future increments. The planning archive retains those requirements. Control,
baseline, practice and order requirements are in methods/CONTROL-DESIGN.md.
