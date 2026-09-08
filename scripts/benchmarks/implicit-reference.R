# Reference-only experiment. Never sourced by the Brohn app.
# Run from repository root with native Rscript --vanilla.
work <- normalizePath("../../work", winslash = "/", mustWork = TRUE)
.libPaths(c(file.path(work, "r-library-implicit-methods"),
            file.path(work, "r-library"), .libPaths()))
stopifnot(as.character(packageVersion("implicitMeasures")) == "1.0.0")
stopifnot(as.character(packageVersion("IATscores")) == "0.2.8")
library(implicitMeasures)
checks <- list()
record <- function(name, observed, expected, tolerance = 1e-12) {
  ok <- isTRUE(all.equal(observed, expected, tolerance = tolerance,
                         check.attributes = FALSE))
  checks[[name]] <<- list(passed = ok, observed = observed, expected = expected)
  stopifnot(ok)
}

# Bundled published example and bundled expected values: upstream regression,
# not an independent validation dataset. Neither trial rows nor real IDs exported.
data("raw_data", package = "implicitMeasures")
data("iatdscores", package = "implicitMeasures")
reference <- clean_iat(raw_data, sbj_id = "Participant", block_id = "blockcode",
  mapA_practice = "practice.iat.Milkbad", mapA_test = "test.iat.Milkbad",
  mapB_practice = "practice.iat.Milkgood", mapB_test = "test.iat.Milkgood",
  latency_id = "latency", accuracy_id = "correct", trial_id = "trialcode",
  trial_eliminate = c("reminder", "reminder1"))[[1]]
result <- compute_iat(reference, Dscore = "d1")
matched <- merge(result, iatdscores, by = "participant")
record("upstream_example_matched_count", nrow(matched), nrow(iatdscores))
record("upstream_example_max_absolute_D1_error",
       max(abs(matched$dscore_d1.x - matched$dscore_d1.y)), 0)

clean_fixture <- function(d) clean_iat(d, mapA_practice = "Ap",
  mapA_test = "At", mapB_practice = "Bp", mapB_test = "Bt")[[1]]
package_score <- function(d, algorithm = "d1") {
  # Its diagnostics crash for one participant with a mixed fast/slow flag table.
  # Duplicate as a distinctly labelled synthetic fixture to exercise the scorer;
  # this is a benchmark workaround, never a production-data transformation.
  fixture_id <- unique(d$participant)
  stopifnot(length(fixture_id) == 1)
  replica <- d
  replica$participant <- paste0(fixture_id, "_replica")
  scored <- compute_iat(clean_fixture(rbind(d, replica)), Dscore = algorithm)
  scored[scored$participant == fixture_id, paste0("dscore_", algorithm)]
}
positive <- data.frame(participant = "synthetic_positive",
  blockcode = rep(c("Ap", "At", "Bp", "Bt"), each = 2),
  latency = c(500, 700, 600, 800, 900, 1100, 1000, 1200), correct = 1)
# Both pair means differ by 400; each sum of squared deviations is 200000,
# n = 4, so sample SD = sqrt(200000/3). This calculation is independent.
expected_positive <- 400 / sqrt(200000 / 3)
record("independent_positive_D1", package_score(positive), expected_positive)
negative <- positive
negative$blockcode <- c(Ap = "Bp", At = "Bt", Bp = "Ap", Bt = "At")[negative$blockcode]
record("independent_mapping_reversal_D1", package_score(negative), -expected_positive)
corrected <- positive
corrected$correct[1] <- 0
corrected$latency[1] <- 1300 # final correct response; first error is not the RT.
# Practice means are now both 1000: practice D = 0; test D unchanged.
record("independent_corrected_error_D1", package_score(corrected), expected_positive / 2)
corrected_flag <- corrected
corrected_flag$correct[1] <- 1
record("no_additional_D1_error_penalty", package_score(corrected_flag), package_score(corrected))
slow <- rbind(positive, transform(positive[1, ], latency = 10001))
single_error <- tryCatch({
  compute_iat(clean_fixture(slow), Dscore = "d1")
  "unexpected_success"
}, error = function(e) conditionMessage(e))
record("upstream_single_participant_slow_trial_crash",
       grepl("differing number of rows", single_error), TRUE)
record("independent_slow_trial_removal", package_score(slow), expected_positive)

# Explicit reference QC adapter: selects four combined blocks, removes >10000,
# then calculates the exact unrounded <300 fraction per participant. It only
# selects rows; package compute_iat still owns D scoring. Complete trial contracts
# and nonfinite/missing/zero-SD checks are separate production prerequisites.
reference_qc <- function(d) {
  d <- d[d$blockcode %in% c("Ap", "At", "Bp", "Bt"), ]
  stopifnot(all(is.finite(d$latency)), all(d$latency > 0))
  d <- d[d$latency <= 10000, ]
  rates <- aggregate(latency ~ participant, d, function(x) mean(x < 300))
  names(rates)[2] <- "fast_fraction"
  rates$excluded <- rates$fast_fraction > .10
  list(audit = rates, eligible = d[!d$participant %in% rates$participant[rates$excluded], ])
}
fast <- positive[rep(1:8, each = 5), ]
fast$participant <- "synthetic_boundary"
fast$latency[1:4] <- 250
record("exact_ten_percent_retained", reference_qc(fast)$audit$excluded, FALSE)
fast$latency[5] <- 250
record("above_ten_percent_excluded", reference_qc(fast)$audit$excluded, TRUE)
record("independent_fast_fraction", reference_qc(fast)$audit$fast_fraction, 5 / 40)
# A reproducible upstream finding: 12.5% fast input still receives a D1 score.
record("upstream_fast_exclusion_not_applied", length(package_score(fast)), 1L)
record("QC_adapter_removes_fast_participant", nrow(reference_qc(fast)$eligible), 0L)
after_slow <- fast
after_slow$latency[5] <- 10001
record("denominator_after_slow_removal", reference_qc(after_slow)$audit$fast_fraction, 4 / 39)
record("post_slow_denominator_changes_boundary", reference_qc(after_slow)$audit$excluded, TRUE)

# D4 comparison against the ordered steps of GNB2003 Table 4, deliberately
# separate from the selected D1 profile. Error substitution changes the SD in
# implicitMeasures, whereas the table first calculates inclusive SD.
d4 <- positive
d4$latency[5:6] <- c(1000, 1200)
d4$correct[1] <- 0
canonical_d4 <- (100 / sqrt(290000 / 3) + expected_positive) / 2
post_replacement_d4 <- (100 / sqrt(210000 / 3) + expected_positive) / 2
record("upstream_D4_uses_postreplacement_SD", package_score(d4, "d4"), post_replacement_d4)
record("D4_differs_from_Table4_order", abs(package_score(d4, "d4") - canonical_d4) > 1e-8, TRUE)

# Independent package API with explicit D1 parameters. No copied scorer and no
# synthetic replication needed. Task exclusions remain the QC adapter's job.
iat_scores <- function(clean) {
  subjects <- unique(clean$participant)
  d <- data.frame(subject = match(clean$participant, subjects),
    blockcode = ifelse(clean$condition == "MappingA", "pair1", "pair2"),
    praccrit = ifelse(clean$block_pool == "practice", "prac", "crit"),
    latency = clean$latency, correct = clean$correct)
  out <- suppressMessages(IATscores::RobustScores(d, P1 = "none", P2 = "ignore",
    P3 = "dscore", P4 = "dist", autoremove = FALSE, verbose = FALSE))
  data.frame(participant = subjects[out$subject], D1 = out$p1112)
}
independent_package <- iat_scores(reference)
cross_package <- merge(independent_package, iatdscores, by = "participant")
record("independent_package_all_reference_rows", nrow(cross_package), nrow(iatdscores))
record("independent_package_reference_max_absolute_error",
       max(abs(cross_package$D1 - cross_package$dscore_d1)), 0)
record("IATscores_independent_positive", iat_scores(clean_fixture(positive))$D1, expected_positive)
record("IATscores_independent_reversed", iat_scores(clean_fixture(negative))$D1, -expected_positive)
record("IATscores_independent_corrected_error", iat_scores(clean_fixture(corrected))$D1, expected_positive / 2)
record("IATscores_single_participant_slow_trial", iat_scores(clean_fixture(slow))$D1, expected_positive)
record("IATscores_requires_external_fast_screen", nrow(iat_scores(clean_fixture(fast))), 1L)
at_boundary <- positive
at_boundary$latency[1] <- 10000
# Independent explicit calculation retains exactly 10000 (not >10000).
boundary_expected <- ((1000 - 5350) / sqrt(sum((c(10000,700,900,1100) - 3175)^2) / 3) + expected_positive) / 2
record("IATscores_retains_exact_10000", iat_scores(clean_fixture(at_boundary))$D1, boundary_expected)

# BIAT denominator fixtures resolve the old vague gate independently of any
# full task runner: one excluded 16-trial block, four 4-trial prefixes, >10 s
# omitted; count <300 on remaining original final-correct latencies, then clamp.
biat <- data.frame(block = c(rep(1, 16), rep(2:5, each = 20)),
                   trial = c(1:16, rep(1:20, 4)), latency = 700)
biat$latency[biat$block == 1 | biat$trial <= 4] <- 250
biat$latency[which(biat$block == 2 & biat$trial %in% 5:10)] <- 250
biat$latency[which(biat$block == 3 & biat$trial == 5)] <- 10001
eligible <- biat[biat$block > 1 & biat$trial > 4 & biat$latency <= 10000, ]
record("BIAT_eligible_denominator", nrow(eligible), 63L)
record("BIAT_original_fast_numerator", sum(eligible$latency < 300), 6L)
record("BIAT_exact_fraction_before_recoding", mean(eligible$latency < 300), 6 / 63)
record("BIAT_fast_count_would_be_lost_after_recoding",
       sum(pmin(2000, pmax(400, eligible$latency)) < 300), 0L)

packages <- installed.packages(lib.loc = file.path(work, "r-library-implicit-methods"))
output <- list(
  generated_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  status = "reference_benchmark_only_not_production_or_psychometric_qualification",
  profile = "iat-gnb2003-d1-reference/0.1.0",
  R = R.version.string,
  packages = list(
    primary_candidate = list(name = "IATscores", version = "0.2.8", license = "GPL-2",
      API = "RobustScores(P1='none', P2='ignore', P3='dscore', P4='dist', autoremove=FALSE)",
      function_sha256 = digest::digest(IATscores::RobustScores, algo = "sha256")),
    comparison = list(name = "implicitMeasures", version = "1.0.0", license = "MIT + file LICENSE",
      compute_iat_sha256 = digest::digest(compute_iat, algo = "sha256"))),
  isolated_packages = unname(lapply(seq_len(nrow(packages)), function(i)
    list(name = packages[i, "Package"], version = packages[i, "Version"], license = packages[i, "License"]))),
  upstream_regression = list(source = "implicitMeasures::raw_data and implicitMeasures::iatdscores",
    real_trial_rows_exported = FALSE, independent_reference = FALSE, D1_only = TRUE),
  checks = checks,
  D4_comparison = list(package_D4 = package_score(d4, "d4"),
                      table4_order = canonical_d4, difference = post_replacement_d4 - canonical_d4),
  source_findings = list(
    compute_iat = "https://github.com/cran/implicitMeasures/blob/1.0.0/R/compute_iat.R",
    fast_flag = "Lines 159-175 compute out_fast, but later code never filters it; 168-171 also overwrite all flags using successive participant denominators.",
    D4 = "Lines 250-253 replace errors; lines 392-395 calculate variance of latency_cor afterwards.",
    single_participant = single_error,
    IATScore = "Source-only review 0.2.0: postreplacement SD; SpeedProp == .10 matches neither return branch. Not installed or used.",
    IATscores = "Installed 0.2.8, D1 parameter profile independently tested; autoremove=TRUE adds <3-correct-latencies rule and is explicitly disabled. Fast-task screening is external QC."),
  limits = c("No human trials or task variants borrowed", "No independent psychometric qualification",
             "IAT QC adapter is benchmark-only", "Synthetic replication bypasses a single-participant package diagnostics crash; never apply this workaround to live data",
             "BIAT fixture establishes denominator arithmetic, not a BIAT scorer"))
jsonlite::write_json(output, "docs/methods/reuse/implicit-reference-results.json",
                     pretty = TRUE, auto_unbox = TRUE, digits = 16)
cat(length(checks), "reference checks passed; upstream exclusions still require explicit QC.\n")
