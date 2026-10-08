# Fixed current-reference metadata only. No store authority or scientific cache.
.brohn_me_host_reference <- function() list(
  path = "registry/method-evidence-0.2.json",
  registry_id = "brohn-consumer-method-evidence", revision = "0.2.0-screened",
  sha256 = "cd63ffb8eaa1a2c73b08dddd93573c5fedeb266f6cad8aadc22c5759b22dd9b0")

brohn_method_evidence_host_load <- function(app_root = getwd()) {
  expected <- .brohn_me_host_reference()
  state <- new.env(parent = emptyenv())
  state$status <- "reference_loading_failed"
  state$expected_ref <- expected
  state$registry <- NULL
  state$ref <- NULL
  state$error_code <- "registry_unavailable"
  state$diagnostic <- NULL
  tryCatch({
    .brohn_me_need(.brohn_me_text(app_root, 4096L) && dir.exists(app_root), "Application checkout is unavailable.")
    path <- file.path(app_root, expected$path)
    if (!file.exists(path)) {
      state$error_code <- "registry_missing"
    } else {
      state$error_code <- "registry_rejected"
      result <- brohn_method_evidence_read(path, expected$sha256)
      .brohn_me_need(identical(result$ref$registry_id, expected$registry_id) &&
        identical(result$ref$revision, expected$revision), "Packaged registry identity differs from the pinned reference.")
      state$registry <- result$registry
      state$ref <- result$ref
      state$status <- "ready"
      state$error_code <- NULL
    }
  }, error = function(e) {state$diagnostic <- conditionMessage(e)})
  lockEnvironment(state, bindings = TRUE)
  state
}

brohn_method_evidence_task_style <- function() shiny::tags$style(
  ".brohn-method-evidence{min-width:0;overflow-wrap:anywhere}.brohn-method-evidence a{overflow-wrap:anywhere}.brohn-method-evidence-claim{margin-top:1rem}.brohn-method-evidence summary{cursor:pointer}")

brohn_method_evidence_task_ui <- function(method_ref, original_source = NULL, state = NULL) {
  if (is.null(state)) state <- get0(".brohn_method_evidence_app", envir = environment(brohn_method_evidence_task_ui), inherits = TRUE)
  ready <- is.environment(state) && environmentIsLocked(state) &&
    identical(state$status, "ready") && identical(state$expected_ref, .brohn_me_host_reference())
  if (!ready) return(shiny::div(class = "brohn-method-evidence brohn-method-evidence-unavailable",
    `data-evidence-status` = "reference_loading_failed",
    shiny::p(role = "status", "Academic references could not be loaded. The saved procedure remains available."),
    shiny::tags$details(shiny::tags$summary("Reference loading and original procedure"),
      shiny::p("The packaged evidence registry is missing or could not be verified. This is a reference-loading problem, not a statement that this procedure has no evidence."),
      shiny::p("Current guidance has not been loaded; no evidence snapshot was added to this study."),
      .brohn_me_source_link(original_source, "Open the procedure's original reference"),
      shiny::tags$code(method_ref))))
  shiny::div(`data-evidence-status` = "reference_loaded", `data-evidence-method` = method_ref,
    brohn_method_evidence_ui(state$registry, method_ref, original_source))
}
