# Loaded implementation identity is distinct from every historical producer's
# retained scientific identity. A new view never rewrites an old producer.
.brohn_cdd_files <- c(
  "R/platform-cardiac-display.R", "R/platform-cardiac-display-jobs.R",
  "R/platform-cardiac-display-identity.R", "R/platform-cardiac-display-validation.R",
  "R/platform-cardiac-display-sources.R", "R/platform-cardiac-display-chapters.R",
  "R/platform-core.R", "R/platform-store.R", "R/platform-catalog.R", "R/platform-publication.R",
  "R/platform-jobs.R", "R/platform-vision.R", "R/platform-hosted-profile.R", "R/platform-report-package-authority.R",
  "R/platform-report-package-sources.R", "R/platform-task-display.R",
  "R/platform-eda-display.R", "R/platform-eda-display-sources.R", "R/platform-eda-continuous-review.R",
  "R/platform-signal.R", "R/platform-signal-values.R", "R/platform-cardiac-review.R",
  "R/platform-stream-curation.R", "R/platform-interchange.R", "R/platform-acquisition.R",
  "R/platform-acquisition-quality.R", "R/platform-ingestion.R", "R/platform-questionnaire-explorer.R",
  "R/platform-clock-map.R", "R/platform-clock-authority.R",
  "scripts/analysis-worker.R", "scripts/workers/cardiac_display.py",
  "scripts/workers/cardiac_display_core.py", "scripts/workers/cardiac_display_geometry.py",
  "scripts/workers/cardiac_display_lineage.py", "scripts/workers/cardiac_display_policy.py",
  "scripts/workers/cardiac_values.py", "scripts/workers/physiology_artifacts.py",
  "scripts/readiness/report-package-runtime.json")
.brohn_cdd_loaded <- stats::setNames(lapply(.brohn_cdd_files,function(p)
  if(file.exists(p))digest::digest(file=p,algo="sha256")else NULL),.brohn_cdd_files)
.brohn_cdd_runtime_profile <- if(file.exists("scripts/readiness/report-package-runtime.json")&&
  file.info("scripts/readiness/report-package-runtime.json")$size<=8192)
    jsonlite::fromJSON("scripts/readiness/report-package-runtime.json",simplifyVector=FALSE)else NULL
.brohn_cdd_runtime <- list(R=as.character(getRversion()),jsonlite=as.character(utils::packageVersion("jsonlite")),
  digest=as.character(utils::packageVersion("digest")),Python=.brohn_cdd_runtime_profile$runtime$Python)
brohn_cardiac_display_implementation <- function() {
  brohn_require(!any(vapply(.brohn_cdd_loaded,is.null,logical(1)))&&
    identical(.brohn_cdd_runtime_profile$schema,"brohn-report-package-runtime-profile/0.1")&&
    identical(.brohn_cdd_runtime$Python$implementation,"CPython")&&brohn_text(.brohn_cdd_runtime$Python$version,64),
    "Cardiac display code and runtime identity require a complete registered installation.")
  list(schema="brohn-cardiac-display-implementation/0.1",profile=.brohn_cdd_profile,
    sources=.brohn_cdd_loaded,runtime=.brohn_cdd_runtime)
}
brohn_cardiac_display_implementation_ref <- function().brohn_td_implementation_ref(brohn_cardiac_display_implementation())
.brohn_cdd_check_code <- function(implementation) {
  brohn_require(.brohn_rpk_same(implementation,brohn_cardiac_display_implementation()),
    "Cardiac display code changed. Explicitly prepare a new view with the current implementation.")
  for(path in names(implementation$sources))brohn_require(file.exists(path)&&
    identical(digest::digest(file=path,algo="sha256"),implementation$sources[[path]]),
    "Cardiac display code changed on disk after loading.")
  invisible(TRUE)
}
