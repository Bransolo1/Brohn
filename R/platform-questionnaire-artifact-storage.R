# Saved questionnaire previews are presentation data only. Scientific readers
# and full exports explicitly hydrate the verified complete analysis.
brohn_questionnaire_is_artifact <- function(analysis) identical(analysis$schema, "brohn-questionnaire-report-preview/1.0")
brohn_questionnaire_report_artifact <- function(report) {
  brohn_require(brohn_questionnaire_is_artifact(report$analysis), "Choose a saved questionnaire report with complete evidence files.")
  found <- Filter(function(a) identical(a$kind, "questionnaire-analysis"), report$analysis$artifacts)
  brohn_require(length(found) == 1L, "This questionnaire report has no unique complete analysis artifact.")
  found[[1L]]
}
brohn_complete_questionnaire_report <- function(store, report) {
  if (!brohn_questionnaire_is_artifact(report$analysis)) return(report)
  reference <- brohn_questionnaire_report_artifact(report)
  brohn_require(brohn_text(reference$hash, 64), "This report does not reference a published questionnaire evidence object.")
  path <- brohn_object_path(store, reference$hash, verify = TRUE)
  expected <- brohn_questionnaire_artifact_source(report)
  full <- brohn_read_questionnaire_artifact(path, reference, expected_source = expected)
  brohn_validate_questionnaire_preview(report$analysis, full, expected)
  report$analysis <- full
  report
}
brohn_questionnaire_source_reference <- function(store, report) {
  if (!brohn_questionnaire_is_artifact(report$analysis)) return(NULL)
  reference <- brohn_questionnaire_report_artifact(report)
  # Keep the worker manifest compact. Reconstruction happens in its consumer,
  # never by copying a large analysis back into a 16 MiB input envelope.
  list(path = brohn_object_path(store, reference$hash, verify = TRUE), reference = reference,
    source = brohn_questionnaire_artifact_source(report))
}
brohn_complete_questionnaire_source <- function(source) {
  if (!identical(source$status, "available") || !brohn_questionnaire_is_artifact(source$body$analysis)) return(source$body)
  evidence <- source$questionnaire_evidence
  brohn_require(is.list(evidence) && brohn_text(evidence$path, 4096), "Load complete questionnaire evidence before scientific synthesis; previews are not source observations.")
  expected <- brohn_questionnaire_artifact_source(source$body)
  brohn_require(identical(brohn_hash(evidence$source), brohn_hash(expected)) &&
    identical(brohn_hash(evidence$reference), brohn_hash(brohn_questionnaire_report_artifact(source$body))),
    "Questionnaire evidence differs from the selected report's frozen source binding.")
  body <- source$body
  full <- brohn_read_questionnaire_artifact(evidence$path, evidence$reference, expected_source = expected)
  brohn_validate_questionnaire_preview(body$analysis, full, expected)
  body$analysis <- full
  body
}
brohn_export_complete_questionnaire_report <- function(store, report, path) {
  packed <- brohn_questionnaire_is_artifact(report$analysis)
  if (!packed) {
    writeLines(enc2utf8(brohn_json(report, TRUE)), path, useBytes = TRUE)
    return(invisible(path))
  }
  reference <- if (packed) brohn_questionnaire_report_artifact(report) else NULL
  result <- brohn_complete_questionnaire_report(store, report)
  if (packed) result$export <- list(schema = "brohn-complete-questionnaire-export/1.0",
    representation = "complete_analysis_reconstructed_from_verified_artifact",
    saved_report_hash = brohn_hash(report), artifact = reference,
    analysis_sha256 = brohn_hash(result$analysis))
  # This is an explicit complete data download, not a catalog/worker envelope.
  # Artifact bounds and typed verification have already been enforced by reader.
  writeBin(charToRaw(enc2utf8(brohn_json(result))), path)
  invisible(path)
}
brohn_verify_questionnaire_worker_report <- function(store, report, scratch) {
  brohn_require(brohn_questionnaire_is_artifact(report$analysis), "Questionnaire evidence requires its complete verified report preview schema.")
  reference <- brohn_questionnaire_report_artifact(report)
  path <- brohn_checked_artifact_path(store, reference$path, scratch)
  full <- brohn_read_questionnaire_artifact(path, reference,
    expected_source = brohn_questionnaire_artifact_source(report))
  brohn_validate_questionnaire_preview(report$analysis, full, brohn_questionnaire_artifact_source(report))
  brohn_require(identical(brohn_hash(full), report$analysis$questionnaire_artifact$analysis_sha256),
    "The complete questionnaire analysis differs from its report preview identity.")
  invisible(TRUE)
}
