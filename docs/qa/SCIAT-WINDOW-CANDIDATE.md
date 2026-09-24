# Response-window SC-IAT candidate

24 September 2026. This is a separate, unregistered candidate. It does not change
any existing task, accepted score, participant renderer or import format. The
earlier [Millisecond contract](SCIAT-IMPLEMENTATION-CONTRACT.md) remains its own
correction-inclusive candidate and qualification route.

## Decision

Prototype the **response-window SC-IAT with implicitMeasures 1.0.0 arithmetic** as
`sciat-response-window-im100/0.1-candidate`. Use the maintained open package as an
independent numerical comparator, with original Brohn code and synthetic inputs.
Do not call this exact Karpinski-Steinman-2006 or Millisecond reproduction. The
documented package arithmetic includes an error-penalty base that needs explicit
naming; it must not be silently replaced with a correct-response-only mean.

This closes a useful implementation gate without waiting for a proprietary
runtime: a precise, testable reducer and explicit proposal for delivery. It does
not yet qualify a participant task. The candidate module is intentionally absent
from the application loader and registered profile list.

## Sources and distinctions

The original authors' [2007 Society for Consumer Psychology paper, printed page
121](https://myscp.org/wp-content/uploads/2023/03/2007-proceedings.pdf#page=149)
describes two pairings, each with 24 practice and 72 test trials. It uses a
1,500 ms response window, a 500 ms omission reminder, and 150 ms accuracy feedback
after each response. Stimuli are sampled without replacement within categories.
Its physical response keys are Z and numeric-keypad 2. This is firsthand evidence
for that response-window procedure, but its brief conference report does not
resolve every reset, interval and scoring detail needed by a browser renderer.

The [2006 original article record](https://pubmed.ncbi.nlm.nih.gov/16834477/) was
verified, but its full methods have not been recovered from an authoritative
open source in this audit. Later papers make materially different choices about
correction, deadlines, errors and SD support. Their shared use of the name SC-IAT
does not prove interchangeability.

The maintained [implicitMeasures source at commit
41b3812ab1d94f624113eb3e11028cf50fff6b2c](https://github.com/OttaviaE/implicitMeasures/tree/41b3812ab1d94f624113eb3e11028cf50fff6b2c)
reports version 1.0.0 and MIT licensing. Its authors' [software
paper](https://doi.org/10.1177/01466216251371532) and [current SC-IAT
vignette](https://www.stats.bris.ac.uk/R/web/packages/implicitMeasures/vignettes/SC-IAT-example.html)
describe the package route. The retained reference probe uses the separately
prepared local `r-library-implicit-methods` library; no application dependency is
added. Runtime agreement, independent arithmetic and scientific validity remain
different claims.

The public [Hussey PsychoPy example](https://github.com/ianhussey/SingleCategoryImplicitAssociationTest)
is a GPL beta, written for PsychoPy 1.82.01, with a different 20/72/72 block layout.
It explicitly lacks independent code checking. It is useful as a design comparison,
not a maintained runtime oracle for this candidate. No vendor task source or
stimulus materials are retained by this work.

## Exact numerical proposal

The prototype accepts explicitly typed test-trial rows for one administration.
It does not accept aggregate means, infer omissions from NA, or reconstruct key
events. A row is either a response with finite numeric latency and literal logical
accuracy, or an explicit omission with neither latency nor accuracy. The proposed
response window is enforced: responses beyond 1,500 ms cannot be silently scored
as omissions or winsorized. Practice is outside the reducer, supplied explicitly
by the eventual trusted replay adapter.

Let A mean target with the positive attribute, and B target with the negative
attribute. The first response ends a trial; this candidate does not require an
error correction. For each mapping:

1. Remove explicit omissions, then response latencies below 350 ms. Exactly
   350 ms remains. Retain the reason for every excluded row.
2. Compute the replacement base as the mean of **all retained response latencies
   in that mapping, including incorrect responses**. Replace each retained
   incorrect latency with that base plus 400 ms. This is the pinned package rule.
3. Compute each mapping's mean after replacement. Compute one sample SD (N-1)
   from the original retained **correct** latencies pooled across both mappings.
4. Retain the package-sign result `(mean_A - mean_B) / SD` and a separately named
   display direction `(mean_B - mean_A) / SD`. A positive display value indicates
   faster target-positive classification in this declared contrast. There are no
   preference-strength bands or individual psychological diagnoses.

Keep the unfiltered presented test denominator, explicit omission count,
responded denominator, fast removals, retained correct/error counts and both
mapping means. Count accuracy before fast removal among actual responses, matching
the package's support for its below-.75 flag. Also disclose accuracy over all
presented trials with omissions separate, so neither denominator is concealed.
The flag remains a QC flag; it does not invent participant exclusion or erase the
reference number. Empty mapping support, no retained correct observations, less
than two pooled correct observations or zero/nonfinite SD yields unavailable.

The package contains ancillary behaviors that must not be adopted as authority:
its capitalized order comparison mislabels an A-first sequence; some diagnostic
columns are rounded proportions despite count-like names; and its single-level
tables can report zero when all responses fall in a flagged class. Running its
actual functions also exposed a single-administration mixed-fast-trial table
failure (`arguments imply differing number of rows: 0, 1`). The prototype
derives order and exact counts from retained rows itself. Reference comparisons
target the numerical D/means and supported accuracy fields; tests must expose,
not hide, ancillary disagreement.

## Adopted delivery decision, 24 September 2026

The implementation lead adopted the following choices within the authorized
platform scope as **`sciat-brohn-response-window-im100/1.0`**. The new constructor,
compiler, dedicated replay and browser state machine implement this separate
Brohn adaptation. Registration and connected delivery remain a subsequent gate;
the arithmetic prototype above does not itself qualify a participant task.

| Component | Source-supported or explicit implementation choice |
| --- | --- |
| Three roles | One target plus positive and negative attributes; no dummy second target |
| Blocks | 24 practice + 72 test in each pairing; declared A-first/B-first assignment retained |
| Category quotas | Adopted 7:7:10 / 7:10:7 practice and 21:21:30 / 21:30:21 test; consistent with the separately audited library, but not specified by the short 2007 paper |
| Response window | 1,500 ms from the requested stimulus onset, first valid physical key ends the response phase |
| Feedback | 150 ms correct/error feedback, or 500 ms omission reminder; every phase onset/offset retained |
| Response keys | Adopted E/I for laptop keyboards; explicitly differs from the original Z/keypad-2 arrangement |
| Intertrial blank | Adopted 250 ms after feedback; explicitly a Brohn adaptation, not resolved by the cited short paper |
| Sampling | Seeded category quota shuffle; independently shuffled exemplar cycles reset per block; fixed Park-Miller/Fisher-Yates implementation independent of R RNG configuration |
| Deadline boundary | Event timestamp at or before 1,500 ms; pending timeout accepts eligible queued keys even when its timer callback ran first; an eligible key arriving after an omission has been sealed interrupts the task instead of silently retaining a false omission |
| Timing qualification | Browser timestamps and requested durations retained separately from measured physical onset; focus loss/refresh interrupts active timed work |

Do not combine this proposal with the existing correction-required participant
runner until a dedicated first-response/timeout/feedback state machine, replay
validator and immutable profile receipt are implemented. A timed-task refresh
must not quietly restart a trial or acquire a second complete administration.
These operational choices belong to the named Brohn variant; they cannot be
attributed to the original paper by implication. Browser event dispatch has no
unbounded guarantee: omission sealing waits through a timer task and subsequent
animation frame, and later contradictory evidence interrupts. Requested onset
and feedback are animation-frame-before-paint observations, not physical display
measurements. Refresh conservatively interrupts even at block instructions;
existing session storage and exactly-once batch retry own lost acknowledgments.

## Next connected slice

After prototype agreement: dedicated authoring for exactly three roles, frozen
procedure preview, complete compiler and first-response replay; two opposite-order
real browser administrations of all 192 trials; native-worker scoring; complete
trial export/import with declared timing semantics; accessible saved report and
cohort support with one administration distinguished from one linked person.
Include omissions, first-key errors, deadline ties, held keys, focus loss,
withdrawal, lost acknowledgment and offline replay. No shortening of the actual
acceptance task and no vendor-equivalence claim.

## Evidence

The unregistered reducer is implemented in
`R/platform-sciat-window-candidate.R`. On 24 September 2026,
`tests/platform-sciat-window-candidate.R` passed **44 checks** and the independent
`tests/verify-sciat-window-candidate.py` passed **40 checks**. Evidence is retained
outside the repository at:

`C:/Users/User/Documents/Codex/2026-09-05/make/work/test-runs/brohn-sciat-window-candidate-20260924-02`

The seven numerical cases cover correct-only support, error replacement,
explicit omissions and 350/1,500 ms boundaries, exactly/below .75 accuracy,
opposite mapping order, and complete 144-row test counts. Five insufficient-support
cases remain unavailable, and fourteen malformed input contracts are rejected.
The Python oracle uses exact rational arithmetic for replacement bases, adjusted
means and correct-only sample variance; it imports no Brohn code or R package.
Every case checks original values, score inputs, denominators and both directions.

The installed `clean_sciat` and `compute_sciat` function bodies were compared with
the pinned upstream commit and matched exactly. Upstream source was fetched for
that check in memory; source bytes and SHA-256 identities are in the receipt.
Following the observed single-administration table failure, the external numerical
probe supplies two separately labelled synthetic copies of each case so the
package preserves its diagnostic table dimensions. Both returned scores and
supported accuracy fields are checked. These copies are a comparator fixture,
not independent research observations. The failure itself and the incorrect
upstream order label are explicitly asserted and retained. The Brohn reducer
continues to accept one administration, with its own independent arithmetic oracle.

| Evidence | SHA-256 |
| --- | --- |
| `results.json` | `f250d50f0e9021a27752214f5f1f95db5bbe4e85a51dc006a28fe2e20667c505` |
| `independent-arithmetic-audit.json` | `517e7ea0b2abd4ef4743660bb22fb50245ddfd81a790849651ff9a1f07b8d382` |
| Reducer source used by these checks | `d8f161b6873efb4d9719824a7937be702ae97986fd232baea7c4507cfec5f30e` |

This evidence establishes arithmetic and typed-input behavior for the named
candidate only. No participant browser task, replay, physical timing, reliability,
construct validity, or original-method/vendor equivalence is qualified. The
delivery choices above are now adopted for a separately named Brohn core, whose
[implementation evidence](SCIAT-WINDOW-CORE-ACCEPTANCE.md) remains separate from
these arithmetic receipts; existing profiles and scores are unchanged at this
prototype checkpoint. The preliminary `-01` test attempt ended at the upstream table
error and is retained as a failed reference probe, not a passing receipt.
