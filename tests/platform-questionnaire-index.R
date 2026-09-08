# Original synthetic source records; this is index/inspection evidence only,
# not receiver acceptance or new scientific-method qualification.
source("R/platform-core.R", encoding = "UTF-8")
source("R/platform-questionnaire-artifacts.R", encoding = "UTF-8")
source("R/platform-questionnaire-index.R", encoding = "UTF-8")
local({
  n <- 0L; handles <- list(); folder <- tempfile("brohn-questionnaire-index-"); dir.create(folder)
  on.exit(for (h in handles) brohn_questionnaire_index_close(h), add = TRUE)
  check <- function(label, value) {if (!isTRUE(value)) stop("FAIL: ", label); n <<- n+1L; cat("PASS", label, "\n")}
  reject <- function(label, expr, pattern = NULL) {e <- tryCatch({force(expr); NULL}, error = conditionMessage)
    check(label, !is.null(e) && (is.null(pattern) || grepl(pattern, e, fixed = TRUE)))}
  open_index <- function(result) {h <- brohn_questionnaire_index_open(result$index$path, result$index, result$index$binding); handles[[length(handles)+1L]] <<- h; h}
  input_for <- function(report, full = report$analysis, artifact_path = NULL) {
    input <- list(schema = "brohn-questionnaire-index-input/1.0", binding = list(workspace_id = "workspace-original", project_id = "project-original",
      report_id = report$id, report_revision = 1, report_hash = brohn_hash(report), origin = report$origin, analysis_sha256 = brohn_hash(full)), report = report)
    if (!is.null(artifact_path)) input$artifact_path <- artifact_path
    input
  }
  report_for <- function(analysis, id = "report-original") list(id = id, title = "Original read-only source", study_id = "study-original", dataset_id = NULL,
    origin = "sample", provenance = list(design = list(id = "study-original", project_id = "project-original"), source_note = "Original synthetic index fixture; no observed people"), analysis = analysis)
  long <- paste0(strrep("\u00e9\u6f22\U0001f512\n", 20000), "<script>original text</script>")
  values <- c(list(0, FALSE, "0", "false", NULL, "", list(0, FALSE, NULL), "<script>original</script>", long), as.list(10:72))
  observations <- lapply(seq_along(values), function(i) list(participant_id = if (i %% 2L) "unlinked:session-one" else "alias:repeat-person",
    session_id = paste0("session-", if (i %% 2L) "one" else "two"), participant_linkage = i %% 2L == 0L,
    question_id = paste0("q-", i), prompt = paste("Original \u6f22 question", i), occurrence_id = paste0("occurrence-", i),
    step_id = paste0("step-", i), stimulus_id = "same-repeated-label", condition_id = if (i %% 2L) "control" else "test",
    value = values[[i]], origin = "sample", status = if (is.null(values[[i]])) "optional_omission" else "answered"))
  features <- lapply(1:12, function(i) list(question_id = paste0("q-", i), prompt = paste("Original summary", i), condition_id = "control",
    response_count = 72, answered_count = 71, missing_count = 1, numeric_response_mean = if (i == 12L) 1/3 else NULL,
    counts = if (i == 12L) lapply(1:72, function(j) list(value = j, label = paste("Source value", j), count = 73-j)) else list()))
  analysis <- list(kind = "questionnaire", title = "Original responses", features = features, observations = observations,
    quality = list(response_count = 72, participant_count = NULL))
  report <- report_for(analysis); original_hash <- brohn_hash(report)
  input <- input_for(report); built <- brohn_build_questionnaire_index(input, file.path(folder, "inline.sqlite")); h <- open_index(built)
  check("build returns complete SQLite descriptor with exact original binding", built$status == "complete" && built$index$media_type == "application/vnd.sqlite3" &&
    identical(brohn_hash(built$index$binding), brohn_hash(input$binding)) && built$index$counts$answers == 72 && built$index$counts$distribution == 72)
  check("building and reading does not mutate the original report", identical(brohn_hash(report), original_hash))
  first <- brohn_questionnaire_index_page(h, "answers"); second <- brohn_questionnaire_index_page(h, "answers", cursor = first$next_cursor)
  rows <- c(first$rows, second$rows)
  check("all72 records appear exactly once across the50-row boundary", first$returned == 50 && second$returned == 22 && is.null(second$next_cursor) &&
    first$matching_total == 72 && first$source_total == 72 && !anyDuplicated(vapply(rows, `[[`, character(1), "record_key")) && identical(vapply(rows, `[[`, integer(1), "ordinal"), 1:72))
  check("page metadata distinguishes native0 false text and null", identical(vapply(rows[1:6], `[[`, character(1), "value_kind"), c("number", "boolean", "text", "text", "null", "text")))
  check("long and HTML-like text remain escaped-data previews rather than markup", isTRUE(rows[[9L]]$value_preview$truncated) && identical(rows[[8L]]$value_preview$text, "<script>original</script>"))
  q <- brohn_questionnaire_index_page(h, "questions", filters = list(question_id = "q-12"))
  check("summary beyond first ten retains exact saved mean and denominator", q$returned == 1 && q$rows[[1L]]$summary$numeric_response_mean == 1/3 && q$rows[[1L]]$summary$response_count == 72)
  dist <- brohn_questionnaire_index_page(h, "distribution", filters = list(parent_key = q$rows[[1L]]$record_key), limit = 100)
  check("all distribution entries remain available beyond both preview caps", dist$returned == 72 && dist$rows[[72L]]$summary$count == 1)
  selected <- brohn_questionnaire_index_page(h, "answers", filters = list(session_id = "session-two", stimulus_id = "same-repeated-label"))
  check("session and repeated stimulus identity filters do not infer unique people", selected$matching_total == 36 &&
    all(vapply(selected$rows, function(r) r$session_id == "session-two" && r$participant_id == "alias:repeat-person", logical(1))))
  search <- brohn_questionnaire_index_page(h, "answers", filters = list(search = "\u6f22 question 72"))
  check("literal UTF8 search finds a record beyond the preview", search$returned == 1 && search$rows[[1L]]$question_id == "q-72")
  check("SQL and wildcard characters remain literal search text", brohn_questionnaire_index_page(h, "answers", filters = list(search = "%_ OR 1=1 --"))$matching_total == 0)
  reject("unknown filter names cannot enter SQL", brohn_questionnaire_index_page(h, "answers", list("status OR 1=1" = "yes")))
  reject("a cursor cannot cross filter contexts", brohn_questionnaire_index_page(h, "answers", list(question_id = "q-72"), first$next_cursor))
  bad_cursor <- first$next_cursor; bad_cursor$index_hash <- strrep("a", 64)
  reject("a cursor cannot cross source indexes", brohn_questionnaire_index_page(h, "answers", cursor = bad_cursor))
  record <- brohn_questionnaire_index_record(h, rows[[1L]]$record_key, rows[[1L]]$source_hash)
  check("record detail reconstructs the exact original typed row and source path", identical(brohn_hash(brohn_parse(record$record_json)), brohn_hash(observations[[1L]])) &&
    identical(brohn_json(record$source_path), brohn_json(.brohn_qindex_path("observations", 1))))
  check("nonrevision source explicitly reports history unretained", record$links$history_status == "not_retained_for_this_source" && h$manifest$counts$history == 0)
  reject("record detail rejects a different original hash", brohn_questionnaire_index_record(h, rows[[1L]]$record_key, strrep("a", 64)))
  reject("record detail rejects foreign record key", brohn_questionnaire_index_record(h, paste0("qr-", strrep("a", 64)), rows[[1L]]$source_hash))
  large <- rows[[9L]]; detail <- brohn_questionnaire_index_record(h, large$record_key, large$source_hash)
  check("large source row is chunked without copying it into the bounded detail", detail$record_chunked && is.null(detail$record_json) && detail$record_bytes > 128*1024)
  join_chunks <- function(row, field = "value", bytes = 8191L) {
    parts <- list(); offset <- 0L
    repeat {
      chunk <- brohn_questionnaire_index_value(h, row$record_key, if (field == "value") row$value_hash else row$source_hash, offset, bytes, field)
      stopifnot(validUTF8(chunk$text), nchar(chunk$text, type = "bytes") <= bytes)
      parts[[length(parts)+1L]] <- chunk$text
      if (is.null(chunk$next_offset)) break
      stopifnot(chunk$next_offset > offset); offset <- chunk$next_offset
    }
    paste0(unlist(parts, use.names = FALSE), collapse = "")
  }
  check("all long Unicode text chunks join to the exact original value", identical(join_chunks(large), long))
  check("all canonical row chunks join to the exact source hash", identical(brohn_hash(brohn_parse(join_chunks(large, "record"), 1024*1024)), large$source_hash))
  check("empty text and null have distinct complete representations", identical(join_chunks(rows[[6L]]), "") && identical(join_chunks(rows[[5L]]), "null"))
  check("structured values keep native0 false and null through chunking", identical(brohn_json(brohn_parse(join_chunks(rows[[7L]]))), brohn_json(values[[7L]])))
  reject("value chunks reject a stale value hash", brohn_questionnaire_index_value(h, large$record_key, strrep("b", 64)))
  reject("value chunks reject an offset beyond the complete value", brohn_questionnaire_index_value(h, large$record_key, large$value_hash, 1e8))
  reject("read-only handle cannot modify the SQLite source", DBI::dbExecute(h$con, "DELETE FROM records"))

  # Source-bound revision history with typed routing, repeated assessment,
  # information, omission and a confirmation that creates no new scored value.
  event <- function(i, step, value = NULL, occurrence = "occ-one", kind = "commit", present = TRUE) {
    payload <- list(kind = kind, occurrence_id = occurrence, state_version = i-1L, visit_id = paste0("visit-", i))
    if (present) payload["value"] <- list(value)
    list(id = paste0("event-", i), sequence = i, type = "questionnaire_event", step_id = step, question_id = paste0("q-", step), payload = payload,
      clock = list(id = "browser-monotonic", unit = "ms", value = as.character(i*10), instance_id = "page-original", time_origin_ms = "9007199254740993"))
  }
  events <- list(event(1,"driver",FALSE), event(2,"dependent",2), event(3,"scale-two",4), event(4,"driver",0),
    event(5,"scale-one",2), event(6,"scale-one",6), event(7,"scale-one",6), event(8,"scale-one-repeat",6,"occ-two"),
    event(9,"information",kind="acknowledge",present=FALSE), event(10,"optional",NULL))
  refs <- lapply(events, function(e) list(event_id=e$id,sequence=e$sequence,kind=e$payload$kind,occurrence_id=e$payload$occurrence_id,
    step_id=e$step_id,visit_id=e$payload$visit_id,state_version=e$payload$state_version,confirmation=e$sequence==7L,source_event_hash=brohn_hash(e)))
  effective <- function(step, event_id, value, status="answered", occurrence="occ-one", information=FALSE) list(
    participant_id="unlinked:run-original",participant_linkage=FALSE,session_id="run-original",origin="sample",occurrence_id=occurrence,
    step_id=step,question_id=if(step=="scale-one-repeat")"q-scale-one"else paste0("q-",step),prompt=paste("Original",step),
    stimulus_id="same-stimulus",condition_id="control",status=status,information=information,event_id=event_id,value=value,
    revision_count=if(step=="scale-one")1 else 0,response_time_ms=if(step=="scale-one")NULL else 10)
  effective_rows <- list(effective("driver","event-4",0),effective("dependent",NULL,NULL,"not_displayed"),effective("scale-one","event-6",6),
    effective("scale-two","event-3",4),effective("scale-one-repeat","event-8",6,occurrence="occ-two"),
    effective("information",NULL,NULL,"information_acknowledged",information=TRUE),effective("optional","event-10",NULL,"optional_omission"))
  inv <- list(occurrence_id="occ-one",step_id="dependent",question_id="q-dependent",cause_event_id="event-4",previous_head_event_id="event-2",
    rule_hash=strrep("d",64),policy_hash=strrep("e",64),dependency_generation=1)
  revision <- list(schema="brohn-questionnaire-revision-projection/1.0",run_id="run-original",projection_hash=brohn_hash(effective_rows),
    effective_records=effective_rows,history_records=refs,history_events=events,invalidations=list(inv))
  response_subset <- Filter(function(r) r$status %in% c("answered","optional_omission")&&!isTRUE(r$information),effective_rows)
  revised_analysis <- list(kind="questionnaire",features=list(),observations=response_subset,
    questionnaire_revision=list(schema="brohn-questionnaire-revision-results/1.0",runs=list(revision)),
    scales=list(observations=list(list(value=5,source_values=list(6,4)))))
  revised_report <- report_for(revised_analysis,"report-revised")
  packed <- brohn_pack_questionnaire_report(revised_report,folder,threshold=1024)
  revised_input <- input_for(packed,revised_analysis,packed$analysis$artifacts[[1L]]$path)
  revised <- brohn_build_questionnaire_index(revised_input,file.path(folder,"revised.sqlite")); rh <- open_index(revised)
  rp <- brohn_questionnaire_index_page(rh,"answers")
  check("revision final states replace overlapping observations without double counting",rp$returned==7L&&revised$index$counts$answers==7L&&rh$manifest$original_counts$observations==5L)
  check("repeated question/stimulus label keeps both occurrence identities",brohn_questionnaire_index_page(rh,"answers",list(question_id="q-scale-one"))$matching_total==2L)
  check("information and hidden states are inspectable but not invented scored responses",sum(vapply(rp$rows,function(r)r$status %in% c("not_displayed","information_acknowledged"),logical(1)))==2L)
  history <- brohn_questionnaire_index_page(rh,"history",list(step_id="scale-one"))
  hd <- lapply(history$rows,function(r)brohn_questionnaire_index_record(rh,r$record_key,r$source_hash))
  check("history links exact source events and confirmation without inventing a version",length(hd)==3L&&isTRUE(hd[[3L]]$links$reference$confirmation)&&
    all(vapply(hd,function(r)identical(brohn_hash(brohn_parse(r$record_json)),r$links$reference$source_event_hash),logical(1))))
  invalidation <- brohn_questionnaire_index_page(rh,"invalidations")
  idetail <- brohn_questionnaire_index_record(rh,invalidation$rows[[1L]]$record_key,invalidation$rows[[1L]]$source_hash)
  check("dependency invalidation retains exact original cause and previous answer hashes",idetail$links$cause_event_hash==brohn_hash(events[[4L]])&&idetail$links$previous_event_hash==brohn_hash(events[[2L]]))
  score_rows <- Filter(function(r)r$step_id %in% c("scale-one","scale-two"),rp$rows)
  score_values <- vapply(score_rows,function(r)brohn_parse(brohn_questionnaire_index_record(rh,r$record_key,r$source_hash)$record_json)$value,numeric(1))
  check("independent final6+4 oracle gives5 while original2 remains history",mean(score_values)==5&&brohn_parse(hd[[1L]]$record_json)$payload$value==2&&
    identical(brohn_hash(revised_analysis$scales),brohn_hash(revised_report$analysis$scales)))
  expected <- revised$index$binding; expected$origin <- "live"
  reject("opening another declared origin fails before querying",brohn_questionnaire_index_open(revised$index$path,revised$index,expected))
  wrong <- revised_input; wrong$report$analysis$quality <- list(usable=TRUE);wrong$binding$report_hash <- brohn_hash(wrong$report)
  reject("altered compact status cannot index genuine source bytes",brohn_build_questionnaire_index(wrong,file.path(folder,"wrong-preview.sqlite")))
  wrong <- input;wrong$binding$report_hash<-strrep("f",64)
  reject("mutated or foreign report identity fails",brohn_build_questionnaire_index(wrong,file.path(folder,"wrong-source.sqlite")))
  reject_source <- function(label,change) {bad <- revised_analysis;bad<-change(bad);r<-report_for(bad,paste0("report-",label));p<-file.path(folder,paste0(label,".sqlite"));
    reject(label,brohn_build_questionnaire_index(input_for(r),p));check(paste(label,"leaves no partial published index"),!file.exists(p)&&!length(list.files(folder,pattern="partial\\.sqlite")))}
  reject_source("missing-history",function(a){a$questionnaire_revision$runs[[1L]]$history_events<-events[-2L];a})
  reject_source("foreign-event-hash",function(a){a$questionnaire_revision$runs[[1L]]$history_records[[1L]]$source_event_hash<-strrep("f",64);a})
  reject_source("missing-invalidation-cause",function(a){a$questionnaire_revision$runs[[1L]]$invalidations[[1L]]$cause_event_id<-"event-missing";a})
  reject_source("mixed-observations",function(a){a$observations<-c(a$observations,list(observations[[1L]]));a})
  target<-file.path(folder,"row-limit.sqlite");reject("row limit never returns a truncated index",brohn_build_questionnaire_index(input,target,list(max_rows=2)))
  check("row limit failure leaves destination absent",!file.exists(target))
  target<-file.path(folder,"disk-limit.sqlite");reject("disk limit never returns a partial index",brohn_build_questionnaire_index(input,target,list(max_index_bytes=16384)))
  check("disk limit failure leaves destination absent",!file.exists(target))
  published<-built$index;published$hash<-published$sha256;published$sha256<-NULL;published$size<-published$bytes;published$bytes<-NULL;published$path<-NULL
  ph<-brohn_questionnaire_index_open(built$index$path,published,published$binding);handles[[length(handles)+1L]]<-ph
  check("published descriptor reopens without a scratch path",brohn_questionnaire_index_page(ph,"answers")$matching_total==72L)
  brohn_questionnaire_index_close(ph);reject("closed handle cannot serve stale content",brohn_questionnaire_index_page(ph,"answers"))
  corrupted<-file.path(folder,"corrupt.sqlite");file.copy(built$index$path,corrupted)
  f<-file(corrupted,"r+b");seek(f,100);writeBin(as.raw(255),f);close(f)
  reject("corrupt SQLite bytes cannot masquerade as a saved index",brohn_questionnaire_index_open(corrupted,built$index,input$binding))
  cat("PASS:",n,"questionnaire index checks; source fixtures are synthetic; no scientific workers.\n")
})
