source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = TRUE)
local({
  checks <- 0L
  check <- function(value, label) {if (!isTRUE(value)) stop(label, call. = FALSE); checks <<- checks+1L}
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  store <- brohn_open_store(tempfile("brohn-run-catalog-ui-")); on.exit(brohn_close_store(store), add = TRUE)
  brohn_initialise_library(store)
  study <- brohn_create_study(store, "Original session-page fixture", "survey")
  d <- study$body; d$questions <- list(brohn_question("Original fixture question", "rating", "end", "q-original-page"))
  study <- brohn_save_study(store, d, study$revision)
  release <- brohn_publish(store, study$id, "sample")
  start <- .brohn_delivery_start(store, release$token, list(consented=TRUE, client_id="original-page-client", operation_id="original-page-start"))
  row <- DBI::dbGetQuery(store$con, "SELECT * FROM delivery_runs WHERE id=?", params=list(start$run_id))
  # Original metadata fixtures share a valid frozen protocol, without pretending
  # to represent actual completed participant observations.
  for (i in 1:41) {
    copy <- row; copy$id <- sprintf("run-page-%03d", i); copy$client_id <- sprintf("page-client-%03d", i)
    copy$allocation_index <- i+1L
    copy$participant_alias <- sprintf("Original catalog person %03d", i)
    copy$created_at <- "2020-01-01T00:00:00Z"
    DBI::dbWriteTable(store$con, "delivery_runs", copy, append=TRUE)
  }
  other <- brohn_create_study(store, "Original different study", "survey")
  # Fail immediately if the UI regresses to the expensive full-protocol reader.
  old_runs <- brohn_runs; assign("brohn_runs", function(...) stop("Full protocol catalog read is forbidden in this view"), envir=.GlobalEnv)
  on.exit(assign("brohn_runs", old_runs, envir=.GlobalEnv), add=TRUE)
  command <- function(offset, direction=1L, parent=study$id) list(relation="study_runs", parent_id=parent, offset=offset, limit=40L, direction=direction)
  server <- function(input, output, session) {
    state <- shiny::reactiveValues(page="study", study_id=study$id, stage="Collect", related_offsets=list(), error=NULL)
    shiny::observeEvent(input$related_page, tryCatch(brohn_related_page_command(store,state,input$related_page), error=function(e) state$error<-conditionMessage(e)))
    output$sessions <- shiny::renderUI(brohn_sessions_ui(store, study$id, state))
  }
  shiny::testServer(server, {
    session$flushReact(); first <- output$sessions$html
    check(grepl("Showing 1 to 40 of 42 participant sessions", first, fixed=TRUE), "Collect shows exact count and bounded first page")
    check(grepl("Next participant sessions", first, fixed=TRUE) && !grepl("Original catalog person 041", first, fixed=TRUE), "Older sessions have a next-page route, without full protocol reads")
    check(grepl("View assigned protocol", first, fixed=TRUE) && grepl("Not requested", first, fixed=TRUE), "Metadata retains protocol review actions and camera configuration display")
    session$setInputs(related_page=command(0)); last <- output$sessions$html
    check(grepl("Showing 41 to 42 of 42", last, fixed=TRUE) && grepl("Original catalog person 041", last, fixed=TRUE), "Next opens oldest matching sessions")
    check(grepl("Previous participant sessions", last, fixed=TRUE) && !grepl("Next participant sessions", last, fixed=TRUE), "Last page has correct direction controls")
    session$setInputs(related_page=command(0, -1)); check(!is.null(state$error) && brohn_related_offset(state,"study_runs",study$id)==40, "Stale page cannot redirect current list")
    state$error <- NULL; state$stage <- "Review"
    session$setInputs(related_page=command(40,-1)); check(is.null(state$error) && brohn_related_offset(state,"study_runs",study$id)==0, "Review uses the same saved session pages")
    state$stage <- "Questions"; session$setInputs(related_page=command(0))
    check(!is.null(state$error) && brohn_related_offset(state,"study_runs",study$id)==0, "Hidden collection list cannot change on another stage")
    state$error <- NULL; state$stage <- "Collect"; session$setInputs(related_page=command(0,parent=other$id))
    check(!is.null(state$error), "Foreign study command is rejected before paging")
  })
  unknown <- list(id=start$run_id, camera_policy_summary=list(status="unavailable"))
  check(grepl("Camera setting unavailable", as.character(brohn_camera_session_ui(store,unknown)), fixed=TRUE), "Unknown camera projection does not claim no camera was requested")
  check(rejects(brohn_search_related(store,"study_runs",study$id,limit=0)), "Related wrapper preserves page-bound validation")
  cat(sprintf("PASS: %d participant-session page UI and guard checks\n",checks))
})
