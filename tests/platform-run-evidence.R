# Original storage-level evidence fixtures, not observed participants and not
# receiver/scientific qualification. The large journal avoids costly replay by
# seeding explicit retained rows with independently calculated SHA-256 values.
# Use the exact inherited library selected by the configured QA runner.
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = FALSE)
source("R/platform-run-evidence.R", encoding = "UTF-8")
local({
  checks <- character(); check <- function(name, value) {if (!isTRUE(value)) stop("FAIL: ", name); checks <<- c(checks, name)}
  rejects <- function(expr, pattern = NULL) {
    message <- tryCatch({force(expr); NULL}, error = conditionMessage)
    if (!is.null(message) && !is.null(pattern) && !grepl(pattern, message, fixed = TRUE)) cat("Unexpected rejection: ", message, "\n")
    !is.null(message) && (is.null(pattern) || grepl(pattern, message, fixed = TRUE))
  }
  root <- tempfile("brohn-run-evidence-"); store <- brohn_open_store(root); second <- NULL
  on.exit({brohn_close_store(second); brohn_close_store(store)}, add = TRUE)
  .brohn_delivery_schema(store)
  rawhash <- function(text) digest::digest(charToRaw(enc2utf8(text)), algo = "sha256", serialize = FALSE)
  saved <- brohn_new_design("Original run evidence transport", "survey", "study-run-evidence")
  saved$instructions <- ""; saved$questions <- list(brohn_question("Original retained numeric answer", "number", "end", "q-evidence"))
  saved$questions[[1]]$max <- 1.2345678901234567
  brohn_put_entity(store, "study", saved$id, saved)
  release <- brohn_publish(store, saved$id, "sample")
  event <- function(sequence, payload, type = "visibility", id = paste0("original-event-", sequence)) list(
    sequence = sequence, id = id, type = type, step_id = NULL, stimulus_id = NULL, condition_id = NULL, question_id = NULL,
    phase = "transport_fixture", clock = list(id = "browser-monotonic", unit = "ms", value = as.character(sequence),
      instance_id = "original-page", time_origin_ms = "9007199254740993"), payload = payload)
  seed <- function(texts, deployment = release, design = saved, legacy_protocol = FALSE, bad_hash = FALSE, final_sequence = length(texts), completion = "completed") {
    run_id <- brohn_id("run"); count <- DBI::dbGetQuery(store$con, "SELECT count(*) AS n FROM delivery_runs WHERE deployment_id=?", params = list(deployment$id))$n[[1]]+1L
    protocol <- brohn_compile(design, count)
    protocol_json <- if (legacy_protocol) as.character(jsonlite::toJSON(protocol, auto_unbox = TRUE, null = "null", digits = NA, force = TRUE)) else .brohn_store_json(protocol)
    stamp <- brohn_now()
    DBI::dbWithTransaction(store$con, {
      DBI::dbExecute(store$con, paste("INSERT INTO delivery_runs (id,deployment_id,study_id,origin,participant_alias,client_id,start_hash,",
        "protocol_json,protocol_hash,allocation_index,completion_status,transfer_status,acked_sequence,created_at,updated_at,finalized_at,participant_alias_supplied)",
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"), params = list(run_id, deployment$id, design$id, "sample", "001", brohn_id("fixture-client"),
        rawhash("original synthetic start identity"), protocol_json, rawhash(protocol_json), count, completion, "saved", final_sequence, stamp, stamp, stamp, 1L))
      for (i in seq_along(texts)) {
        decoded <- jsonlite::fromJSON(texts[[i]], simplifyVector = FALSE)
        DBI::dbExecute(store$con, "INSERT INTO delivery_events VALUES (?,?,?,?,?,?)", params = list(run_id, i, decoded$id, texts[[i]], if (bad_hash && i == 1L) rawhash("different source") else rawhash(texts[[i]]), stamp))
      }
    })
    list(id = run_id, texts = texts, protocol_json = protocol_json)
  }
  claim <- function(request, operation = "analyse_run", lease = 600) {
    queued <- brohn_enqueue_job(store, operation, request, brohn_id("evidence-test"))
    job <- brohn_claim_job(store, "original-run-evidence-test", lease_seconds = lease)
    stopifnot(identical(queued$id, job$id)); job
  }
  scratch <- function() {path <- tempfile("evidence-", file.path(store$root, "scratch")); dir.create(path, recursive = TRUE); normalizePath(path, winslash = "/")}
  read_input <- function(input, path) brohn_read_run_evidence_input(brohn_parse(brohn_json(input)), path)
  finish_job <- function(job) brohn_cancel_job(store, job$id)
  rebind <- function(input) {input$run_evidence$binding_hash <- .brohn_run_evidence_binding(input); input}
  first_event <- event(1L, list(false = FALSE, zero = 0, text_zero = "0", absent = NULL,
    unicode = "Original caf\u00e9 \u2014 \u6e29\u5ea6", precise = 1+.Machine$double.eps, array = list(FALSE), tick = "9007199254740993"))
  legacy_text <- paste0('{"sequence":2,"id":"legacy-event","type":"visibility","step_id":null,"stimulus_id":null,"condition_id":null,"question_id":null,',
    '"phase":"transport_fixture","clock":{"id":"browser-monotonic","unit":"ms","value":"2"},"payload":{"original_rounded":1.23456789012345}}')
  texts <- list(.brohn_store_json(first_event), legacy_text, .brohn_store_json(event(3L, list(outcome = "completed"), "run_finished")),
    .brohn_store_json(event(4L, list(hidden = TRUE))))
  original <- seed(texts, legacy_protocol = TRUE)
  job <- claim(list(run_id = original$id)); path <- scratch()
  before_rows <- DBI::dbGetQuery(store$con, "SELECT * FROM delivery_events WHERE run_id=? ORDER BY sequence", params = list(original$id))
  input <- brohn_prepare_run_evidence_input(store, job, path); hydrated <- read_input(input, path)
  old <- brohn_job_input(store, job)
  check("hydration equals the existing scorer input exactly", identical(brohn_json(hydrated[setdiff(names(hydrated), "run_evidence")]), brohn_json(old)))
  check("false, numeric zero, text zero, null, array, Unicode and adjacent binary64 survive", identical(brohn_json(hydrated$events[[original$id]][[1]]), brohn_json(first_event)))
  check("original legacy decimal is retained rather than restored from a new encoder", identical(hydrated$events[[original$id]][[2]]$payload$original_rounded, 1.23456789012345))
  check("legacy protocol is consumed from exact original bytes despite encoder precision difference", identical(readBin(file.path(path, input$run_evidence$runs[[1]]$protocol$path), "raw", n = 16*1024^2), charToRaw(enc2utf8(original$protocol_json))) &&
    !identical(hydrated$design$questions[[1]]$max, saved$questions[[1]]$max))
  journal <- file.path(path, input$run_evidence$runs[[1]]$journal$path)
  check("journal is exactly original row bytes with one LF per retained row", identical(readBin(journal, "raw", n = 1024^2), charToRaw(enc2utf8(paste0(paste(texts, collapse = "\n"), "\n")))))
  check("source rows remain immutable and unchanged", identical(before_rows, DBI::dbGetQuery(store$con, "SELECT * FROM delivery_events WHERE run_id=? ORDER BY sequence", params = list(original$id))))
  check("compact input excludes inline design, events and credentials", nchar(brohn_json(input), type = "bytes") < 8192 &&
    !any(c("design", "events", "runs") %in% names(input)) && !grepl('"(token|access_token|client_id|start_hash|worker)"', brohn_json(input), perl = TRUE))
  check("whole original protocol and journal hashes are pinned", identical(input$run_evidence$runs[[1]]$protocol$sha256, rawhash(original$protocol_json)) &&
    identical(input$run_evidence$runs[[1]]$journal$sha256, digest::digest(file = journal, algo = "sha256")))
  check("trailing durable visibility receipt remains after the completed ending", length(hydrated$events[[original$id]]) == 4L && hydrated$events[[original$id]][[4]]$type == "visibility")
  check("existing input directory is never overwritten", rejects(brohn_prepare_run_evidence_input(store, job, path), "already been used"))
  bad <- input; bad$run_evidence$runs[[1]]$metadata$participant_alias <- "002"
  check("manifest alteration fails its binding hash", rejects(read_input(bad, path), "integrity"))
  bad <- rebind(bad)
  check("row chain binds even same-protocol evidence to exact participant metadata", rejects(read_input(bad, path), "Consumed journal"))
  for (unsafe in c("../events.jsonl", "input-evidence/../events.jsonl", "input-evidence/RUN-00000001.events.jsonl", "input-evidence/run-00000001.events.jsonl.", "C:/foreign/events.jsonl", "input-evidence\\run-00000001.events.jsonl", "input-evidence/run-00000001.events.jsonl:secret")) {
    bad <- input; bad$run_evidence$runs[[1]]$journal$path <- unsafe
    check(paste("reject noncanonical path", unsafe), rejects(read_input(rebind(bad), path), "relative path"))
  }
  foreign_scratch <- tempfile("foreign-evidence-root-"); dir.create(foreign_scratch)
  check("input cannot choose the independent scratch root", rejects(read_input(input, foreign_scratch)))
  if (.Platform$OS.type == "windows") {
    linked_root <- scratch(); dir.create(file.path(linked_root, "retained"))
    file.copy(list.files(file.path(path, "input-evidence"), full.names = TRUE), file.path(linked_root, "retained"))
    created <- Sys.junction(file.path(linked_root, "retained"), file.path(linked_root, "input-evidence"))
    check("actual Windows junction within trusted root is rejected", isTRUE(created) && rejects(read_input(input, linked_root), "symbolic links"))
  }
  bad <- input; bad$run_evidence$schema <- "brohn-run-evidence-input/99.0"
  check("unknown manifest schema rejected", rejects(read_input(rebind(bad), path)))
  bad <- input; bad$run_evidence$access_token <- "must-not-be-accepted"
  check("unknown credential-bearing manifest fields rejected", rejects(read_input(rebind(bad), path)))
  mutate_journal <- function(transform, change_whole_hash = FALSE) {
    saved_bytes <- readBin(journal, "raw", n = file.info(journal)$size); on.exit(writeBin(saved_bytes, journal), add = TRUE)
    changed <- transform(saved_bytes); writeBin(changed, journal); altered <- input
    if (change_whole_hash) {
      altered$run_evidence$runs[[1]]$journal$bytes <- length(changed)
      altered$run_evidence$runs[[1]]$journal$sha256 <- digest::digest(file = journal, algo = "sha256")
      altered <- rebind(altered)
    }
    read_input(altered, path)
  }
  check("same-size source mutation rejected by whole file hash", rejects(mutate_journal(function(raw) {raw[[20]] <- as.raw(88); raw}), "whole-file hash"))
  check("truncation rejected even with rewritten whole-file descriptor", rejects(mutate_journal(function(raw) head(raw, -1L), TRUE), "truncated"))
  swapped <- texts[c(2, 1, 3, 4)]
  check("out-of-order rows rejected independently of a rewritten whole-file hash", rejects(mutate_journal(function(raw) charToRaw(paste0(paste(swapped, collapse = "\n"), "\n")), TRUE), "sequence"))
  duplicated <- texts; duplicate_event <- first_event; duplicate_event$sequence <- 2L; duplicated[[2]] <- .brohn_store_json(duplicate_event)
  check("duplicate event IDs rejected independently of a rewritten whole-file hash", rejects(mutate_journal(function(raw) charToRaw(paste0(paste(duplicated, collapse = "\n"), "\n")), TRUE), "duplicate"))
  modified <- texts; modified_event <- first_event; modified_event$payload$zero <- 1; modified[[1]] <- .brohn_store_json(modified_event)
  check("consumed row chain rejects changed contents with a rewritten whole-file hash", rejects(mutate_journal(function(raw) charToRaw(paste0(paste(modified, collapse = "\n"), "\n")), TRUE), "Consumed journal"))
  check("oversized physical journal line rejected with bounded chunk parser", rejects(mutate_journal(function(raw) c(rep(as.raw(32), 4*1024^2+1L), as.raw(10)), TRUE), "four MiB"))
  check("empty physical journal line rejected", rejects(mutate_journal(function(raw) c(as.raw(10), raw), TRUE), "empty"))
  bad <- input; bad$project_id <- "foreign-project"
  check("foreign project binding rejected even with rewritten manifest hash", rejects(read_input(rebind(bad), path), "project"))
  bad <- input; bad$run_evidence$runs[[1]]$metadata$allocation_index <- 2L
  check("foreign allocation rejected", rejects(read_input(rebind(bad), path), "allocation"))
  badjob <- job; badjob$token <- "foreign-claim"
  check("wrong job authentication binding rejected before files", rejects(brohn_prepare_run_evidence_input(store, badjob, scratch()), "job lease"))
  badjob <- job; badjob$request <- list(run_id = brohn_id("foreign-run"))
  check("changed original job request rejected before files", rejects(brohn_prepare_run_evidence_input(store, badjob, scratch()), "job lease"))
  second <- brohn_open_store(tempfile("brohn-evidence-foreign-workspace-"))
  check("job from another workspace cannot authorize source preparation", rejects(brohn_prepare_run_evidence_input(second, job, scratch()), "job lease"))
  check("spool refuses an existing enclosing transaction", DBI::dbWithTransaction(store$con, rejects(brohn_prepare_run_evidence_input(store, job, scratch()), "outside a catalog")))
  finish_job(job)
  check("cancelled original job cannot prepare evidence", rejects(brohn_prepare_run_evidence_input(store, job, scratch()), "job lease"))
  job <- claim(list(run_id = original$id)); original_validator <- .brohn_run_evidence_event; cancelled_once <- FALSE
  assign(".brohn_run_evidence_event", function(bytes, sequence, ids, protocol) {
    value <- original_validator(bytes, sequence, ids, protocol)
    if (!cancelled_once) {cancelled_once <<- TRUE; brohn_cancel_job(store, job$id)}
    value
  }, envir = .GlobalEnv)
  cancellation_rejected <- tryCatch(rejects(brohn_prepare_run_evidence_input(store, job, scratch()), "job lease"),
    finally = assign(".brohn_run_evidence_event", original_validator, envir = .GlobalEnv))
  check("cancellation during spooling cannot return a worker manifest", cancellation_rejected && brohn_get_job(store, job$id)$status == "cancelled")
  check("mid-spool cancellation leaves original participant evidence intact", identical(before_rows, DBI::dbGetQuery(store$con, "SELECT * FROM delivery_events WHERE run_id=? ORDER BY sequence", params = list(original$id))))
  original2 <- seed(list(.brohn_store_json(event(1L, list(outcome = "completed"), "run_finished"))))
  job <- claim(list(deployment_id = release$id, run_ids = list(original2$id, original$id), recipe = "typed-explicit-responses/1.0.0-draft"), "analyse_cohort")
  cohort_path <- scratch(); cohort <- brohn_prepare_run_evidence_input(store, job, cohort_path); cohort_hydrated <- read_input(cohort, cohort_path)
  check("frozen cohort preserves explicit run order and exact source identities", identical(vapply(cohort_hydrated$runs, `[[`, character(1), "id"), c(original2$id, original$id)))
  # Both protocols have the same original design identity, but the retained old
  # precision is allowed; each original protocol byte hash remains separate.
  check("each cohort run preserves its own protocol bytes and allocation", cohort_hydrated$runs[[1]]$allocation_index == 2L && cohort_hydrated$runs[[2]]$allocation_index == 1L)
  bad <- cohort; bad$run_evidence$runs <- rev(bad$run_evidence$runs)
  check("cross-run descriptor swap cannot change frozen membership", rejects(read_input(rebind(bad), cohort_path), "another session"))
  finish_job(job)
  foreign_design <- brohn_new_design("Original other project", "survey", "study-evidence-other", "other-project")
  foreign_design$questions <- list(brohn_question("Original other-project question", "rating", "end", "q-evidence-other"))
  brohn_put_entity(store, "study", foreign_design$id, foreign_design, project_id = foreign_design$project_id)
  foreign_release <- brohn_publish(store, foreign_design$id, "sample")
  foreign_run <- seed(list(.brohn_store_json(event(1L, list(outcome = "completed"), "run_finished"))), foreign_release, foreign_design)
  job <- claim(list(deployment_id = release$id, run_ids = list(original$id, foreign_run$id), recipe = "typed-explicit-responses/1.0.0-draft"), "analyse_cohort")
  check("foreign project run cannot enter requested release cohort", rejects(brohn_prepare_run_evidence_input(store, job, scratch()), "outside this frozen")); finish_job(job)
  job <- claim(list(run_id = original$id, project_id = "other-project"))
  check("explicit foreign project authorization cannot redirect single-run evidence", rejects(brohn_prepare_run_evidence_input(store, job, scratch()), "outside this frozen")); finish_job(job)
  job <- claim(list(deployment_id = release$id, run_ids = list(original$id, original$id), recipe = "typed-explicit-responses/1.0.0-draft"), "analyse_cohort")
  check("duplicate requested run identity rejected", rejects(brohn_prepare_run_evidence_input(store, job, scratch()), "distinct")); finish_job(job)
  broken <- seed(texts, bad_hash = TRUE); job <- claim(list(run_id = broken$id))
  check("damaged retained row hash rejected before input publication", rejects(brohn_prepare_run_evidence_input(store, job, scratch()), "original row hash")); finish_job(job)
  mismatched <- texts; changed <- first_event; changed$sequence <- 2L; mismatched[[1]] <- .brohn_store_json(changed)
  broken <- seed(mismatched); job <- claim(list(run_id = broken$id))
  check("original row index and event sequence mismatch rejected", rejects(brohn_prepare_run_evidence_input(store, job, scratch()), "sequence")); finish_job(job)
  broken <- seed(texts, final_sequence = 5L); job <- claim(list(run_id = broken$id))
  check("missing final durable sequence rejected", rejects(brohn_prepare_run_evidence_input(store, job, scratch()), "incomplete")); finish_job(job)
  broken <- seed(texts, completion = "in_progress"); job <- claim(list(run_id = broken$id))
  check("in-progress source cannot enter automatic completed-run evidence", rejects(brohn_prepare_run_evidence_input(store, job, scratch()), "completed")); finish_job(job)
  changed <- first_event; changed$step_id <- "foreign-step"; mismatched <- texts; mismatched[[1]] <- .brohn_store_json(changed)
  broken <- seed(mismatched); job <- claim(list(run_id = broken$id))
  check("retained foreign protocol step rejected", rejects(brohn_prepare_run_evidence_input(store, job, scratch()), "different protocol")); finish_job(job)
  huge_row <- .brohn_store_json(event(1L, list(text = paste(rep("x", 4*1024^2), collapse = ""))))
  broken <- seed(list(huge_row)); job <- claim(list(run_id = broken$id))
  check("oversized catalog event rejected by length query before page decode", rejects(brohn_prepare_run_evidence_input(store, job, scratch()), "four MiB")); finish_job(job)
  # The 20 MiB original payload is intentionally larger than the old request
  # document limit, while every row remains well below four MiB.
  paragraph <- paste(rep("Original synthetic long answer. ", 18000L), collapse = "")
  large_texts <- lapply(1:36, function(i) .brohn_store_json(event(i, list(original_text = paragraph, assessment = i))))
  large_texts[[37]] <- .brohn_store_json(event(37L, list(outcome = "completed"), "run_finished"))
  large <- seed(large_texts); job <- claim(list(run_id = large$id), lease = 2)
  large_path <- scratch(); large_input <- brohn_prepare_run_evidence_input(store, job, large_path)
  check("short initial lease is renewed without a long read transaction", brohn_get_job(store, job$id)$lease_until-.brohn_store_now() > 45)
  check("original journal exceeds sixteen MiB but manifest stays compact", large_input$run_evidence$runs[[1]]$journal$bytes > 16*1024^2 && nchar(brohn_json(large_input), type = "bytes") < 8192)
  large_hydrated <- read_input(large_input, large_path)
  check("large journal hydrates every original answer and terminal row exactly", length(large_hydrated$events[[large$id]]) == 37L && all(vapply(large_hydrated$events[[large$id]][1:36], function(x) identical(x$payload$original_text, paragraph), logical(1))))
  check("legacy single-document writer still enforces its original sixteen MiB limit", rejects(brohn_write_json_file(brohn_job_input(store, job), file.path(large_path, "must-not-write.json")), "size limit"))
  check("large original source rows remain exact after input preparation", identical(DBI::dbGetQuery(store$con, "SELECT event_hash FROM delivery_events WHERE run_id=? ORDER BY sequence", params = list(large$id))$event_hash,
    vapply(large_texts, rawhash, character(1))))
  finish_job(job)
  workspace_id <- store$workspace_id; brohn_close_store(store); store <- brohn_open_store(root)
  check("reopened source retains exact run identity and original protocol hash", identical(store$workspace_id, workspace_id) && identical(DBI::dbGetQuery(store$con, "SELECT protocol_hash FROM delivery_runs WHERE id=?", params = list(original$id))$protocol_hash[[1]], rawhash(original$protocol_json)))
  cat("Run evidence checks passed:", length(checks), "\n")
  cat("Large original journal bytes:", large_input$run_evidence$runs[[1]]$journal$bytes, "; compact input bytes:", nchar(brohn_json(large_input), type = "bytes"), "\n")
})
