source("R/platform-load.R", encoding = "UTF-8"); brohn_load()
local({
  count <- 0L
  check <- function(name, ok) {if (!isTRUE(ok)) stop("FAILED: ", name); count <<- count+1L}
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  store <- brohn_open_store(tempfile("brohn-run-review-")); on.exit(brohn_close_store(store), add = TRUE)
  brohn_initialise_library(store)
  study <- brohn_create_study(store, "Original assigned protocol review", "survey")
  design <- study$body; design$questions <- lapply(1:45, function(i) brohn_question(paste("Original question", i), "single_choice", "before", paste0("original-question-", i)))
  design$questions[[1]]$options <- lapply(seq_along(list(0, "0", FALSE, 1, "1", TRUE)), function(i)
    list(id = paste0("typed-", i), label = paste("Original answer", i), value = list(0, "0", FALSE, 1, "1", TRUE)[[i]]))
  design$questions[[1]]$randomize_options <- TRUE
  study <- brohn_save_study(store, design, study$revision)
  release <- brohn_publish(store, study$id, origin = "sample", quota = 3)
  started <- .brohn_delivery_start(store, release$token, list(consented = TRUE, client_id = "original-review-client", operation_id = "original-review-start"))
  other <- brohn_create_study(store, "Original unrelated study", "survey")
  snapshot <- brohn_run_protocol(store, started$run_id, study$id, study$project_id)
  check("saved assignment equals actual start protocol", identical(brohn_hash(snapshot$protocol), brohn_hash(started$protocol)))
  check("cross-study and cross-project reads reject", rejects(brohn_run_protocol(store, started$run_id, other$id, study$project_id)) && rejects(brohn_run_protocol(store, started$run_id, study$id, "other-project")))
  design$title <- "Edited after participant assignment"; study <- brohn_save_study(store, design, study$revision)
  check("historical protocol is independent of current draft", identical(brohn_run_protocol(store, started$run_id, study$id, study$project_id)$json, snapshot$json))
  file <- tempfile(fileext = ".json"); brohn_export_run_protocol(snapshot, file)
  bytes <- readBin(file, "raw", n = file.info(file)$size)
  check("complete export preserves original JSON bytes and hash", identical(bytes, charToRaw(snapshot$json)) && identical(digest::digest(bytes, algo = "sha256", serialize = FALSE), snapshot$hash))
  check("export excludes participant credentials and deployment token", !grepl(started$access_token, rawToChar(bytes), fixed = TRUE) && !grepl(release$token, rawToChar(bytes), fixed = TRUE) && !grepl("access_token", rawToChar(bytes), fixed = TRUE))
  tampered <- snapshot; tampered$json <- paste0(snapshot$json, " ")
  check("export refuses changed source bytes", rejects(brohn_export_run_protocol(tampered, tempfile(fileext = ".json"))))
  one <- as.character(brohn_run_protocol_ui(snapshot)); two <- as.character(brohn_run_protocol_ui(snapshot, 40))
  check("bounded pages retain access to every assigned step", grepl("Next assigned steps", one, fixed = TRUE) && !grepl("Original question 45", one, fixed = TRUE) && grepl("Original question 45", two, fixed = TRUE) && grepl("Previous assigned steps", two, fixed = TRUE))
  check("review distinguishes assigned from observed behavior", grepl("assignment alone does not establish what was viewed or completed", one, fixed = TRUE))
  check("typed zero and false remain readable alongside text codes", grepl("<code>0</code>", one, fixed = TRUE) && grepl("<code>false</code>", one, fixed = TRUE) && grepl("<code>\"0\"</code>", one, fixed = TRUE))
  server <- function(input, output, session) {
    current <- new.env(parent = emptyenv()); current$study <- study
    state <- shiny::reactiveValues(page = "study", stage = "Collect", error = NULL)
    attempt <- function(fn) {state$error <- NULL; tryCatch(fn(), error = function(e) {state$error <- conditionMessage(e); NULL})}
    api <- brohn_install_run_protocol_ui(input, output, session, store, current, state, attempt, function(fn) fn())
  }
  shiny::testServer(server, {
    command <- list(run_id = started$run_id, study_id = study$id)
    session$setInputs(view_run_protocol = command)
    check("current study can open its participant assignment", is.null(state$error))
    check("unbound protocol selection cannot download", rejects(api$selected()))
    session$setInputs(run_protocol_identity = paste(started$run_id, snapshot$hash, sep = ":"))
    check("bound selection reads the original protocol", identical(api$selected()$json, snapshot$json))
    stale <- list(run_id = started$run_id, hash = brohn_hash("different"), offset = 40)
    session$setInputs(run_protocol_page = stale)
    check("stale page command cannot switch protocol", !is.null(state$error) && identical(api$selected()$hash, snapshot$hash))
    session$setInputs(close_run_protocol = 1L)
    check("closing review invalidates its download selection", rejects(api$selected()))
    session$setInputs(view_run_protocol = command)
    state$page <- "datasets"
    check("leaving the study invalidates its protocol download", rejects(api$selected()))
    state$page <- "study"; current$study <- other
    session$setInputs(view_run_protocol = command)
    check("late session action cannot use another study", !is.null(state$error) && rejects(api$selected()))
  })
  cat(sprintf("PASS: %d stored protocol, byte-exact download and Shiny selection checks\n", count))
})
