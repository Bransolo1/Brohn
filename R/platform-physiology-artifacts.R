brohn_validate_physiology_artifact_receipt <- function(analysis) {
  items <- Filter(function(a) a$kind %in% c("physiology-series", "physiology-events"), analysis$artifacts)
  if (!length(items)) return(invisible(TRUE))
  receipt <- analysis$artifact_verification
  brohn_require(identical(receipt$schema, "brohn-physiology-artifact-receipt/1.0") && identical(receipt$status, "verified") &&
    brohn_array(receipt$artifacts) && length(receipt$artifacts) == length(items), "Complete physiology artifacts need their typed verification receipt.")
  for (item in items) {
    matched <- Filter(function(a) identical(a$kind, item$kind), receipt$artifacts)
    brohn_require(length(matched) == 1L && isTRUE(matched[[1]]$verified), "A processed artifact has no unique verification receipt.")
    for (field in c("sha256", "bytes", "schema", "tables", "rows", "provenance_sha256"))
      brohn_require(identical(brohn_hash(matched[[1]][[field]]), brohn_hash(item[[field]])), "Processed artifact metadata differs from its verified typed stream.")
  }
  invisible(TRUE)
}
brohn_verify_physiology_artifacts <- function(result, scratch, modality) {
  if (!length(result$artifacts)) return(result)
  brohn_require(brohn_array(result$artifacts) && length(result$artifacts) <= 2L &&
    all(vapply(result$artifacts, function(a) a$kind %in% c("physiology-series", "physiology-events"), logical(1))), "Unexpected physiology artifact manifest.")
  directory <- normalizePath(file.path(scratch, "artifacts"), winslash = "/", mustWork = TRUE)
  manifest <- file.path(scratch, "processed-artifacts.json"); output <- file.path(scratch, "processed-artifact-verification.json")
  brohn_write_json_file(result$artifacts, manifest, maximum = 1024^2)
  checked <- processx::run(brohn_python_profile(modality), c("scripts/workers/physiology_artifacts.py", "--verify-manifest", manifest,
    "--directory", directory, "--output", output), timeout = 10*60, error_on_status = FALSE, echo = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)
  brohn_require(file.exists(output), paste("Complete processed output verification failed.", substr(checked$stderr, 1, 1000)))
  receipt <- brohn_read_json_file(output, maximum = 1024^2)
  brohn_require(checked$status == 0 && identical(receipt$status, "verified"), paste("Complete processed output needs attention:", brohn_default(receipt$error$message, "typed stream verification failed")))
  result$artifact_verification <- receipt
  brohn_validate_physiology_artifact_receipt(result)
  result
}
