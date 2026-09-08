# Recalculate from the embedded original CSV, ignoring saved analysis tables.
for (module in c("study", "comparison", "presentation", "records", "json", "storage", "assets", "aois", "analysis", "gaze-import", "import-report"))
  source(paste0("R/", module, ".R"))
args <- commandArgs(trailingOnly = TRUE)
record_assert(length(args) == 1L, "Usage: Rscript examples/reproduce-import.R report.json")
report <- read_prepared_report(args[[1]])
cat("Recalculated from embedded CSV; origin unverified and method unqualified.\n")
print(report$analysis$summary)
