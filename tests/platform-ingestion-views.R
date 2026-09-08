source("R/platform-load.R", encoding = "UTF-8"); brohn_load()
local({
  checks <- 0L
  check <- function(name, ok) {if (!isTRUE(ok)) stop("FAILED: ", name); checks <<- checks+1L}
  store <- brohn_open_store(tempfile("brohn-intake-ui-")); on.exit(brohn_close_store(store), add = TRUE); brohn_initialise_library(store)
  first <- brohn_create_study(store, "Original destination A"); second <- brohn_create_study(store, "Original destination B")
  upload <- tempfile(fileext = ".csv"); writeLines(c("time,temperature", "0,30", "1,31"), upload)
  upload_value <- data.frame(name = "original-fixture.csv", size = file.info(upload)$size, type = "text/csv", datapath = upload)
  actual_server <- brohn_server; formals(actual_server) <- formals(brohn_server)[c("input", "output", "session")]
  environment(actual_server) <- list2env(list(store_root = store$root), parent = environment(brohn_server))
  shiny::testServer(actual_server, {
    identity <- function() {
      html <- as.character(output$ingestion_upload_review$html)
      captured <- regmatches(html, regexec('id="ingestion_upload_review_identity"[^>]*value="([a-f0-9]{64})"', html))[[1]]
      if (length(captured) != 2L) stop("Expected the displayed upload review identity: ", html)
      captured[[2]]
    }
    state$page <- "study"; state$stage <- "Collect"; current$study <- first; state$study_id <- first$id
    session$setInputs(dataset_title = "Original source", dataset_modality = "temperature", dataset_origin = "sample", start_source_import = 0L)
    session$flushReact(); session$setInputs(dataset_upload = upload_value)
    check("completed transfer never assigns a destination automatically", !length(brohn_list_entities(store, "ingestion")) && file.exists(upload))
    old_identity <- identity()
    state$study_id <- second$id; current$study <- second; state$refresh <- state$refresh+1L; session$flushReact()
    session$setInputs(ingestion_upload_review_identity = old_identity, start_source_import = 1L)
    check("late upload action cannot use another study's displayed destination", !length(brohn_list_entities(store, "ingestion")) && grepl("destination changed", state$error, fixed = TRUE))
    shown <- identity()
    session$setInputs(ingestion_upload_review_identity = shown, dataset_origin = "live", start_source_import = 2L)
    check("changed origin requires its own current displayed review", !length(brohn_list_entities(store, "ingestion")) && file.exists(upload))
    session$setInputs(dataset_origin = "sample"); session$flushReact()
    session$setInputs(ingestion_upload_review_identity = identity(), start_source_import = 3L)
    queued <- brohn_ingestion(store, state$ingestion_id)
    check("explicit current review queues the whole source once", is.null(state$error) && state$page == "ingestion" &&
      queued$body$review$study_id == second$id && queued$body$review$study_revision == second$revision && queued$body$review$origin == "sample")
    check("source is pending rather than a partially saved dataset", !length(brohn_list_entities(store, "dataset")) &&
      length(brohn_list_jobs(store)) == 1L && brohn_list_jobs(store)[[1]]$operation == "ingest_source" && !file.exists(upload))
    session$setInputs(ingestion_form_identity = paste(queued$id, queued$revision, sep = ":"),
      cancel_ingestion = list(id = queued$id, revision = queued$revision))
    cancelled <- brohn_ingestion(store, queued$id)
    check("cancel uses the exact reviewed intake revision", cancelled$body$effective_status == "cancelled" && is.null(cancelled$body$dataset_id))
    session$setInputs(retry_ingestion = list(id = queued$id, revision = queued$revision))
    check("stale retry cannot create another processing attempt", length(brohn_list_jobs(store)) == 1L && grepl("import changed", state$error, ignore.case = TRUE))
    session$setInputs(ingestion_form_identity = paste(cancelled$id, cancelled$revision, sep = ":"),
      retry_ingestion = list(id = cancelled$id, revision = cancelled$revision))
    retried <- brohn_ingestion(store, queued$id)
    check("explicit retry keeps the original upload and study review", length(brohn_list_jobs(store)) == 2L &&
      retried$body$effective_status == "queued" && identical(retried$body$review_hash, queued$body$review_hash))
    brohn_cancel_ingestion(store, retried$id, retried$revision)
    display <- retried; display$body$source_snapshot$owner$pid <- -1; display$body$effective_status <- "preserving_source"
    check("active worker may finish after original owner exits", grepl("may complete under its own file guard", as.character(brohn_ingestion_detail_ui(store, display)), fixed = TRUE))
  })
  for (i in 1:88) {
    id <- sprintf("history-intake-%03d", i)
    body <- list(id = id, status = "needs_attention", review = list(study_id = if (i <= 45) first$id else second$id,
      title = paste("History fixture", i), filename = paste0(i, ".csv"), origin = "sample", modality = "temperature", size = 10))
    brohn_put_entity(store, "ingestion", id, body)
  }
  a <- brohn_ingestion_history(store, study_id = first$id)
  b <- brohn_ingestion_history(store, study_id = first$id, offset = 40)
  check("historical study filter precedes the page limit", a$total == 45 && length(a$records) == 40 && a$has_next &&
    all(vapply(a$records, function(r) r$body$review$study_id == first$id, logical(1))))
  check("older import attempts remain reachable with exact totals", b$total == 45 && length(b$records) == 5 && b$has_previous && !b$has_next &&
    !any(vapply(a$records, `[[`, character(1), "id") %in% vapply(b$records, `[[`, character(1), "id")))
  check("history pagination remains explicit in the accessible markup", grepl("Next imports", as.character(brohn_ingestion_history_ui(a)), fixed = TRUE))
  cat(sprintf("PASS: %d actual Shiny intake review and historical retrieval checks\n", checks))
})
