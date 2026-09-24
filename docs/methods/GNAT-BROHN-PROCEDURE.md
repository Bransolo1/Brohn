# Brohn single-target GNAT procedure

24 September 2026. **Procedure decision adopted; implementation and activation
remain pending.** Profile `gnat-brohn-single-target/1.0` is an original Brohn
adaptation. It supersedes the unresolved GNAT draft in
[PROTOCOL-TEMPLATES](../preparation/PROTOCOL-TEMPLATES.md#gnat-gnat-configured-sensitivity01-draft)
for this first implementation. It is neither an exact historical replication nor
a vendor implementation. The integration lead approved the 384-trial design,
explicit deadlines, endpoint correction and descriptive retention policy below.

## Primary-source decision

The [original Nosek and Banaji paper](https://banaji.sites.fas.harvard.edu/research/publications/articles/2001_Nosek_SC.pdf)
was retrieved and visually inspected, including printed pp. 631, 633-635, 646,
652 and 660-661. It varies context and timing across experiments. Table 1
(p. 631) lists 833/666 ms for Experiment 4; its prose (p. 646) says 750/600.
Page 634 uses a 0.35/n empty-cell correction; p. 635 excludes nonpositive
sensitivity. These are not the policies selected below. The paper does not
establish reliability for this Brohn adaptation.

The [current official demonstration manual](https://www.millisecond.com/library/v7/gnat/gnat/gnat/gnatdemo.manual)
also conflicts: procedure/parameters say 750/600 ms, summary labels 700/550.
It describes four 20-trial training blocks, then two rounds of four
16-practice/60-test pairings for two targets, a 500 ms offset-to-onset interval
and .005/.995 correction at exact endpoints. It explicitly identifies itself as
a demonstration. Brohn selects one target and the explicit decisions below;
neither source supplies a universal commercial-research default.

The author's PDF remains outside Git at
`work/references/gnat-20260924/2001_Nosek_SC.pdf`, relative to the outer workspace:
2,015,510 bytes; SHA256
`ebfe3ff2945c44c66e6e3f77f831effa8d6cd9214bc6ab91f3737de1a1cfe787`.
Its 22 scanned PDF pages include two printed pages per sheet and adjacent
material. The article's own heading gives *Social Cognition* 19(6), 625-664;
the manual's bibliography says 625-666. Local extracted text and inspected
page renders are retained beside the PDF. No vendor code, instructions or
stimulus library is copied into Brohn.

## Four roles and research context

There is one scored target, with four disjoint roles: `target`, `context`,
`attribute_positive`, `attribute_negative`. The context is a declared distractor
set, not a second scored target. Every study supplies its target, context kind
(`generic`, `single_category`, or `superordinate`), rationale, language, category
labels, exemplar IDs/text, material origin and rights. Generic context is the
demonstration default. An attribute-only context changes the quotas and is not
supported by this revision. Changes to context/materials require a new frozen
design; they cannot be pooled as equivalent conditions automatically.

The first profile uses text and a physical Space key. Each role has 2-64 distinct
exemplars; those are operational bounds, not sufficient-stimulus or reliability
criteria. Duplicate text within or across roles is rejected using this exact
comparison key: collapse and trim Unicode White_Space code points U+0009-000D,
0020, 0085, 00A0, 1680, 2000-200A, 2028, 2029, 202F, 205F and 3000 to ASCII
space; map ASCII A-Z to a-z; preserve every other code point. This is not Unicode
normalization, full case folding or transliteration. Original displayed text is
retained. Semantic ambiguity and valence suitability require the researcher's
review; software cannot certify them. Images, touch substitutions, different
attributes or adaptive deadlines need a separately qualified revision.

An original software rehearsal may use `Writing tools` (pencil, marker, fountain
pen, chalk), generic `Other things` (ladder, blanket, scooter, pebble), positive
(pleasant, joyful, superb, kind), and negative (awful, cruel, grim, nasty).
These familiar words form an authored demonstration, not a normed stimulus set.
Researchers replace them with materials appropriate to their question. The
participant instructions explain the actual named categories without describing
the participant as biased or announcing an expected result.

## Fixed sequence and sampling

| Phase | Trials and exact quotas | Signal/noise deadline |
| --- | --- | --- |
| Four single-role training blocks | Target Go/context No-Go; context Go/target No-Go; positive Go/negative No-Go; negative Go/positive No-Go. Each has 10 Go + 10 No-Go = 20. | 1,000/1,000 ms |
| Round 1, target + positive | 16 practice (4 from each role), then 60 test (15 from each role). Target and positive are Go; context and negative are No-Go. | 750/750 ms |
| Round 1, target + negative | Same quotas; target and negative are Go; context and positive are No-Go. | 750/750 ms |
| Round 2 | Both pairings again, with identical phase quotas. | 600/600 ms |

Total: **384 trials: 80 training + 64 pairing practice + 240 test**. Each of the
four scored cells has 30 signal and 30 noise opportunities. Training and practice
are one pass, with feedback but **no accuracy pass threshold or repeat**. Complete
practice errors do not become missing trials or silently prevent progression.
A technical interruption is handled separately below.

Round 1 always precedes round 2. Shuffle the four training blocks and select the
first pairing independently within each round using the frozen PRNG; the second
pairing is the other one. This randomization does not guarantee balance across
recruited people. Retain the actual order in each administration and report it.
Give a self-paced instruction screen before every training/pairing practice and
a self-paced reminder before every test phase. There are no timed instruction
screens, covert retries or adaptive trial additions.

Use the existing explicitly specified Park-Miller 16807/Fisher-Yates strategy,
independent of ambient R RNG state: initial state
`((seed + allocation_index - 2) %% 2147483646) + 1`. Before generating trials,
consume the training permutation and the two round-order draws. Each draw updates
state to `(state * 16807) %% 2147483647`, then uses `u = state / 2147483647`.
Fisher-Yates visits indices `n` down to `2`, swapping with `floor(u * i) + 1`;
each round's next draw chooses positive-first when `u < .5`, negative-first
otherwise. For each phase in realized order, shuffle its complete category-quota
vector (constructed in the four-role order above). Initialize decks only for
used roles, in that same order, by shuffling each role's materials in their
frozen source-array order. Fill trials from those decks, reshuffling an exhausted
deck when its next trial is reached. Start fresh decks at each phase. Adjacent
repetition across deck boundaries is allowed and retained. No extra run-length
restriction or outcome-dependent reshuffle is applied. Independently test and
pin the complete realized table, seed, allocation, procedure hash and sequence
hash.

## Trial, feedback and withholding

Display one centered text exemplar with the current Go category labels remaining
visible. Category meaning must not depend on color. The participant presses
Space for either Go category and does nothing otherwise. No error correction is
requested. Wait for Space release before presenting the next stimulus; a held
instruction key cannot become a trial response. Retain the extra release wait.

An eligible first trusted, unmodified, nonrepeat Space keydown has a timestamp in the
half-open interval **`[requested_onset, requested_onset + deadline)`**. Exactly at
the deadline is late. Record event timestamp and dispatch/observation time
separately. On the first eligible Space, request stimulus removal and close the
response window; otherwise request removal when the deadline expires. Preserve
requested deadline and actual removal observation separately. A scheduling delay
does not extend the accepted response window.

Start 100 ms of correct/error symbol **and text** feedback at the observed
stimulus-removal transition, followed by at least 400 ms blank. The next requested
onset is no earlier than 500 ms after that removal, and requires Space released.
This is an offset-to-onset interval, not 500 ms after feedback and not a fixed
onset-to-onset interval. Preserve actual onset/offset for both phases, including
late animation frames. All phases use the same page clock. Optional self-paced
reminders are outside this timing interval.

| Expected action | Eligible Space | Intact full window with no eligible Space |
| --- | --- | --- |
| Go | `hit` | `miss` |
| No-Go | `false_alarm` | `correct_rejection` |

Miss and correct rejection have **null key and null response latency**. Never
write zero or the deadline as their RT. The separately recorded observation
duration is not a response latency. Other keys, untrusted/repeat/held/early/late
events remain diagnostic events and cannot become Go responses. Space held at
onset, impossible key state or contradictory evidence invalidates the trial;
it cannot earn correct withholding. Do not silently drop an earlier eligible
key because a later callback timed out first.

The renderer retains a complete key/visibility/focus stream and requested
animation-frame onset, deadline, offset and page-clock identity. At a no-response
deadline, allow the timeout task and a subsequent animation frame to drain
already queued eligible key events before sealing withholding. Any subsequently
observed key whose timestamp contradicts that sealed outcome **interrupts the
task**. Preserve both receipts; do not revise history or keep a manufactured
correct rejection. Event dispatch has no guaranteed maximum delay, so this is
explicit software evidence, not proof of physical visual timing or attention.

Hidden tab, lost focus, page restart, clock change, failed durable event write,
missing required phase evidence or duplicate/conflicting trial receipt interrupts
the timed task. No active trial or task is resumed/restarted under the same
administration. Retain the local journal for reconciliation and use existing
interruption/researcher-resolution flow. Starting a deliberately new run is
separate. Withholding requires a continuously eligible visible/focused window;
an unobserved interval is unavailable evidence, never a correct rejection.

## Scoring and understandable results

Score separately for each round and pairing. Only its 60 exact, replay-qualified
test trials can establish an available cell; training/practice and invalid or
incomplete cells do not contribute. A run interrupted later may retain earlier
complete-cell descriptive counts, but has no completed-administration result or
cohort eligibility. Do not fill missing trials or silently use a reduced quota.

Let `H = hits / (hits + misses)` and
`F = false_alarms / (false_alarms + correct_rejections)`.
Keep their integer denominators and uncorrected values. Under recipe
`gnat-brohn-endpoint005/1.0`, replace **only exact 0 with .005 and exact 1 with
.995**. Interior rates are unchanged, not clipped and not given pseudocounts.
Compute `d_prime = qnorm(H_corrected) - qnorm(F_corrected)` and
`criterion = -0.5 * (qnorm(H_corrected) + qnorm(F_corrected))`.
The round contrast is `d_prime_target_positive - d_prime_target_negative`.

Both cells must be available for a contrast. Never pool the two deadlines, combine
different contexts or use an IAT D-score. Preserve nonpositive sensitivity and
flag it as little/reversed signal discrimination; it is not automatic participant
exclusion. Exact endpoint corrections, all-Go/all-No-Go and low discrimination
are visible support flags. No extra RT trimming, quality-based person exclusion,
preference bands or diagnostic interpretation is part of this profile. Actual
response RT can be described separately, split by hit/false alarm, with its own
denominator; it does not define the GNAT score.

Lead reports with the target/context, two deadline-specific contrasts and the
plain-language meaning: positive values mean better discrimination in the
target-positive pairing **in this task and context**. Show sensitivity, criterion,
four outcome counts, raw/corrected rates, timing/support and actual pairing order
in numerical detail. No absolute attitude, commercial prediction or individual
reliability claim follows from software agreement.

## Machine-readable contract proposal

The exact profile object should encode these values rather than infer them from
labels. Researcher materials/context/seed live in the frozen source block; the
compiler retains that block and its canonical design hash.

```json
{
  "id": "gnat-brohn-single-target/1.0",
  "roles": ["target", "context", "attribute_positive", "attribute_negative"],
  "stimulus_mode": "text",
  "go_code": "Space",
  "training_blocks": 4,
  "training_trials_per_block": 20,
  "training_go_no_go_counts": [10, 10],
  "training_signal_noise_deadline_ms": [1000, 1000],
  "round_signal_noise_deadlines_ms": [[750, 750], [600, 600]],
  "pairings_per_round": ["target_positive", "target_negative"],
  "pairing_practice_role_counts": [4, 4, 4, 4],
  "pairing_test_role_counts": [15, 15, 15, 15],
  "practice_policy": "one_pass_no_threshold_no_repeat",
  "response_interval": "onset_inclusive_deadline_exclusive",
  "stimulus_offset": "first_eligible_space_or_deadline",
  "feedback_ms": 100,
  "offset_to_next_onset_min_ms": 500,
  "require_space_release": true,
  "late_dispatch_after_seal": "interrupt_preserve_evidence",
  "timed_restart": "forbidden",
  "scoring_binding": "brohn-gnat-single-target-score/1.0",
  "arithmetic_rule": "gnat-brohn-endpoint005/1.0",
  "endpoint_rates": [0.005, 0.995],
  "interior_rate_adjustment": "none",
  "cell_required_test_signal_noise": [30, 30],
  "nonpositive_sensitivity": "retain_with_support_flag",
  "contrast": "target_positive_minus_target_negative_within_round",
  "pool_deadlines": false,
  "additional_rt_trimming": "none"
}
```

## Activation evidence still required

The [implementation packet](../qa/GNAT-NEXT-IMPLEMENTATION-PACKET.md) owns shared
hooks and connected acceptance. Before registration, independently verify exact
384-trial quotas, all category/Go mappings, order/deck replay and arithmetic,
including 8/10 hits and 2/10 false alarms (`d_prime = 1.6832424671458286`,
criterion zero), exact endpoints, reversed rates, missing denominators,
practice exclusion and incomplete cells. The small arithmetic example is a
reducer oracle, not a publishable 10-trial procedure.

Then exercise actual full researcher/participant delivery, first-key and genuine
withholding evidence, exact boundary and delayed-dispatch races, held keys,
visibility loss, restart refusal, durable upload retries, independent server
replay and native-worker scoring. Verify raw export/import without fabricated
latencies, person/visit cohort weighting, portable design reuse and saved results
after restart. Scan and visually inspect authoring, instructions and results for
keyboard access, phone comprehension and readable feedback; unsupported input
must be explained before timed collection. Existing six profiles and preserved
participant runtimes must remain unchanged. These establish software behavior;
population/material reliability and measured physical timing remain separate.
