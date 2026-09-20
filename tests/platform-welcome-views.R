# Source-bound authoring state, recovery and safe read-only participant preview.
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = TRUE)
local({
  checks <- 0L; check <- function(ok, label) {if (!isTRUE(ok)) stop(label, call. = FALSE); checks <<- checks+1L; cat("PASS", label, "\n")}
  root <- tempfile("brohn-welcome-ui-"); dir.create(root)
  store <- brohn_open_store(file.path(root, "workspace")); brohn_initialise_library(store)
  on.exit(brohn_close_store(store), add = TRUE)
  study <- brohn_create_study(store, "Original welcome authoring", "survey")
  d <- study$body; d$questions <- list(brohn_question("Original question", "text", "end")); study <- brohn_save_study(store, d, study$revision)
  source <- file.path(root, "first.png"); png::writePNG(array(c(1,0,0,1,0,1,0,1,0,0,1,1), c(2,2,3)), source)
  second <- file.path(root, "second.png"); file.copy(source, second)
  corrupt <- file.path(root, "corrupt.png"); writeBin(charToRaw("original non-image fixture"), corrupt)
  server <- function(input, output, session) {
    state <- shiny::reactiveValues(page = "study", stage = "Plan", study_id = study$id, refresh = 0L, error = NULL)
    current <- new.env(); current$study <- study
    update <- function(d) {current$study <- brohn_save_study(store, d, current$study$revision); state$refresh <- state$refresh+1L}
    capture <- function() {d <- brohn_capture_welcome(input, current$study$body); if (!identical(brohn_hash(d), brohn_hash(current$study$body))) update(d)}
    attempt <- function(fn, ...) {state$error <- NULL; tryCatch(fn(), error = function(e) {state$error <- conditionMessage(e); NULL})}
    welcome <- brohn_install_welcome_ui(input, output, session, store, state, current, attempt, capture, update)
  }
  shiny::testServer(server, {
    command <- list(study_id = study$id)
    session$setInputs(study_form_identity = paste(study$id,"Plan",sep=":"), welcome_enabled = TRUE,
      welcome_title = "Original heading", welcome_text = "Original saved text", welcome_image_alt = "")
    session$setInputs(welcome_image_open = command)
    if(!is.null(state$error))stop(state$error)
    check(!is.null(welcome$upload()) && current$study$body$welcome$title == "Original heading", "Image action first captures the currently edited welcome fields")
    session$setInputs(welcome_image_save = 1L)
    check(!is.null(state$error) && grepl("Choose a PNG", output$welcome_upload_error$html), "Missing image gives an actionable error inside the open dialog")
    session$setInputs(welcome_image_file = list(datapath=source,name="first.png"), welcome_upload_alt="")
    session$setInputs(welcome_image_save = 2L)
    check(!is.null(state$error) && is.null(current$study$body$welcome$asset) && grepl("Describe", output$welcome_upload_error$html), "Image description failure preserves the draft and remains recoverable in place")
    session$setInputs(welcome_upload_alt = "Four original coloured squares", welcome_image_save = 3L)
    if(!is.null(state$error))stop(state$error)
    first_hash <- current$study$body$welcome$asset$hash
    check(is.null(welcome$upload()) && nchar(first_hash)==64, "Successful source-bound image upload saves the immutable asset and closes its action")
    # Simulate new DOM input binding after update_study redraw.
    session$setInputs(welcome_image_alt = current$study$body$welcome$image_alt)
    session$setInputs(welcome_preview = command)
    check(!is.null(welcome$preview()) && identical(welcome$preview()$hash, brohn_hash(current$study$body)), "Saved preview pins the source after pending authoring changes")
    session$setInputs(welcome_preview_close = 1L)
    check(is.null(welcome$preview()), "Closing the saved welcome preview clears its source state")
    session$setInputs(welcome_image_open = command, welcome_image_save = 4L)
    check(!is.null(state$error) && grepl("this dialog", output$welcome_upload_error$html), "A stale uploaded file from an earlier dialog cannot silently attach again")
    session$setInputs(welcome_image_file = list(datapath=corrupt,name="corrupt.png"), welcome_image_save = 5L)
    check(!is.null(state$error) && identical(current$study$body$welcome$asset$hash, first_hash), "Invalid replacement bytes retain the existing welcome image")
    d <- current$study$body; d$description <- "Updated by another saved editor"; newer <- brohn_save_study(store,d,current$study$revision)
    session$setInputs(welcome_image_file=list(datapath=second,name="second.png"), welcome_image_save=6L)
    check(!is.null(state$error) && grepl("changed", output$welcome_upload_error$html) && identical(brohn_study(store,study$id)$body$description,newer$body$description), "Concurrent draft change rejects stale image attachment without overwriting saved work")
    current$study <- newer; session$setInputs(welcome_image_open = command)
    state$page <- "home";session$flushReact()
    check(is.null(welcome$upload()), "Navigating away discards the old study image-action context")
    state$page <- "study";session$flushReact()
    session$setInputs(welcome_image_open=list(study_id="another-study"))
    check(!is.null(state$error) && is.null(welcome$upload()), "Delayed authoring commands cannot target a different study")
    session$setInputs(welcome_image_remove=command)
    check(is.null(current$study$body$welcome$asset) && identical(current$study$body$welcome$image_alt,""), "Removing welcome artwork preserves the authored text and clears only the current draft image")
  })
  check(!DBI::dbExistsTable(store$con,"delivery_runs"), "Authoring component creates no participant-delivery tables or sessions")
  cat("PASS",checks,"welcome authoring component checks\n")
})
