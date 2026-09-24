# Actual summary coordinator and saved-support checks using authored GNAT rows.
# This does not claim browser execution, native journal replay or job publication.
source("R/platform-load.R", encoding="UTF-8"); brohn_load(ui=TRUE)
source("tests/fixtures/gnat-journal.R", encoding="UTF-8")
local({
  args <- commandArgs(trailingOnly=TRUE)
  folder <- if(length(args))args[[1L]]else tempfile("gnat-import-",tmpdir=Sys.getenv("BROHN_QA_EVIDENCE_PARENT",tempdir()))
  stopifnot(!dir.exists(folder)); dir.create(folder,recursive=TRUE)
  checks <- character()
  files <- c("R/platform-core.R","R/platform-methods.R","R/platform-gnat.R","R/platform-gnat-import.R",
    "R/platform-task-import.R","R/platform-task-import-views.R","R/platform-task-cohort.R",
    "tests/fixtures/gnat-journal.R","tests/platform-gnat-import.R")
  hashes <- function()setNames(lapply(files,function(p)digest::digest(file=p,algo="sha256")),files)
  source_start <- hashes(); brohn_write_json_file(source_start,file.path(folder,"source-start.json"))
  on.exit(if(!file.exists(file.path(folder,"results.json")))brohn_write_json_file(list(passed=FALSE,checks=as.list(checks),
    source_start=source_start,source_end=hashes()),file.path(folder,"failure-progress.json")),add=TRUE)
  check <- function(label,value) {if(!isTRUE(value))stop(label,call.=FALSE);checks<<-c(checks,label);cat("PASS",label,"\n")}
  rejects <- function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  same <- function(a,b)identical(brohn_hash(a),brohn_hash(b))
  task <- brohn_task_new("gnat-brohn-single-target/1.0",id="gnat-import-original")
  design <- brohn_new_design("Original authored GNAT summary","blank",id="gnat-import-study")
  design$blocks <- list(task); compiled <- brohn_task_compile(task,1L)
  trials <- Filter(function(t)t$type=="task_trial",compiled$timeline)
  journal <- original_gnat_journal(compiled)
  terminal <- Filter(function(e)e$payload$kind=="task_trial_finished",journal)
  responses <- lapply(terminal,function(e)e$payload$data)
  protocol_id <- paste0("protocol-",brohn_hash(compiled))
  registry <- list(schema="brohn-implicit-protocol-registry/1.0",task=task,
    protocols=list(list(id=protocol_id,compiled_hash=brohn_hash(compiled),compiled=compiled)))
  identity <- list(participant_id="person-original",participant_linkage=TRUE,session_id="visit-original",
    attempt_id="attempt-original",protocol_id=protocol_id,origin="sample",source_collection_id="authored-collection")
  rows <- lapply(seq_along(trials),function(i).brohn_gnat_native_row(trials[[i]],responses[[i]],identity,i))
  columns <- names(rows[[1L]])
  data <- as.data.frame(setNames(lapply(columns,function(f)vapply(rows,`[[`,character(1),f)),columns),stringsAsFactors=FALSE)
  path <- file.path(folder,"original-authored-trials.csv")
  utils::write.csv(data,path,row.names=FALSE,na="",fileEncoding="UTF-8")
  data <- brohn_read_table(path,"csv",20000L)
  registry_path <- file.path(folder,"original-registry.json"); brohn_write_json_file(registry,registry_path)
  original <- list(id="gnat-import-source",revision=1L,hash=digest::digest(file=path,algo="sha256"),origin="sample",
    registry_object_hash=digest::digest(file=registry_path,algo="sha256"))
  metadata <- list(adapter=.brohn_gnat_import_adapter,task_id=task$id,source_collection_id=identity$source_collection_id,
    origin_statement="Original authored software fixture; no participant or device qualification.",source_software=NULL,
    source_rt_definition="space_ms_from_onset_no_rt_for_withholding",terminal_response_rule="space_or_visible_deadline",
    evidence_level="declared_trial_summary")
  aliases <- c(participant="participant_id",session="session_id",attempt="attempt_id",protocol="protocol_id",trial="trial_id")
  for(field in .brohn_task_import_columns(metadata$adapter)) {
    base <- sub("_column$","",field)
    metadata[[field]] <- if(base %in% names(aliases))unname(aliases[[base]])else base
  }
  run <- function(d=data,m=metadata)brohn_import_task_trials(d,m,design,original,registry)
  result <- run(); attempt <- result$task_attempts[[1L]]; score <- attempt$score
  expected <- brohn_task_score(compiled,responses,TRUE)
  check("Complete summary keeps every original trial and separate four outcomes",result$quality$source_row_count==384L &&
    result$quality$derived_missing_trial_count==0L && length(unique(vapply(attempt$responses,`[[`,character(1),"outcome")))==4L)
  check("Qualified declared summary agrees with direct procedure metrics",score$eligible && same(score$metrics,expected$metrics))
  check("Summary import never acquires a browser journal",identical(attempt$evidence_level,"declared_trial_summary") &&
    !attempt$timing_quality$journal_replayed && is.null(attempt$timing_quality$key_history))
  check("Canonical cohort validation accepts exact GNAT recipe and units",identical(.brohn_task_cohort_attempt(attempt),attempt) &&
    all(vapply(score$metrics,function(m)m$unit=="dimensionless",logical(1))))
  check("Original source text and field hashes remain intact",all(vapply(seq_len(nrow(data)),function(i)
    same(result$source_rows[[i]]$original_cells,lapply(as.list(data[i,,drop=FALSE]),unname)),logical(1))))
  withheld <- which(data$outcome=="correct_rejection" & data$phase=="test")[[1L]]
  check("Correct withholding is true accuracy with no RT or first-response correctness",
    isTRUE(attempt$responses[[withheld]]$correct) && is.null(attempt$responses[[withheld]]$response_ms) &&
      is.null(attempt$responses[[withheld]]$first_correct) &&
      identical(attempt$trial_audit[[withheld]]$disposition,"candidate_for_task_scoring"))
  bad <- data; bad$response_ms[[withheld]] <- "0"
  check("Withholding cannot acquire an artificial zero response time",rejects(run(bad)))
  bad <- metadata; bad$adapter <- NULL
  check("GNAT cannot use generic two-key response fields",rejects(run(m=bad)))
  bad <- metadata; bad$adapter <- "brohn-gnat-trial-summary/9.0"
  check("Unknown summary adapter is refused",rejects(run(m=bad)))
  for(field in c("phase","round_id","cell_id","expected_action")) {
    bad <- data; bad[[field]][[withheld]] <- "foreign"
    check(paste("Frozen",field,"cannot be substituted"),rejects(run(bad)))
  }
  hit <- which(data$outcome=="hit" & data$phase=="test")[[1L]]
  bad <- data; bad$response_ms[[hit]] <- as.character(trials[[hit]]$timeout_ms)
  check("Known timing rejects the exclusive deadline",rejects(run(bad)))
  unknown <- metadata; unknown$source_rt_definition <- "unknown"
  declared <- run(bad,unknown); u <- declared$task_attempts[[1L]]
  check("Unknown timing preserves source latency instead of rejecting or rewriting it",
    identical(u$responses[[hit]]$first_response_ms_source,bad$response_ms[[hit]]) &&
    u$responses[[hit]]$response_ms==trials[[hit]]$timeout_ms)
  check("Unknown timing has counts and raw rates without qualified metrics",
    !u$score$eligible && all(vapply(u$score$metrics,function(m)is.null(m$value),logical(1))) &&
    all(vapply(u$score$scoring_audit$cells,function(c)is.null(c$d_prime)&&is.null(c$criterion),logical(1))) &&
    sum(vapply(u$score$scoring_audit$cells,function(c)c$received_test,numeric(1)))==240L)
  check("Unknown timing remains an auditable canonical administration",identical(.brohn_task_cohort_attempt(u),u))
  omitted <- run(data[-withheld,,drop=FALSE]); o <- omitted$task_attempts[[1L]]
  check("Absent expected source is distinct from a recorded correct rejection",!o$score$eligible &&
    isTRUE(o$trial_audit[[withheld]]$derived) && is.null(o$trial_audit[[withheld]]$correct) && o$score$counts$received==383L)
  stopped <- data; n <- nrow(stopped)
  stopped$presented[[n]] <- "false"; stopped$outcome[[n]] <- "interrupted"
  for(field in c("response_outcome","response_code","response_ms","correct"))stopped[[field]][[n]] <- ""
  stopped$missing_reason[[n]] <- "Original source declares not presented"
  stop_result <- run(stopped)$task_attempts[[1L]]
  check("Unpresented interrupted source rows are not counted as observed trials",!stop_result$score$eligible &&
    stop_result$score$counts$received==383L && identical(stop_result$trial_audit[[n]]$disposition,"not_presented"))
  check("No response-summary case fabricates a corrected-response latency",all(vapply(attempt$responses,
    function(r)is.null(r$final_code)&&is.null(r$final_correct_ms),logical(1))))
  cloned <- brohn_task_clone(task)
  check("Cloning preserves reviewed GNAT rules and material text with new identity",cloned$id!=task$id &&
    same(cloned$settings,task$settings) && identical(vapply(cloned$materials,`[[`,character(1),"content"),vapply(task$materials,`[[`,character(1),"content")))
  html <- as.character(brohn_task_import_response_fields_ui(names(data),list(),task$profile))
  check("GNAT mapping offers withholding fields without fabricated final-correct inputs",grepl('map_task_correct_column',html,fixed=TRUE) &&
    !grepl('map_task_final_correct_ms_column',html,fixed=TRUE) && grepl('empty for withholding',html,fixed=TRUE))
  old <- as.character(brohn_task_import_response_fields_ui(names(data),list(),"iat-gnb2003-d1/1.0"))
  check("Existing IAT mapping keeps its original correction inputs",grepl('map_task_final_correct_ms_column',old,fixed=TRUE) &&
    !grepl('map_task_response_outcome_column',old,fixed=TRUE))
  check("Exercised import sources remained unchanged",same(source_start,hashes()))
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),score=score,source_start=source_start,source_end=hashes(),
    scope="Authored complete summary/coordinator/clone/view checks; not a participant or native job journey."),file.path(folder,"results.json"))
  cat("GNAT_IMPORT_PASS",length(checks),"\n")
})
