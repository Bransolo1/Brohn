# Best-worst visual evidence — 20 September 2026

Saved object-case paired MaxDiff results now include exposure-adjusted choice
plots and identifiable aggregate paired-utility plots. All declared items retain
their complete-pair denominators and unavailable results. Utilities are relative
zero-centred logits; no participant uncertainty or individual preference is
inferred. Missing choices never become zero preference.

Both responsive variants read the exact saved item/utility values and verify
retained design/response hashes. Complete labels and exact values accompany the
plots in tables. Standalone SVG and exact JSON chart-value downloads retain
source hashes, original labels, units, missing counts and method context. The
original choice ledger is available through existing report exports.

`tests/platform-maxdiff-plots.R` passes11 numerical/rendering checks. Its48
ordered-pair observations have counts9,18,4,12,2,3, proportional to the paired
likelihood with item strengths3,2,1. Independent expected adjusted values are
21/48,4/48,−25/48; fitted utilities match `log(c(3,2,1))` centred on zero within
1e−6. One additional omitted choice remains outside all48-pair denominators.
The existing MaxDiff UI suite passes32 checks.

Actual Chrome evidence is recorded in
`oka/work/brohn-maxdiff-plots-browser-01/browser`:10 checks and5 clear
accessibility/reflow/axis-label scans across choice, utility and saved interval
plots. The SVG download retains exact counts and escaped source labels. Narrow
screens use complete compact axes rather than requiring horizontal panning.
Screenshots were visually inspected. The later chart-value download addition
passes11 checks and5 clear scans in `oka/work/brohn-maxdiff-plots-browser-02/browser`, including the actual exact-value JSON download.

The fixtures are original synthetic counts. No observed participants or
population-level preference claims are implied.
