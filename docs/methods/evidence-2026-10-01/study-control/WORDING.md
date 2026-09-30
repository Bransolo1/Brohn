# Focused prospective wording; no frozen source changed

The source15 scan found **no literal four-trial “ABBA” description** in the inspected R, method registry or method/design documents, and no affirmative promise of general carryover balance. The ambiguity in the task's shorthand is resolved by the actual compiler: **AB/BA across allocation indices**. Other task-specific alternating blocks are outside this comparison-starter claim.

| Exact current location | Assessment | Prospective wording |
|---|---|---|
| `R/platform-guidance-views.R:110`: “Counterbalanced order is selected; all settings remain inspectable.” | True but underspecified starter guidance, not an established incorrect algorithm. | “The two stimuli alternate AB and BA across allocation indices. Review order and usable completion; this does not remove all carryover.” |
| `R/platform-views.R:45`: “These are declared presentation settings. Physiological recipes check whether their baseline and response windows have enough support.” | Could imply every physiological recipe validates the planned baseline. A blank phase alone supplies no recorded sensor evidence. | “These are planned display timings. A baseline phase needs a suitable recorded signal and the selected analysis recipe's required support; it does not by itself establish an adequate physiological baseline or recovery period.” |
| `registry/method-evidence-0.2.json`, claim `comparison-starter-order`, binding `/order`, statement/nonclaims around lines 1931–1938 | Correctly calls rotation operational and not universally carryover-balanced. Historical revision stays exact. | Future revision may add: “For two stimuli, AB and BA are assigned to successive allocation indices, not four trials ABBA within a participant. Larger stimulus sets rotate cyclically; achieved usable balance is separate.” |
| `R/platform-views.R:12,40`; `docs/methods/CONTROL-DESIGN.md:8`; `docs/methods/evidence-2026-09-30/study-design/EVIDENCE.md:12` | Already distinguish control from physiological baseline and cyclic rotation from general carryover balance. | Preserve. No correction needed. |

The existing evidence claim's locator points to the constructor at line 58. A future revision can additionally bind `brohn_compile` lines 315–317 and delivery allocation lines 258–260. It must say **stimuli**, not an arbitrary number of conditions: conditions can contain multiple stimuli, and a stimulus-position rotation need not balance condition histories.

`CONTROL-DESIGN.md` and `PROTOCOL-SNAPSHOTS.md` contain explicitly historical statements about absent delivery. The former's current-scope notice already distinguishes the current runner. Do not reuse an isolated historical paragraph as the current feature account.

Default values are operational starting values. No proposed wording upgrades source15's physiological, timing, baseline or stimulus-population inference status. Changing a saved template, sequence or calculation later requires its ordinary versioned contract and explicit rerun where relevant.
