# From repository root: Rscript examples/reproduce-sample.R path/to/sample-analysis.json
# Uses the exported inputs, ignoring stored output tables. No device data is implied.
for (path in c("study", "comparison", "presentation", "records", "json", "assets", "aois", "analysis"))
  source(paste0("R/", path, ".R"))
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L, file.exists(args[[1]]), file.info(args[[1]])$size <= 16 * 1024^2)
text <- paste(readLines(args[[1]], encoding = "UTF-8", warn = FALSE), collapse = "\n")
record_assert(jsonlite::validate(text), "Choose a JSON report, not a file or URL reference.")
report <- jsonlite::fromJSON(text, simplifyVector = FALSE)
stopifnot(identical(report$schema_version, "sample-report/0.1.0"),
          identical(report$origin, "synthetic_demonstration"))
study <- .study_from_wire(report$study)
intervals <- jsonlite::fromJSON(text)$prepared_intervals
result <- analyze_gaze_intervals(study, intervals)
cat("Recalculated from exported fictional inputs; method remains unqualified.\n")
print(result$summary)
