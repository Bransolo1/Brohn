# Literal inactive worker registration. No public/default dispatch is changed.
.brohn_vra_worker_paths <- function() c(
  "scripts/variant-analysis-worker.R",
  "R/platform-core.R",
  "R/platform-question-materials.R",
  "R/platform-welcome.R",
  "R/platform-question-flow.R",
  "R/platform-analysis-plan.R",
  "R/platform-store.R",
  "R/platform-publication.R",
  "R/platform-methods.R",
  "R/platform-delivery.R",
  "R/platform-runner-assets.R",
  "R/platform-analysis.R",
  "R/platform-jobs.R",
  "R/platform-task-delivery.R",
  "R/platform-sciat-window-candidate.R",
  "R/platform-sciat-window.R",
  "R/platform-sciat-window-delivery.R",
  "R/platform-sciat-window-score.R",
  "R/platform-gnat.R",
  "R/platform-capture.R",
  "R/platform-camera-analysis.R",
  "R/platform-participant-equipment.R",
  "R/platform-scales.R",
  "R/platform-question-sections.R",
  "R/platform-question-revision.R",
  "R/platform-question-revision-delivery.R",
  "R/platform-run-evidence.R",
  "R/platform-questionnaire-artifacts.R",
  "R/platform-questionnaire-artifact-storage.R",
  "R/platform-maxdiff.R",
  "R/platform-maxdiff-platform.R",
  "R/platform-method-evidence.R",
  "R/platform-method-evidence-binding.R",
  "R/platform-method-evidence-ancestry.R",
  "R/platform-method-evidence-identity.R",
  "R/platform-method-evidence-domain.R",
  "R/platform-variant-design.R",
  "R/platform-task-protocol-history.R",
  "R/platform-method-evidence-protocol-history.R",
  "R/platform-variant-protocol-history.R",
  "R/platform-evidence-run-source.R",
  "R/platform-variant-run-source.R",
  "R/platform-variant-analysis-index.R",
  "R/platform-variant-run-reader.R",
  "R/platform-variant-analysis-values.R",
  "R/platform-variant-analysis.R",
  "R/platform-variant-analysis-identity.R",
  "scripts/workers/publication.py",
  "src/publication_guard.c",
  "R/platform-variant-run-transport.R",
  "R/platform-variant-analysis-queue.R",
  "R/platform-variant-analysis-claim.R",
  "R/platform-variant-analysis-publication-schema.R",
  "R/platform-variant-analysis-publication.R",
  "R/platform-variant-analysis-process.R"
)
.brohn_vra_worker_identity <- function() {
  paths <- .brohn_vra_worker_paths()
  brohn_require(all(file.exists(paths)) && !any(file.info(paths)$isdir), "The complete saved-variant worker closure is unavailable.")
  setNames(lapply(paths, function(path) digest::digest(file = path, algo = "sha256")), paths)
}
.brohn_vra_worker_output <- function(result, expected) {
  .brohn_ph_domain(result$code_identity)
  brohn_fields(result$code_identity, .brohn_vra_worker_paths(), label = "Variant worker implementation")
  brohn_require(identical(result$schema, "brohn-analysis-output/1.0") &&
    identical(result$analysis_profile, .brohn_vra_profile) && is.list(result$report) &&
    identical(result$report$analysis_profile, .brohn_vra_profile) &&
    .brohn_ph_equal(result$code_identity, expected) && identical(expected, .brohn_vra_worker_identity()),
    "The saved-variant result differs from its exact registered worker implementation.")
  invisible(TRUE)
}
