# Declared comparison families: bounded academic appraisal

Reviewed 1 October 2026. This follows the 30 September design audit's unresolved
Holm source review. It does not alter that historical audit or any calculation.
The inspected application is joined10, `paired-consumer-comparisons/1.0-draft`.
No complete recipe, template or consumer-population qualification is asserted.

## Verified sources and contribution

- Sture Holm (1979), *A Simple Sequentially Rejective Multiple Test Procedure*,
  Scandinavian Journal of Statistics 6(2), 65–70. [Original paper, university
  copy](https://www.ime.usp.br/~abe/lista/pdf4R8xPVzCnX.pdf),
  [stable record](https://www.jstor.org/stable/4615733). Inspected pp.66–67,
  section2, Scheme1 and Theorem1. Ordered tests proceed until the first failed
  threshold; the remaining hypotheses are not rejected. The proof bounds the
  probability of any false rejection across every true-null configuration.
  The same section supplies the ordinary Bonferroni bound. This is statistical
  theory, not empirical validation of Brohn's participant contrasts or sensors.
- Jelle J. Goeman and Aldo Solari (2010), *The sequential rejection principle
  of familywise error control*, Annals of Statistics 38(6), 3782–3810.
  [DOI](https://doi.org/10.1214/10-AOS829),
  [author text](https://arxiv.org/html/1211.3313v1). Inspected section3,
  equations11–13 and Holm construction. The argument requires valid marginal
  p-values under their nulls; Bonferroni provides the single-step bound without
  requiring independent outcomes. Section2 separates this from additional
  assumptions of other procedures. This independent author group corroborates
  the mathematical conditions, not consumer construct validity. The journal
  year is2010; the arXiv deposit is2012.
- Kevin S. S. Henning and Peter H. Westfall (2015), *Closed Testing in
  Pharmaceutical Research: Historical and Recent Developments*, Statistics in
  Biopharmaceutical Research 7(2), 126–147.
  [Full text](https://pmc.ncbi.nlm.nih.gov/articles/PMC4564263/),
  [DOI](https://doi.org/10.1080/19466315.2015.1004270). Inspected sections3–5:
  closed-test adjusted values maximize intersection-test p-values over sets
  containing the hypothesis; Bonferroni intersection tests give Holm. This
  supports an independent exhaustive-closure numerical oracle. Section4 makes
  directional-error protection a separate question. Pharmaceutical examples
  do not qualify consumer templates or justify declaring a commercial winner.
- [R stats documentation](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/p.adjust.html),
  inspected Details and `n` argument. A family size larger than the supplied
  vector retains unobserved comparisons in the adjustment; its Holm convention
  places unobserved values above the observed values. This is implementation
  documentation and is not counted as another academic source. The online
  development manual is not proof of the installed runtime version.

## Application findings and remaining decisions

`R/platform-analysis-plan.R` admits one named draft recipe and Holm with a
user-selected alpha. Its allowed alpha range is a software bound, not a
scientifically recommended range. The family is the full declared comparisons
list, including comparisons without usable data. All same-modality hypotheses
use `stats::p.adjust(..., n=family)`; if some belong to another modality, the
saved report uses `min(1, p*family)` and labels the incomplete-family branch.
The latter is a conservative product policy, not a mathematical claim that
Holm can never be bounded with missing values. No automatic policy change is
made here; it would need an explicit version and historical compatibility.

Unavailable p-values remain unavailable; they must never be presented as
measured p=1, zero effects or evidence for no difference. Padding with1 in the
test oracle is a mathematical bound only. Its derivation is our inference:
replacing unavailable tests with never-rejecting values cannot add rejections
to monotone Holm when the other marginal p-values remain valid. This does not
repair selective sampling, optional stopping, invalid individual tests, or
families chosen after looking at results.

Point estimates and 95% Student intervals remain ordinary equal-person
summaries; the intervals are explicitly unadjusted. Familywise adjustment of
p-values does not make those intervals simultaneous. A nonsignificant test
does not establish equivalence. These are required interpretation distinctions
for the next in-app evidence record and report wording review.

Independent numerical work here tests adjustment and integration only.
Normality/robustness, participant/stimulus sampling, repeated-visit weighting,
missing-data sensitivity, trial timing, instrument validity, prespecification
and population transfer remain separately required. Existing descriptive
support counts must not become a sample-size recommendation.

## Connected acceptance work

Retain an exact source receipt and run the real analysis-plan function on
synthetic declared designs, without mocking p-values or inference. Compare its
reported marginal tests to SciPy and its adjusted values to exhaustive closed
Bonferroni testing, independently of R's ordered implementation. Cover ties,
order permutations, missing outcomes, single-person and zero-variance cases,
cross-modality families, repeated visits and unknown identity. Then bind the
review to a new evidence revision and actual plan/result/report guidance.
This packet alone does not activate evidence capture or change recipes.
