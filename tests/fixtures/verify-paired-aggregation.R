# Verify retained worker outputs without launching jobs or rewriting reports.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = FALSE)
reference <- brohn_read_json_file(file.path(normalizePath(args[[1]], winslash = "/", mustWork = TRUE), "fixture.json"))
folder <- normalizePath(args[[2]], winslash = "/", mustWork = TRUE)
receipt <- brohn_read_json_file(file.path(folder, "acceptance.json"))
stopifnot(identical(receipt$schema, "brohn-paired-aggregation-worker-review/1.0"),
  identical(receipt$source_sha256, digest::digest(file = "R/platform-analysis.R", algo = "sha256")))
local({
  original_store <- brohn_open_store(reference$workspace)
  on.exit(brohn_close_store(original_store))
  store <- brohn_open_store(file.path(folder, "workspace"))
  on.exit(brohn_close_store(store), add = TRUE)
  checks <- list()
  for (kind in c("questionnaire", "gaze", "stress", "multimodal")) {
    ref <- reference$reports[[kind]]; check <- receipt$reviews[[kind]]
    stopifnot(!is.null(ref), !is.null(check), identical(ref$id, check$original_report))
    original <- brohn_get_entity(original_store, "report", ref$id)
    copied <- brohn_get_entity(store, "report", ref$id)
    result <- brohn_get_entity(store, "report", check$new_report)
    job <- brohn_get_job(store, check$job_id)
    stopifnot(identical(job$status, "succeeded"), identical(job$result$report_id, result$id),
      identical(brohn_hash(original$body), ref$hash), identical(brohn_hash(copied$body), ref$hash),
      identical(brohn_hash(result$body), check$new_report_hash),
      identical(brohn_json(result$body$analysis), brohn_json(original$body$analysis)),
      identical(brohn_json(result$body$provenance), brohn_json(original$body$provenance)),
      identical(result$body$origin, original$body$origin),
      identical(result$body$processing$code_hashes$`R/platform-analysis.R`, receipt$source_sha256))
    checks[[kind]] <- list(job_terminal = TRUE, report_hash_verified = TRUE,
      original_and_copy_unchanged = TRUE, complete_analysis_and_provenance_exact = TRUE,
      processing_source_hash_verified = TRUE, report_id = result$id)
  }
  brohn_write_json_file(list(schema = "brohn-paired-aggregation-retained-review/1.0",
    origin = "original_synthetic", source_sha256 = receipt$source_sha256,
    worker_receipt_sha256 = digest::digest(file = file.path(folder, "acceptance.json"), algo = "sha256"),
    reviews = checks), file.path(folder, "retained-output-verification.json"))
  cat("PASS four terminal worker reports, exact outputs, source fingerprints and original reports\n")
})
