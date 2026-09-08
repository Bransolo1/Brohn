source("R/platform-load.R", encoding = "UTF-8"); brohn_load()
local({
  checks <- 0L
  check <- function(label, ok) {if (!isTRUE(ok)) stop("FAIL: ", label); checks <<- checks+1L}
  store <- brohn_open_store(tempfile("brohn-revision-ui-")); on.exit(brohn_close_store(store), add = TRUE)
  brohn_initialise_library(store); study <- brohn_create_study(store, "Original answer review UI", "survey")
  design <- study$body; design$questions <- list(brohn_question("Original review item", "rating", "end", "q-original-review"))
  study <- brohn_save_study(store, design, study$revision)
  other <- brohn_create_study(store, "Original other study", "survey")
  actual <- brohn_server; formals(actual) <- formals(actual)[c("input", "output", "session")]
  environment(actual) <- list2env(list(store_root = store$root), parent = environment(brohn_server))
  shiny::testServer(actual, {
    state$page <- "study"; state$stage <- "Questions"; state$study_id <- study$id; current$study <- study
    command <- list(study_id = study$id, design_hash = brohn_hash(study$body), enabled = TRUE)
    session$setInputs(study_form_identity = paste(study$id, "Questions", sep = ":"), save_study = 1L)
    check("ordinary autosave never opts an older draft into navigation", is.null(current$study$body$questionnaire_navigation) && current$study$revision == study$revision)
    state$page <- "datasets"; session$setInputs(questionnaire_navigation_change = command)
    check("off-page request cannot change draft policy", !is.null(state$error) && current$study$revision == study$revision)
    state$page <- "study"; state$stage <- "Plan"; session$setInputs(questionnaire_navigation_change = command)
    check("other stage cannot accept delayed questionnaire action", !is.null(state$error) && current$study$revision == study$revision)
    state$stage <- "Questions"; bad <- command; bad$study_id <- other$id; session$setInputs(questionnaire_navigation_change = bad)
    check("another study cannot inherit this action", !is.null(state$error) && current$study$revision == study$revision)
    bad <- command; bad$design_hash <- brohn_hash("old-source"); session$setInputs(questionnaire_navigation_change = bad)
    check("stale reviewed design cannot change navigation", !is.null(state$error) && current$study$revision == study$revision)
    bad <- command; bad$enabled <- "true"; session$setInputs(questionnaire_navigation_change = bad)
    check("policy choice must be typed boolean", !is.null(state$error) && current$study$revision == study$revision)
    session$setInputs(questionnaire_navigation_change = command)
    check("explicit opt-in saves one exact policy revision", is.null(state$error) && current$study$revision == study$revision+1L &&
      identical(brohn_json(current$study$body$questionnaire_navigation), brohn_json(brohn_questionnaire_navigation())))
    frozen <- current$study$revision; session$setInputs(questionnaire_navigation_change = command)
    check("late repeated action cannot save again", !is.null(state$error) && current$study$revision == frozen)
    html <- htmltools::renderTags(brohn_questions_ui(current$study$body))$html
    check("enabled UI explains sealing and final-answer evidence", grepl("Use forward-only", html, fixed = TRUE) && grepl("Reports score the final answers", html, fixed = TRUE))
    command$enabled <- FALSE; command$design_hash <- brohn_hash(current$study$body)
    session$setInputs(questionnaire_navigation_change = command)
    check("explicit opt-out removes the extension without changing questions", is.null(current$study$body$questionnaire_navigation) &&
      identical(brohn_hash(current$study$body$questions), brohn_hash(study$body$questions)))
    check("reopening retains saved policy choice", identical(brohn_hash(brohn_study(store, study$id)$body), brohn_hash(current$study$body)))
    current$study <- brohn_archive_study(store, study$id, TRUE, current$study$revision); frozen <- current$study$revision
    command$enabled <- TRUE; command$design_hash <- brohn_hash(current$study$body)
    session$setInputs(questionnaire_navigation_change = command)
    check("archived study cannot change navigation", !is.null(state$error) && current$study$revision == frozen)
  })
  # An unsectioned revision question must not partially match the longer metadata
  # key as 'questionnaire' in the assigned-protocol renderer.
  d <- study$body; d$questionnaire_navigation <- brohn_questionnaire_navigation(); p <- brohn_compile(d)
  snapshot <- list(run = list(id = "original-run", participant_alias = "001", origin = "sample", allocation_index = 1,
    completion_status = "in_progress", transfer_status = "pending"), protocol = p, hash = brohn_hash(p))
  html <- htmltools::renderTags(brohn_run_protocol_ui(snapshot))$html
  check("assigned review renders unsectioned revision steps without R partial matching", grepl("questionnaire review", html, fixed = TRUE))
  check("revision display does not change stored protocol evidence", identical(brohn_hash(p), snapshot$hash))
  cat(sprintf("PASS: %d actual Shiny answer-review and assigned-protocol checks\n", checks))
})
