# Initial behavioral protocol templates

Prepared 2026-09-08. These are proposed, named implementation profiles for the large build, not claims of completed Brohn tasks. The [existing IAT/BIAT/AAT specification](../methods/reuse/IMPLICIT-REUSE.md) remains canonical.

Each profile must compile into a frozen trial table, response contract, scorer and report. **Source-defined settings** below are separated from **required design fields**: the latter must be supplied by a reviewed study template, then need no repeated participant-level configuration. A missing field prevents study publication, while allowing an explicitly labelled rehearsal. Changed timing, input, counts or scoring creates a new profile revision.

## Shared runner and report contract

Record planned and observed onset/offset, source clock, frame intervals, stimulus/control IDs, block/order, first response, corrections, accuracy, omission and abort separately. Keep practice outside test outcomes. Persist the seed and realized sequence; resume must preserve assignment rather than reshuffle.

Required design fields include licensed stimuli/instructions, language, geometry, input mapping, randomization constraints, practice/retry policy, participant exclusions and minimum valid support. “No additional trimming” is an explicit policy; no algorithm may invent universal RT cutoffs. Missing responses never become correct trials or ordinary latencies.

Report condition counts, errors/omissions, included/excluded support, latency definition, score formula/direction, timing deviations and participant-level uncertainty/group contrasts. Pair physiology to actual stimulus, response, feedback and rest phases. Pilot reliability belongs to the actual trial count; shortened tasks do not inherit another version's badge.

## SC-IAT: `sc-iat-ms-corrected/0.1-draft`

Choose the **correction-inclusive Inquisit variant**, explicitly distinct from Karpinski–Steinman's response-window/400-ms-penalty procedure. Flow: 24 practice, 72 test, reversed pairing with 24 practice and 72 test; counterbalance pairing order. Use E/I, 250-ms pretrial pause, stimulus until correct response, reminder disabled. Preserve initial errors and final-correct RT. [Official variant specification](https://www.millisecond.com/library/v7/iat/sc_iat/singlecategoryiat/singlecategory/singlecategoryiat.manual)

**Scorer binding remains required before analytical activation.** Bind this vendor procedure to its exact source-versioned vendor scorer, with the script/reference hash, score direction, SD definition, exclusion order and eligible fast-trial denominator recorded. The manual references improved IAT scoring but does not fully specify those implementation details; it is insufficient to justify choosing a new two-block formula. Do not substitute Brohn's full-IAT scorer, add a second error penalty or label this the original SC-IAT method. The runner can support rehearsal while this binding is unresolved; source-output replay must establish scorer agreement before enabling results.

**Required:** the source-anchored scorer binding above, per-category counts in each block, stimulus sampling/repetition, positive direction labels, full trial-key mapping and valid-support policy. The compiler checks the 24/72 totals and category quotas. Report the source-defined score, block summaries, initial error rate, corrections, exclusions and order. Original Karpinski–Steinman scoring requires its own original-procedure profile; do not mix its rules into this vendor variant.

## GNAT: `gnat-configured-sensitivity/0.1-draft`

**Historical preparation profile.** The implemented first GNAT route follows
[Brohn single-target GNAT](../methods/GNAT-BROHN-PROCEDURE.md),
`gnat-brohn-single-target/1.0`, with explicit quotas and a complete response
contract. Use that specification and its linked acceptance records for current
development; the September 8 notes below remain background research.

Flow: single-category practice, then target-plus-attribute Go versus declared distractor No-Go blocks; compare target+positive against target+negative at each deadline. Fix spacebar Go, no-response No-Go and 500-ms ISI. The official demonstration lists 1000-ms practice and 750/600-ms test deadlines, but inconsistent summary labels say 700/550; **the manifest's explicit signal/noise deadlines govern**. The source author calls the demo minimalist, not a reliability-optimized research protocol. [Author-derived official GNAT manual](https://www.millisecond.com/library/v7/gnat/gnat/gnat/gnatdemo.manual)

**Required:** target/noise context, deadline rounds, signal/noise counts per pairing, practice count/pass rule and pairing order. Compile balanced comparisons within each deadline; do not pool deadlines silently. Source-compatible scorer: `d'=qnorm(hit_rate)-qnorm(false_alarm_rate)`, replacing only exact 0/1 rates with .005/.995; save both original and corrected rates. Report hits/misses/false alarms/correct rejections, d', criterion and positive-minus-negative d' by deadline. Practice and incomplete/unusable cells cannot yield a score. GNAT is accuracy-based; timeout on a No-Go trial is potentially correct.

## Evaluative priming: `ep-ms-matched-baseline/0.1-draft`

Use the official supraliminal Fazio-derived adaptation: 12 practice trials; two 24-trial unprimed baseline blocks; 96 primed tests comprising 24 each for A, B and two filler categories. Match A/B prime pairs to the same positive/negative adjective targets. Randomize trials and persist pair assignments. Sequence: prime/fixation 315 ms, blank 135 ms, target up to 1750 ms, ITI 2500 ms. [Official procedure and scorer](https://www.millisecond.com/library/v7/evaluativepriming/evaluativepriming/evaluativepriming.manual)

Score each correct test trial as that adjective's mean correct baseline RT minus test RT, then aggregate by prime and target valence. Incorrect/omitted trials do not receive facilitation scores; absent valid target baseline remains unavailable. Report baseline support, accuracy, facilitation and prespecified A/B contrasts.

**Required:** six images per category, 12 positive/12 negative adjectives, pair assignment scheme, E/I mapping, instructions and valid baseline support. New stimulus counts, omitted fillers, masking or different SOA become separate profiles; this profile makes no subliminal claim.

## AMP: `amp-ms-three-prime/0.1-draft`

Use 10 practice and 48 test trials: 16 each for A, B and neutral prime, in randomized order. Present prime 75 ms, blank 125 ms, ambiguous target 100 ms, then mask; ask for target pleasant/unpleasant evaluation, preserving the instruction to evaluate the target. [Official AMP manual](https://www.millisecond.com/library/v7/amp/amp/amp.manual)

Score the pleasant-response proportion per prime; contrasts A-neutral and B-neutral are percentage-point differences. RT is descriptive, not a D-score. Exclude practice; abort/missing evaluations are unavailable, never “unpleasant.” Report numerator/denominator, contrasts, omissions and target allocation.

**Required:** suitable ambiguous-target and prime sets, allocation/reuse rule, E/I mapping, mask persistence/response availability, ITI and any timeout policy. Declare these rather than infer unreported timing from a diagram. Screen-refresh quantization must be recorded for 75-ms delivery; the implemented duration must be visible in the manifest.

## Simple and choice RT: `dl-simple/0.1-draft`, `dl-four-choice/0.1-draft`

Adopt the documented Deary–Liewald-derived keyboard variants: simple = 8 practice + 20 test, central X, key B; choice = 8 practice + 40 test, X in one of four boxes, C/V/N/M left-to-right. Foreperiod spans 1000–3000 ms. [Simple specification](https://www.millisecond.com/library/v7/drearyliewaldreactiontimetask/dls/dls.manual), [choice specification](https://www.millisecond.com/library/v7/drearyliewaldreactiontimetask/dlc/dlc.manual)

Keep pre-onset responses without terminating the trial. Use target-onset RT, not trial-start latency; responses above 5000 ms are retained but excluded from valid summaries. Report correct RT mean/median/sample SD, errors, early/late counts and trial support; no imported age-percentile norms.

**Required:** sampled foreperiod distribution, choice-location sampling, task order, geometry and keyboard-layout mapping. Freeze practice feedback separately; choice source uses 500-ms practice error feedback and none in tests. A researcher-controlled abort is distinct from a response timeout.

## Interference: `stroop-keyboard-control/0.1-draft`

The official keyboard profile has 84 randomized tests: four ink colors × congruent/incongruent/rectangle-control × seven repeats. D/F/J/K map red/green/blue/black; stimulus persists until response; ITI 200 ms, error feedback 400 ms. [Official Stroop profile](https://www.millisecond.com/library/v7/stroop/colorwordstroop/stroop_keyboard/stroop_keyboard/stroopwithcontrolkeyboard.manual)

Brohn reports correct-RT incongruent-minus-congruent and incongruent-minus-control separately, with accuracy and cell counts. No unrequested composite “inhibition score.” **Required:** practice policy, incongruent word-allocation table, exact randomization constraints, color/display eligibility and any trimming/abort rule. Keep practice separate from 84 tests and expose color/input incompatibility before collection. Changing to speech or emotional words creates another profile.

## Interference: `arrow-flanker-ms-short/0.1-draft`

Choose the official simplified arrow variant: 8-trial practice, ≥75% accuracy, at most three attempts; 24 tests with six per congruence × direction cell. Q/P answer the central arrow's direction. Fixation 1000 ms, response window 1750 ms, response highlight 100 ms, blank 500 ms. [Official short Flanker profile](https://www.millisecond.com/library/v7/flankertask/arrowflankertest/arrowflankertest_keyboard/arrowflankertest_keyboard/arrowflankertest_keyboard.manual)

**Required:** balanced shuffled trial table, arrow geometry and practice-feedback sequence. Failed practice ends with a recorded reason. Correct-RT incongruent-minus-congruent is Brohn's primary contrast; errors and omissions remain separate accuracy outcomes. Report practice attempts, cell means, valid counts and uncertainty. This is a short documented adaptation; it is not the full 1997 design, a clinical norm or evidence of reliable individual differences.
