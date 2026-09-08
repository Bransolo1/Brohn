source("R/platform-load.R", encoding = "UTF-8"); brohn_load()
local({
  checks <- 0L
  check <- function(name, ok) {if (!isTRUE(ok)) stop("FAILED: ", name); checks <<- checks+1L}
  store <- brohn_open_store(tempfile("brohn-assignment-ui-")); on.exit(brohn_close_store(store), add = TRUE)
  brohn_initialise_library(store)
  legacy <- brohn_create_study(store, "Original legacy questionnaire", "survey")
  design <- legacy$body
  q <- brohn_question("Choose an original answer", "single_choice", "before", "legacy-question")
  q$option_assignment <- NULL; q$randomize_options <- TRUE
  second <- q; second$id <- "fixed-question"; second$randomize_options <- FALSE
  design$questions <- list(q, second); legacy <- brohn_save_study(store, design, legacy$revision)
  other <- brohn_create_study(store, "Original other questionnaire", "survey")
  html <- as.character(brohn_questions_ui(legacy$body))
  check("legacy shared order is visible with an explicit draft action", grepl("same shuffled option order for every participant", html, fixed = TRUE) && grepl("Use participant-specific order", html, fixed = TRUE))
  actual_server <- brohn_server; formals(actual_server) <- formals(brohn_server)[c("input", "output", "session")]
  environment(actual_server) <- list2env(list(store_root = store$root), parent = environment(brohn_server))
  shiny::testServer(actual_server, {
    state$page <- "study"; state$stage <- "Questions"; current$study <- legacy; state$study_id <- legacy$id
    command <- list(study_id = legacy$id, question_id = q$id, question_hash = brohn_hash(q))
    session$setInputs(study_form_identity = paste(legacy$id, "Questions", sep = ":"), save_study = 1L)
    check("ordinary capture preserves legacy randomized questions", is.null(current$study$body$questions[[1]]$option_assignment) && current$study$revision == legacy$revision)
    state$page <- "datasets"
    session$setInputs(question_assignment_upgrade = command)
    check("off-page assignment actions cannot edit a draft", !is.null(state$error) && current$study$revision == legacy$revision)
    state$page <- "study"
    wrong <- command; wrong$study_id <- other$id
    session$setInputs(question_assignment_upgrade = wrong)
    check("another study cannot inherit a delayed action", !is.null(state$error) && current$study$revision == legacy$revision)
    stale <- command; stale$question_hash <- brohn_hash("old question")
    session$setInputs(question_assignment_upgrade = stale)
    check("stale question review cannot upgrade current content", grepl("question changed", state$error, fixed = TRUE) && current$study$revision == legacy$revision)
    session$setInputs(question_assignment_upgrade = command)
    check("explicit action saves one selected question revision", is.null(state$error) && current$study$revision == legacy$revision+1L && identical(current$study$body$questions[[1]]$option_assignment, "participant-sha256/1.0"))
    check("unselected fixed question and typed options remain intact", identical(brohn_hash(current$study$body$questions[[2]]), brohn_hash(second)) && identical(brohn_hash(current$study$body$questions[[1]]$options), brohn_hash(q$options)))
    revision <- current$study$revision
    session$setInputs(question_assignment_upgrade = command)
    check("replayed old action cannot create another edit", current$study$revision == revision && !is.null(state$error))
    session$setInputs(q_random_2 = TRUE, save_study = 2L)
    check("newly enabled randomization explicitly chooses participant assignment", is.null(state$error) && identical(current$study$body$questions[[2]]$option_assignment, "participant-sha256/1.0") && current$study$body$questions[[2]]$randomize_options)
    saved <- brohn_study(store, legacy$id)
    check("reopening retains saved assignment choices", identical(saved$body, current$study$body))
    html <- as.character(brohn_questions_ui(saved$body))
    check("updated draft explains resume and nonbalanced assignment", !grepl("same shuffled option order for every participant", html, fixed = TRUE) && grepl("Resuming keeps that order", html, fixed = TRUE) && grepl("equal allocation across orders is not guaranteed", html, fixed = TRUE))
    current$study <- brohn_archive_study(store, current$study$id, TRUE, current$study$revision)
    frozen <- current$study$revision
    command$question_hash <- brohn_hash(current$study$body$questions[[1]])
    session$setInputs(question_assignment_upgrade = command)
    check("archived draft cannot change assignment", current$study$revision == frozen && grepl("Restore", state$error, fixed = TRUE))
  })
  cat(sprintf("PASS: %d actual Shiny option-assignment checks\n", checks))
})
