# GPT-6 Astra execution brief for Brohn

Prepared 2026-09-08. This is a launch brief for the next authorized implementation
run, not a change to model settings or a request to start it now. The objective is
one coherent Brohn product, delivered through connected, tested work packages.
A large run can retain checkpoints and continue across context refreshes; its
completion criteria remain observable product behavior.

## Why this preparation matters

Official OpenAI guidance identifies Astra's sensitivity to instruction files,
its tendency to ask consequential clarifying questions, and the value of explicit
delegation and appropriately scoped verification instructions. Our response is
to provide clear authority, working examples, assigned ownership and measurable
completion criteria. These are Brohn's proposed working practices, not guarantees
of model performance. [Official Astra prompting guidance](https://developers.openai.com/api/docs/guides/latest-model#prompting-best-practices).

Codex assembles global and project instruction files, with more local guidance
able to override earlier project guidance. Check the effective instructions at
launch so old piecemeal-sprint wording does not contradict the newly authorized
large build. Keep durable repository guidance concise; detailed task requirements
belong in the relevant specification. [Official AGENTS.md guidance](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

## The valuable inputs now available

- **A complete scope and dependency map:** the master architecture, 50-capability
  register and 17-work-package manifest retain the holistic brief. The old
  238-ticket dossier is indexed background, not a competing execution plan.
- **Runnable scientific references:** pinned engines, source-bound recipes,
  independent arithmetic examples, upstream replays and known API traps give
  concrete adapter requirements. Preserve the evidence category of each check.
- **Local development assets:** isolated R/Python/browser environments, model
  hashes, cached R binaries and reference scripts reduce setup uncertainty.
  Package availability and prototype checks remain distinct from product features.
- **Product direction:** the new brand, unified-experience and introduction
  specifications supply shared visual language, navigation and first-use behavior.
  Use their referenced assets and acceptance criteria across every module.
- **Continuity:** existing contracts, working draft/report readers, status,
  decisions and checkpoints explain what must remain compatible.

These inputs are sufficient to begin implementation. More broad competitor
research has lower immediate value than converting the shared contracts into
executable fixtures and connecting the first complete research journey.

## Authoritative reading order

1. Current user instructions, applicable `AGENTS.md`, `STATUS.md`, then
   [MASTER-ARCHITECTURE](../MASTER-ARCHITECTURE.md).
2. [Build manifest](build-manifest.json), [readiness index](LARGE-BUILD-READINESS.md)
   and the capability entries assigned to the active work package.
3. [Brand system](../brand/BRAND-SYSTEM.md),
   [unified experience](../product/UNIFIED-EXPERIENCE.md) and
   [introduction and launch](../product/INTRODUCTION-AND-LAUNCH.md).
   Include [the full lifecycle](../product/STUDY-LIFECYCLE.md) and
   [design portability](../product/DESIGN-PORTABILITY.md): the five study tabs
   alone do not cover historical libraries, participant deployment or reuse.
4. Relevant method/procedure specification, dependency notes, current module code
   and fixtures. Search the historical dossier only for an unresolved detail.

Read the overview once. Supply agents with focused excerpts and paths, rather
than repeatedly loading all screenshots, package logs or the entire dossier.
If a new decision conflicts with the master plan, resolve and record it before
different modules implement different interpretations.

## First implementation fixtures to create

These are planned build deliverables; they are not claimed as existing tests.

| Fixture | Required observable outcome |
|---|---|
| Frozen controlled study | Two stimulus conditions, separate baseline/practice/question phases, balanced assignment and stable compiled hash; reopened old drafts still work. |
| Realized run and responses | Repeated presentations have distinct IDs; zero/false survive; hidden/declined/unanswered differ; answer changes retain history; first and final-correct RT remain distinct. |
| Time and geometry | A source reset, missing span, large native tick and image transform survive R/browser/Python transfer without inferred synchrony or guessed units. |
| Interrupted work | Duplicate operation is replayed safely; conflicting reuse fails; an expired worker cannot publish after a retry; restart reconciles files and database state. |
| Analysis and correction | The known numerical result reproduces; changing one AOI/mask invalidates affected descendants; an optional missing channel does not erase valid results. |
| Whole user journey | Template to controlled run/import, automatic analysis, review, export and reopen after restart all use the same stored records. |
| Historical research and reuse | Migrate all retained artifacts, search archived studies/datasets, open the original report, clone design and reanalyse data as distinct operations. |
| Portable design | Export/import into a fresh workspace preserves independently specified graph, timing, controls, AOIs and scoring behavior; new identity, no observations/secrets and no automatic deployment. |
| Participant delivery and closure | Fresh-browser link opens the pinned release, consent/quota/resume/endings work, finalization reconciles uploads, and restoring a backup cannot reopen recruitment. |
| Visual and accessible states | Empty, populated, processing, failure and recovery screens share the brand; keyboard/reflow/contrast and plot alternatives meet the product acceptance criteria. |

Use original synthetic fixtures and approved public references. Specify expected
results independently of the adapter under test. Record which failures are
intentional injections; retain unexpected failure/correction evidence.

## Coordinating the implementation

The coordinator owns shared schemas, migrations, integration fixtures, navigation
contracts and manifest updates. Stabilize BWP01/BWP02 first, then compiler,
questionnaire, runner and acquisition interfaces through BWP06. A designer can
prepare components concurrently against the agreed commands and state models.
BWP08–BWP12 can then proceed independently where their manifest prerequisites
are satisfied. Integration remains a continuing responsibility, not a final merge.

Every delegated package receives a compact packet:

```text
Work package and researcher outcome:
Prerequisites and accepted contract/schema revision:
Exact files this worker may edit; shared files owned elsewhere:
Relevant specification sections and reference fixture paths:
Inputs, outputs, failure states and compatibility requirements:
Acceptance commands plus expected numerical or UI outcomes:
Current blocker, decisions already settled and remaining discretion:
Return: changes, evidence, unresolved issues and next integration action.
```

Use exact file ownership, including tests and documentation. Shared-file changes
go through the coordinator; another worker does not silently alter a schema or
dependency environment. After integration, run the affected cross-module checks
and inspect the actual UI. Keep meaningful numerical fixtures separate from
visual evidence. A screenshot proves a rendered state, not correct scoring;
a numerical test proves arithmetic, not an understandable workflow.

At each checkpoint update the manifest's status and evidence, `STATUS.md`, the
active sprint and `CHANGELOG.md`. Add decisions to `docs/DECISIONS.md` with the
choice, reason, affected contracts and consequence. Continuation notes retain
active package IDs, changed files, last passing commands, failures and the next
concrete action. They should let the next context resume without replanning.

## Ready-to-paste launch prompt

```text
Use GPT-6 Astra for the authorized large Brohn implementation. Build the complete
platform described by docs/MASTER-ARCHITECTURE.md and
docs/preparation/build-manifest.json. Preserve every registered capability and
track actual progress; do not reduce the brief to an eye-tracking demo.

Start with applicable AGENTS.md, STATUS.md and the master architecture. Read
docs/preparation/LARGE-BUILD-READINESS.md and run scripts/readiness/check-plan.py.
Use docs/brand/BRAND-SYSTEM.md, docs/product/UNIFIED-EXPERIENCE.md and
docs/product/INTRODUCTION-AND-LAUNCH.md as the shared product design specification.
Inspect their referenced assets. Read only the method/code sections needed next.

Implement the shared schemas, migrations, durable storage/jobs and integration
fixtures before parallel modules depend on them. Keep R authoritative for study
semantics, eligibility, scoring and reports; use the prepared isolated workers
for timing, acquisition and expensive computation. Reuse pinned references and
preserve their documented settings, units, missingness and output conventions.

Give independent workers bounded packages, exact file ownership and shared
contract revisions. Keep one coordinator responsible for integration and common
files. Complete connected vertical journeys as you expand the method packs:
design, questions, collection/import, automatic analysis, review, report, restart.
Apply the same branding and accessible interaction patterns throughout.

Use ordinary implementation judgment within the agreed brief. Record consequential
design choices and continue useful independent work when an external input is
missing. An unavailable physical rig or paid provider blocks that named route,
not imported-data analysis or the rest of the platform. Do not fabricate access,
participant testing or scientific qualification. Installed packages and empty
menus do not count as completed capabilities.

Run meaningful checks for each changed numerical, contract, recovery and UI path.
Inspect desktop and narrow layouts plus keyboard flows and error states. Reuse
passing evidence until a change or unresolved issue warrants another run.
Keep progress messages concise and explain outcomes, remaining work and blockers.

Continue through the authorized manifest instead of stopping after one increment
or offering to continue. Maintain reviewable checkpoints and resume from them
after context refreshes. Stop dependent work only for a real unresolved external
requirement or explicit user stop; continue other ready packages. Keep blocked
packages explicit and never relabel them complete to close the run.

Before the final handoff, reconcile every package's status, run the required
integration/release checks and update STATUS.md, decisions, sprint and changelog.
Report working journeys, evidence, remaining scoped blockers and how to launch
Brohn. Repository publication still needs the destination/licence decisions.
Do not change account/model settings, redeem resets, schedule work or publish
externally as a substitute for completing the local implementation.
```
