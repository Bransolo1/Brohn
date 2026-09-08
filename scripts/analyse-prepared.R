# From the repository root: Rscript scripts/analyse-prepared.R study.json gaze.csv report.json
for (module in c("study", "comparison", "presentation", "records", "json", "storage", "assets", "aois", "analysis", "gaze-import", "import-report"))
  source(paste0("R/", module, ".R"))
args <- commandArgs(trailingOnly = TRUE)
record_assert(length(args) == 3L, "Usage: Rscript scripts/analyse-prepared.R study.json gaze.csv new-report.json")
report <- build_prepared_report(read_bundle(args[[1]]), args[[2]])
save_prepared_report(report, args[[3]])
cat("Saved an unqualified prepared-gaze report. Original CSV bytes are included.\n")
print(report$analysis$summary)
