# Explicit LSL acquisition queue and independently owned local manager.
.brohn_acq_publication_code <- stats::setNames(lapply(c("R/platform-acquisition.R", "scripts/acquisition/lsl_recorder.py"),
  function(path) digest::digest(file = path, algo = "sha256")), c("R/platform-acquisition.R", "scripts/acquisition/lsl_recorder.py"))
.brohn_acq_path <- function(store, ...) {
  root <- file.path(store$root, "acquisitions")
  if (!dir.exists(root)) brohn_require(dir.create(root), "Cannot create the acquisition workspace.")
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  base <- paste0(normalizePath(store$root, winslash = "/", mustWork = TRUE), "/")
  brohn_require(startsWith(tolower(root), tolower(base)), "Acquisition directory leaves this workspace.")
  components <- list(...)
  brohn_require(all(vapply(components, function(x) brohn_text(x, 200) && !grepl("[/\\\\]|^\\.\\.?$", x), logical(1))), "Invalid acquisition path component.")
  do.call(file.path, c(list(root), components))
}
.brohn_acq_hash <- function(path) digest::digest(file = path, algo = "sha256")
.brohn_acq_atomic <- function(value, path, replace = TRUE) {
  brohn_require(replace || !file.exists(path), "This acquisition control/output already exists.")
  temporary <- tempfile(".brohn-acq-", tmpdir = dirname(path)); on.exit(unlink(temporary), add = TRUE)
  brohn_write_json_file(value, temporary)
  # Windows rename can fail briefly while a status reader holds the old file.
  for (i in seq_len(50L)) {
    if (file.rename(temporary, path)) return(invisible(path))
    Sys.sleep(.01)
  }
  brohn_stop("Could not publish acquisition state atomically.")
}
.brohn_acq_script <- function() normalizePath("scripts/acquisition/lsl_recorder.py", winslash = "/", mustWork = TRUE)
.brohn_acq_python <- function() brohn_python_profile("interchange")
.brohn_acq_read <- function(path, maximum = 2*1024^2) tryCatch(brohn_read_json_file(path, maximum), error = function(e) NULL)
.brohn_acq_check_path_budget <- function(store, id = paste0("acquisition-",strrep("0",32L))) {
  if (.Platform$OS.type != "windows") return(invisible(TRUE))
  # Include the complete local lifecycle, including archive/review scratch.
  # A conservative 32-character tempfile suffix bounds this prepared R profile.
  root <- file.path(store$root,"acquisitions"); suffix <- strrep("0",32L)
  candidates <- c(file.path(root,"recordings",id,"chunks","100000.jsonl"),
    file.path(root,"recordings",id,"manifest.json.writing"),
    file.path(root,"work",paste0(id,"-receipt.json.writing")),
    file.path(root,"work",paste0("preserve-",id,"-",suffix),"original-recording.brohn-acquisition.zip"),
    file.path(root,"work",paste0("import-",id,"-",suffix),"stream-bundle.json.writing"),
    file.path(root,"work",paste0("discovery-discovery-",strrep("0",32L),"-",suffix),"result.json.writing"))
  converted <- iconv(enc2utf8(candidates),from="UTF-8",to="UTF-16LE",toRaw=TRUE)
  units <- vapply(converted,function(x) if(is.null(x)) Inf else length(x)/2,numeric(1))
  brohn_require(all(is.finite(units)) && all(units < 260),
    "This workspace path is too long for the Windows local acquisition and archive profile. Choose a shorter workspace path before finding sources or recording.")
  invisible(TRUE)
}
.brohn_acq_process <- function(pid = Sys.getpid()) {
  p <- ps::ps_handle(as.integer(pid))
  list(pid = ps::ps_pid(p), created = as.numeric(ps::ps_create_time(p)), exe = normalizePath(ps::ps_exe(p), winslash = "/", mustWork = TRUE),
    cwd = normalizePath(ps::ps_cwd(p), winslash = "/", mustWork = TRUE), command = as.list(ps::ps_cmdline(p)))
}
.brohn_acq_probe <- function(identity) {
  if (is.null(identity)) return("unknown")
  tryCatch({
    handle <- ps::ps_handle(as.integer(identity$pid), as.POSIXct(as.numeric(identity$created), origin="1970-01-01", tz="UTC"))
    if (!ps::ps_is_running(handle)) return("absent")
    actual <- .brohn_acq_process(identity$pid)
    if (abs(actual$created-identity$created) > .001) return("absent")
    if (!identical(tolower(actual$exe), tolower(identity$exe)) || !identical(tolower(actual$cwd), tolower(identity$cwd)) ||
        !identical(actual$command, identity$command)) return("unknown")
    "owned_alive"
  }, no_such_process = function(e) "absent", error = function(e) "unknown")
}
brohn_acquisitions <- function(store, study_id = NULL, limit = 500L, status = NULL, review_status = NULL) {
  filters <- list()
  if (!is.null(study_id)) filters$study_id <- study_id
  if (!is.null(status)) filters$status <- status
  if (!is.null(review_status)) filters$review.status <- review_status
  brohn_list_entities(store, "acquisition", limit = limit, filters = filters)
}
brohn_acquisition <- function(store, id) {
  record <- brohn_get_entity(store, "acquisition", id)
  brohn_require(!is.null(record), "This acquisition is unavailable."); brohn_project(store, record$project_id)
  snapshot <- .brohn_acq_read(file.path(.brohn_acq_directory(store,record),"status.json"),2*1024^2)
  if(!is.null(snapshot) && identical(snapshot$recording_id,id) && (is.null(record$body$python_request_hash) || identical(snapshot$request_sha256,record$body$python_request_hash)))
    record$live_snapshot <- snapshot
  record
}
brohn_lsl_discoveries <- function(store, study_id = NULL, status = NULL) {
  filters <- list()
  if (!is.null(study_id)) filters$study_id <- study_id
  if (!is.null(status)) filters$status <- status
  brohn_list_entities(store, "acquisition_discovery", filters = filters)
}
brohn_queue_lsl_discovery <- function(store, study_id, lsl_session = "default", source_ids = character(), confirm_discovery = FALSE) {
  .brohn_acq_check_path_budget(store)
  study <- brohn_study(store, study_id); brohn_project(store, study$project_id)
  brohn_require(brohn_valid_id(lsl_session), "Choose a safe LSL session identifier.")
  brohn_require(is.character(source_ids) && length(source_ids) <= 16L && !anyDuplicated(source_ids) && all(vapply(as.list(source_ids), brohn_text, logical(1), max = 500)), "Choose up to 16 exact source IDs.")
  brohn_require(length(source_ids) > 0 || isTRUE(confirm_discovery), "Confirm metadata discovery on this machine.")
  request <- list(schema = "brohn-lsl-discovery-request/1.0", lsl_session = lsl_session, timeout_s = 2)
  if (length(source_ids)) request$source_ids <- as.list(source_ids) else request$allow_machine_discovery <- TRUE
  id <- brohn_id("discovery")
  brohn_put_entity(store, "acquisition_discovery", id, list(id = id, study_id = study$id, study_revision = study$revision,
    design_hash = brohn_hash(study$body), status = "queued", request = request, request_hash = brohn_hash(request),
    script_hash = .brohn_acq_hash(.brohn_acq_script()), created_at = brohn_now()), project_id = study$project_id)
}
brohn_retry_lsl_discovery <- function(store, id, expected_revision) {
  brohn_store_batch(store,function() {
    prior<-brohn_get_entity(store,"acquisition_discovery",id)
    brohn_require(!is.null(prior),"This discovery is unavailable.");brohn_project(store,prior$project_id)
    brohn_require(identical(as.numeric(prior$revision),as.numeric(expected_revision)) && prior$body$status %in% c("interrupted","failed"),
      "This discovery changed or does not need retrying. Review its current status.")
    brohn_require(identical(prior$body$request_hash,brohn_hash(prior$body$request)),"The saved discovery request failed its integrity check.")
    request<-prior$body$request
    retry<-brohn_queue_lsl_discovery(store,prior$body$study_id,request$lsl_session,
      if(length(request$source_ids)) unlist(request$source_ids,use.names=FALSE) else character(),isTRUE(request$allow_machine_discovery))
    body<-retry$body;body$retry_of<-list(id=prior$id,revision=prior$revision,request_hash=prior$body$request_hash)
    brohn_put_entity(store,"acquisition_discovery",retry$id,body,retry$revision,retry$project_id)
  })
}
brohn_lsl_selection <- function(discovery, uid, id, clock_id, clock_kind, kind, channels, unit_provenance, gap_threshold_s = NULL, readiness = NULL) {
  brohn_require(identical(discovery$body$status, "ready"), "Wait for a completed discovery before reviewing sources.")
  matches <- Filter(function(s) identical(s$uid, uid), discovery$body$result$streams)
  brohn_require(length(matches) == 1L && isTRUE(matches[[1L]]$supported), "Select one supported exact outlet UID.")
  observed <- matches[[1L]]
  brohn_require(brohn_valid_id(id) && brohn_text(clock_id, 500) && clock_kind %in% c("monotonic", "unix", "device", "unspecified_epoch") &&
    kind %in% c("signal", "markers", "unclassified") && brohn_text(unit_provenance, 1000), "Declare stream role, clock identity/epoch and unit provenance.")
  brohn_require(brohn_array(channels) && length(channels) == observed$channel_count && length(channels) <= 128L && !anyDuplicated(brohn_ids(channels)), "Review the complete original channel layout.")
  for (channel in channels) brohn_require(brohn_valid_id(channel$id) && brohn_text(channel$label, 500) && brohn_text(channel$type, 500) &&
    identical(channel$value_type, observed$value_type) && (brohn_text(channel$unit, 500) || (is.null(channel$unit) && channel$value_type == "string")), "Declare each original channel type and unit; use explicit unknown for unresolved numeric units.")
  brohn_require(is.null(gap_threshold_s) || brohn_number(gap_threshold_s, 1e-6, 3600), "Choose an explicit supported gap threshold.")
  result <- list(id = id, uid = observed$uid, source_id = observed$source_id, metadata_sha256 = observed$metadata_sha256,
    clock_id = clock_id, clock_kind = clock_kind, kind = kind, channels = channels, unit_provenance = unit_provenance)
  if (!is.null(gap_threshold_s)) result$gap_threshold_s <- gap_threshold_s
  if (!is.null(readiness)) {brohn_validate_acquisition_readiness(readiness,channels);result$readiness<-readiness}
  result
}
brohn_queue_acquisition <- function(store, study_id, discovery_id, selections, identity, origin, origin_statement,
                                    limits, expected_study_revision, reviewed = FALSE, run_id = NULL) {
  brohn_require(isTRUE(reviewed), "Confirm the selected source, full channel units, source clocks and participant/session identities.")
  brohn_store_batch(store, function() {
    study <- brohn_study(store, study_id); brohn_project(store, study$project_id)
    brohn_require(identical(as.numeric(study$revision), as.numeric(expected_study_revision)), "The study changed; review its current design before recording.")
    discovery <- brohn_get_entity(store, "acquisition_discovery", discovery_id)
    brohn_require(!is.null(discovery) && identical(discovery$project_id, study$project_id) && identical(discovery$body$study_id, study_id) &&
      identical(discovery$body$status, "ready") && identical(discovery$body$result_hash, brohn_hash(discovery$body$result)), "Use a verified discovery for this study and project.")
    brohn_require(identical(discovery$body$script_hash, .brohn_acq_hash(.brohn_acq_script())), "The recorder changed; discover and review sources again.")
    active <- brohn_acquisitions(store, status = c("queued", "starting", "recording", "stopping", "attention_required"))
    brohn_require(length(active) == 0L, "This local profile permits one recording at a time. Stop or resolve the current recording first.")
    brohn_require(brohn_array(selections) && length(selections) >= 1L && length(selections) <= 16L && !anyDuplicated(brohn_ids(selections)) &&
      !anyDuplicated(vapply(selections, `[[`, character(1), "uid")), "Choose 1 to 16 distinct reviewed sources.")
    selections <- lapply(selections, function(s) brohn_lsl_selection(discovery, s$uid, s$id, s$clock_id, s$clock_kind, s$kind, s$channels, s$unit_provenance, s$gap_threshold_s, s$readiness))
    brohn_require(is.list(identity) && all(c("participant_id", "session_id") %in% names(identity)) &&
      all(names(identity) %in% c("participant_id", "session_id", "condition_id", "exposure_id")) && all(vapply(identity, brohn_text, logical(1), max = 500)), "Supply explicit participant/session IDs; source labels are not person identities.")
    brohn_require(origin %in% c("sample", "pilot", "live") && brohn_text(origin_statement, 4000), "Declare the collection origin and its source.")
    for (s in selections) {
      observed <- Filter(function(x) identical(x$uid, s$uid), discovery$body$result$streams)[[1L]]
      classified <- tolower(brohn_default(observed$source_origin, "")); if (classified %in% c("synthetic", "synthetic/reference")) classified <- "sample"
      brohn_require(!classified %in% c("sample", "pilot", "live") || identical(classified, origin), "Collection origin conflicts with the source's own declaration.")
    }
    ranges <- list(max_duration_s = c(.1,86400), max_samples = c(1,2000000), max_bytes = c(65536,512*1024^2), chunk_samples = c(1,512), inlet_buffer = c(1,60))
    brohn_require(is.list(limits) && setequal(names(limits),names(ranges)), "Set all five bounded recording limits.")
    for (name in names(ranges)) brohn_require(brohn_number(limits[[name]],ranges[[name]][1],ranges[[name]][2], name != "max_duration_s"), paste("Invalid recording limit:", name))
    brohn_require(limits$max_samples*max(vapply(selections,function(s) length(s$channels),integer(1)))<=20000000,"Recording exceeds the 20 million channel-value bound.")
    references <- list(study_id = study_id, design_hash = brohn_hash(study$body))
    if (!is.null(run_id)) {
      run <- brohn_run(store, run_id)
      brohn_require(!is.null(run) && identical(run$study_id, study_id) && identical(run$origin, origin) &&
        identical(brohn_hash(run$protocol$design), references$design_hash), "Bind only a run of this exact study design and origin.")
      references$run_id <- run_id; references$deployment_id <- run$deployment_id
    }
    id <- brohn_id("acquisition")
    .brohn_acq_check_path_budget(store,id)
    output_root <- .brohn_acq_path(store, "recordings"); if (!dir.exists(output_root)) dir.create(output_root)
    request <- list(schema = "brohn-lsl-record-request/1.0", recording_id = id, output_root = output_root,
      lsl_session = discovery$body$request$lsl_session, origin = origin, origin_statement = origin_statement,
      identity = identity, references = references, streams = selections, limits = limits)
    brohn_put_entity(store, "acquisition", id, list(id = id, title = paste(study$body$title, "local recording"), study_id = study_id,
      study_revision = study$revision, design_hash = brohn_hash(study$body), design = study$body, discovery_id = discovery_id,
      discovery_hash = discovery$body$result_hash, origin = origin, status = "queued", request = request,
      request_hash = brohn_hash(request), script_hash = .brohn_acq_hash(.brohn_acq_script()), created_at = brohn_now()), project_id = study$project_id)
  })
}
brohn_stop_acquisition <- function(store, id, expected_revision, cancel = FALSE) brohn_store_batch(store, function() {
  r <- brohn_acquisition(store,id)
  brohn_require(identical(as.numeric(r$revision),as.numeric(expected_revision)), "This recording changed; refresh before stopping.")
  brohn_require(r$body$status %in% c("queued","starting","recording","stopping","attention_required"), "This recording has already stopped.")
  if (r$body$status == "queued") {r$body$status <- "cancelled"; r$body$completion_status <- "cancelled"; r$body$reason <- "cancelled_before_start"} else {
    r$body$control <- if (isTRUE(cancel)) "cancel" else "stop"; r$body$status <- "stopping"
  }
  brohn_put_entity(store,"acquisition",id,r$body,r$revision,r$project_id)
})
brohn_review_acquisition <- function(store, id, expected_revision, allow_incomplete = FALSE) {
  r <- brohn_acquisition(store,id)
  brohn_require(identical(as.numeric(r$revision),as.numeric(expected_revision)), "The acquisition changed; review the current receipt.")
  brohn_require(!is.null(r$body$original) && r$body$status %in% c("completed","cancelled","interrupted","incomplete"), "Wait for preserved original evidence before importing.")
  brohn_require(r$body$completion_status == "completed" || isTRUE(allow_incomplete), "Explicitly accept the interrupted/cancelled verified subset before import.")
  brohn_require(is.null(r$body$import_dataset_id), "This recording already has a prepared dataset.")
  r$body$review <- list(status="queued",allow_incomplete=isTRUE(allow_incomplete),confirmed_at=brohn_now(),original_hash=r$body$original$hash)
  brohn_put_entity(store,"acquisition",id,r$body,r$revision,r$project_id)
}
brohn_acquisition_download <- function(store, id) {
  r <- brohn_acquisition(store,id); brohn_require(!is.null(r$body$original), "The original recording is not preserved yet.")
  brohn_object_path(store,r$body$original$hash)
}
.brohn_acq_assert <- function(store, manager) {
  current <- brohn_get_entity(store,"acquisition_service","local")
  brohn_require(!is.null(current) && identical(current$body$manager_id,manager$id) &&
    identical(current$body$workspace_id,store$workspace_id) && identical(current$body$workspace_root,store$root) &&
    identical(brohn_hash(current$body$process),brohn_hash(manager$identity)), "This acquisition manager has lost its ownership fence.")
  invisible(current)
}
.brohn_acq_reconcile_discoveries <- function(store, manager) {
  .brohn_acq_assert(store,manager)
  # Select current running rows directly so a stale request cannot disappear
  # beyond the recent-history UI limit. All updates still use the public CAS API.
  ids<-DBI::dbGetQuery(store$con,paste("SELECT e.id FROM entities e JOIN entity_versions v ON",
    "v.kind=e.kind AND v.id=e.id AND v.revision=e.revision WHERE e.kind=? AND json_extract(v.body_json,'$.status')=?"),
    params=list("acquisition_discovery","running"))$id
  history<-brohn_entity_history(store,"acquisition_service","local")
  for(id in ids) {
    r<-brohn_get_entity(store,"acquisition_discovery",id);b<-r$body
    if(identical(b$manager_id,manager$id)) next
    owners<-Filter(function(h) identical(h$body$manager_id,b$manager_id) &&
      identical(h$body$workspace_id,store$workspace_id) && identical(h$body$workspace_root,store$root),history)
    execution_bound<-is.null(b$execution) || (identical(b$execution$manager_id,b$manager_id) &&
      identical(b$execution$workspace_id,store$workspace_id) && identical(b$execution$workspace_root,store$root))
    absent<-execution_bound && length(owners)>0 && identical(.brohn_acq_probe(owners[[1L]]$body$process),"absent")
    b$status<-if(absent) "interrupted" else "attention_required"
    b$error<-if(absent) "The previous local manager exited during metadata discovery. No sources were rescanned. Retry these sources or use Find local sources." else
      "The previous discovery owner or workspace could not be verified. No sources were rescanned. Review the source scope and use Find local sources explicitly."
    b$recovery<-list(at=brohn_now(),manager_id=manager$id,previous_manager_id=b$manager_id,workspace_id=store$workspace_id,
      owner_status=if(absent) "absent" else "unverified",automatic_rescan=FALSE)
    brohn_put_entity(store,"acquisition_discovery",r$id,b,r$revision,r$project_id)
  }
  invisible(NULL)
}
brohn_acquisition_manager <- function(store) {
  brohn_initialise_library(store)
  brohn_store_batch(store,function() {
    previous <- brohn_get_entity(store,"acquisition_service","local")
    if (!is.null(previous) && !identical(previous$body$status,"stopped"))
      brohn_require(identical(.brohn_acq_probe(previous$body$process),"absent"), "An existing or uncertain acquisition manager owns this workspace; resolve it before launching another.")
    state <- new.env(parent=emptyenv()); state$id <- brohn_id("manager"); state$children <- list(); state$stopped <- FALSE
    state$identity <- .brohn_acq_process()
    body <- list(manager_id=state$id,workspace_id=store$workspace_id,workspace_root=store$root,process=state$identity,status="running",started_at=brohn_now())
    brohn_put_entity(store,"acquisition_service","local",body,if(is.null(previous)) 0L else previous$revision)
    .brohn_acq_reconcile_discoveries(store,state)
    .brohn_acq_reconcile_publications(store,state)
    .brohn_acq_atomic(c(body,list(updated_at=brohn_now(),updated_epoch=as.numeric(Sys.time()))),.brohn_acq_path(store,"service.json"))
    state
  })
}
.brohn_acq_read_service <- function(root) {
  # Only the atomic service-state handoff uses these retries. Scientific files,
  # receipts and recording evidence retain their existing strict read paths.
  path<-file.path(root,"acquisitions","service.json");maximum<-65536L;last_error<-NULL
  for(attempt in seq_len(10L)) {
    if(!file.exists(path)) return(list(status="missing",ready=FALSE,attempts=attempt,error="The acquisition service state is absent."))
    info<-file.info(path)
    if(isTRUE(info$isdir) || (!is.na(info$size) && info$size>maximum))
      return(list(status="invalid",ready=FALSE,attempts=attempt,error="The acquisition service state is not a bounded JSON file."))
    warnings<-character()
    bytes<-tryCatch(withCallingHandlers(readBin(path,"raw",n=maximum+1L),warning=function(w) {
      warnings<<-c(warnings,conditionMessage(w));invokeRestart("muffleWarning")
    }),error=identity)
    if(!inherits(bytes,"error")) {
      value<-tryCatch({
        brohn_require(length(bytes)<=maximum,"Acquisition service state exceeds its size bound.")
        text<-rawToChar(bytes);Encoding(text)<-"UTF-8";brohn_parse(text,maximum)
      },error=identity)
      if(inherits(value,"error")) return(list(status="invalid",ready=FALSE,attempts=attempt,
        error=paste("Acquisition service state is invalid:",conditionMessage(value))))
      return(list(status="read",ready=FALSE,attempts=attempt,value=value,error=NULL))
    }
    last_error<-paste(c(warnings,conditionMessage(bytes)),collapse="; ")
    if(attempt<10L) Sys.sleep(.02)
  }
  list(status="unavailable",ready=FALSE,attempts=10L,error=paste("Acquisition service state remains unreadable after bounded retries:",last_error))
}
brohn_acquisition_service_status <- function(root, workspace_id = NULL) {
  result<-.brohn_acq_read_service(root)
  if(!identical(result$status,"read")) return(result)
  value<-result$value
  schema_ok<-is.list(value) && brohn_valid_id(value$manager_id) && brohn_valid_id(value$workspace_id) &&
    brohn_text(value$workspace_root,4000) && brohn_text(value$status,40) && value$status %in% c("running","stopped") &&
    brohn_number(value$updated_epoch,0,1e12) && is.list(value$process) &&
    brohn_number(value$process$pid,1,.Machine$integer.max,TRUE) && brohn_number(value$process$created,0,1e12) &&
    brohn_text(value$process$exe,4000) && brohn_text(value$process$cwd,4000) && brohn_array(value$process$command)
  if(!schema_ok) {result$status<-"invalid";result$error<-"Acquisition service state has invalid ownership or schema fields.";return(result)}
  root_match<-identical(tolower(normalizePath(root,winslash="/",mustWork=FALSE)),tolower(value$workspace_root))
  if(!root_match || (!is.null(workspace_id)&&!identical(value$workspace_id,workspace_id))) {
    result$status<-"foreign_workspace";result$error<-"Acquisition service state belongs to a different workspace.";return(result)
  }
  if(identical(value$status,"stopped")) {result$status<-"stopped";result$error<-NULL;return(result)}
  result$owner_status<-.brohn_acq_probe(value$process)
  result$ready<-identical(result$owner_status,"owned_alive")
  result$status<-if(result$ready) "ready" else if(result$owner_status=="absent") "owner_absent" else "unverified_process"
  result$error<-if(result$ready) NULL else "Acquisition manager process identity is absent or could not be verified."
  result
}
brohn_acquisition_ready <- function(root, workspace_id = NULL) isTRUE(brohn_acquisition_service_status(root,workspace_id)$ready)
brohn_request_acquisition_manager_stop <- function(root, expected_pid) {
  status<-brohn_acquisition_service_status(root);value<-status$value
  brohn_require(isTRUE(status$ready) && brohn_number(expected_pid,1,.Machine$integer.max,TRUE) &&
    identical(as.numeric(value$process$pid),as.numeric(expected_pid)),
    paste("Only this runtime's verified acquisition manager may receive its stop request.",brohn_default(status$error,"")))
  safe <- brohn_valid_id(value$manager_id); brohn_require(safe,"Invalid acquisition manager identity.")
  control <- list(operation="stop",manager_id=value$manager_id,workspace_id=value$workspace_id,process_created=value$process$created)
  path <- file.path(root,"acquisitions",paste0("stop-",value$manager_id,".json"))
  if(file.exists(path)) brohn_require(identical(.brohn_acq_read(path,4096),control),"A different manager stop control already exists.") else .brohn_acq_atomic(control,path,FALSE)
  invisible(TRUE)
}
brohn_acquisition_stop_requested <- function(store, manager) {
  value <- .brohn_acq_read(.brohn_acq_path(store,paste0("stop-",manager$id,".json")),4096)
  !is.null(value) && identical(value$operation,"stop") && identical(value$manager_id,manager$id) &&
    identical(value$workspace_id,store$workspace_id) && brohn_number(value$process_created,0,1e12) &&
    # Epoch doubles may change by one ULP through the catalog/JSON encoders.
    # Match the already verified process-identity tolerance, with the unique
    # manager ID and exact workspace still independently bound above.
    abs(as.numeric(value$process_created)-as.numeric(manager$identity$created)) <= .001
}
.brohn_acq_directory <- function(store, record) .brohn_acq_path(store,"recordings",record$id)
.brohn_acq_run <- function(operation, request = NULL, recording = NULL, output, extra = character(), timeout = 120, checkpoint = NULL) {
  args <- c(.brohn_acq_script(),operation,"--output",output)
  if (!is.null(request)) args <- c(args,"--request",request)
  if (!is.null(recording)) args <- c(args,"--recording",recording)
  if (is.null(checkpoint)) process <- processx::run(.brohn_acq_python(),c(args,extra),timeout=timeout,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE) else {
    out <- paste0(output,".stdout"); err <- paste0(output,".stderr")
    child <- processx::process$new(.brohn_acq_python(),c(args,extra),stdout=out,stderr=err,cleanup_tree=TRUE,windows_hide_window=TRUE)
    on.exit(if(child$is_alive()){child$kill_tree();child$wait(3000)},add=TRUE)
    start <- as.numeric(Sys.time())
    while(child$is_alive()) {child$wait(100);checkpoint();brohn_require(as.numeric(Sys.time())-start <= timeout,
      "The acquisition helper exceeded its time limit. The original source is preserved.")}
    checkpoint(TRUE)
    process <- list(status=child$get_exit_status(),timeout=FALSE,stderr=paste(head(readLines(err,warn=FALSE),10L),collapse="\n"))
  }
  brohn_require(!isTRUE(process$timeout), paste("The acquisition helper exceeded its", timeout, "second time limit. The original source is preserved."))
  result <- .brohn_acq_read(output,16*1024^2)
  brohn_require(!is.null(result) && process$status==0 && !identical(result$status,"error"),
    paste("Acquisition operation needs attention:",brohn_default(result$error$message,substr(process$stderr,1,2000))))
  result
}
.brohn_acq_walk <- function(directory) {
  root <- normalizePath(directory,winslash="/",mustWork=TRUE); queue <- root; paths <- character()
  while(length(queue)) {
    path <- queue[[1L]]; queue <- queue[-1L]
    for(entry in list.files(path,full.names=TRUE,all.files=TRUE,no..=TRUE)) {
      link <- Sys.readlink(entry); resolved <- normalizePath(entry,winslash="/",mustWork=TRUE)
      brohn_require((is.na(link)||!nzchar(link)) && startsWith(tolower(resolved),paste0(tolower(root),"/")),"Original acquisition contains a linked or escaping member.")
      if(dir.exists(entry)) queue <- c(queue,resolved) else paths <- c(paths,resolved)
    }
    brohn_require(length(paths)+length(queue)<=100100,"Original acquisition inventory is too large.")
  }
  paths
}
.brohn_acq_preserve <- function(store, record, scratch, checkpoint = function(...) invisible(NULL)) {
  directory <- .brohn_acq_directory(store,record)
  inspection <- .brohn_acq_run("inspect",recording=directory,output=file.path(scratch,"inspection.json"),checkpoint=checkpoint)
  brohn_require(identical(inspection$recording_id,record$id) && identical(brohn_hash(inspection$request),record$body$request_hash),"The recorded request differs from its frozen catalog request.")
  brohn_require(identical(inspection$evidence$engine$script_sha256,record$body$script_hash),"Recorder code differs from the reviewed acquisition request.")
  paths <- .brohn_acq_walk(directory)
  members <- substring(paths,nchar(normalizePath(directory,winslash="/"))+2L)
  brohn_require(!anyDuplicated(members) && sum(file.info(paths)$size) <= 700*1024^2,"Original recording exceeds the archival profile.")
  inventory <- lapply(seq_along(paths),function(i) {checkpoint();list(path=members[[i]],hash=.brohn_acq_hash(paths[[i]]),size=file.info(paths[[i]])$size)})
  archive <- file.path(scratch,"original-recording.brohn-acquisition.zip")
  zip::zipr(archive,members,root=directory,mode="mirror",recurse=FALSE,include_directories=FALSE,compression_level=1)
  checkpoint(TRUE); archive_hash <- .brohn_acq_hash(archive)
  listing <- zip::zip_list(archive)
  brohn_require(setequal(listing$filename,members) && !anyDuplicated(listing$filename),"Archived recording inventory differs from original evidence.")
  # A short fresh path avoids legacy Windows ZIP extraction path limits.
  verified <- tempfile("brohn-acq-verify-"); dir.create(verified)
  on.exit({
    canonical <- normalizePath(verified,winslash="/",mustWork=TRUE)
    brohn_require(identical(dirname(canonical),normalizePath(tempdir(),winslash="/",mustWork=TRUE)) && startsWith(basename(canonical),"brohn-acq-verify-"),"Refusing cleanup outside verified acquisition scratch.")
    .brohn_acq_walk(canonical); unlink(canonical,recursive=TRUE,force=TRUE)
  },add=TRUE)
  zip::unzip(archive,exdir=verified)
  for(i in seq_along(inventory)) {checkpoint();brohn_require(identical(.brohn_acq_hash(file.path(verified,inventory[[i]]$path)),inventory[[i]]$hash) &&
    identical(.brohn_acq_hash(paths[[i]]),inventory[[i]]$hash),"Original bytes changed during archive publication.")}
  brohn_require(identical(.brohn_acq_hash(archive),archive_hash),"The verified original archive changed during preparation.")
  checkpoint(TRUE); list(archive=archive,archive_hash=archive_hash,inspection=inspection,inventory=inventory)
}
# Acquisition publication uses the common job/native-seal contract, with jobs
# reserved for the independent manager rather than the scientific worker queue.
.brohn_acq_reconcile_publications <- function(store, manager) {
  .brohn_acq_assert(store,manager)
  ids <- DBI::dbGetQuery(store$con,"SELECT id FROM jobs WHERE operation IN ('acquisition_preserve','acquisition_prepare') AND status IN ('queued','running')")$id
  for(id in ids) {
    job <- brohn_get_job(store,id)
    owner <- job$request$owner
    brohn_require(identical(owner$workspace_id,store$workspace_id) && identical(owner$workspace_root,store$root) &&
      identical(.brohn_acq_probe(owner$process),"absent"),"An acquisition publication owner is still alive or uncertain; its attempt was retained.")
    brohn_cancel_job(store,job$id)
    .brohn_store_audit(store,"acquisition.publication_recovered",job$id,list(previous_manager_id=owner$manager_id,
      manager_id=manager$id,source_preserved=TRUE,policy="proven_absent_owner_new_fenced_attempt"))
  }
  invisible(NULL)
}
.brohn_acq_publication_owner <- function(store, record, manager, job = NULL) {
  service <- .brohn_acq_assert(store,manager)
  brohn_require(!isTRUE(manager$stopped) && identical(service$body$status,"running"),"This acquisition publication manager has stopped.")
  brohn_require(identical(.brohn_acq_probe(manager$identity),"owned_alive"),"The acquisition publication manager process cannot be verified.")
  current <- brohn_acquisition(store,record$id)
  brohn_require(identical(current$revision,record$revision) && identical(brohn_hash(current$body),brohn_hash(record$body)),
    "The acquisition changed during publication; its complete source is retained for a new review.")
  if(!is.null(job)) {
    .brohn_publication_job(store,job)
    brohn_require(identical(job$request$owner$manager_id,manager$id) && identical(job$request$acquisition_hash,brohn_hash(record$body)),
      "This publication belongs to another acquisition owner or revision.")
    brohn_require(identical(brohn_hash(job$request$implementation),brohn_hash(.brohn_acq_publication_code)) &&
      all(vapply(names(.brohn_acq_publication_code),function(path)identical(.brohn_acq_hash(path),.brohn_acq_publication_code[[path]]),logical(1))),
      "Acquisition publication implementation changed; restart the manager and retry from the retained source.")
  }
  invisible(current)
}
.brohn_acq_publication_job <- function(store, record, manager, operation) {
  brohn_require(operation %in% c("acquisition_preserve","acquisition_prepare"),"Unsupported acquisition publication operation.")
  brohn_require(.Platform$OS.type=="windows","Acquisition staged publication currently requires the qualified Windows native guard.")
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Prepare acquisition evidence outside the metadata transaction.")
  brohn_require(all(vapply(names(.brohn_acq_publication_code),function(path)
    identical(.brohn_acq_hash(path),.brohn_acq_publication_code[[path]]),logical(1))),"Restart the acquisition manager after source changes.")
  request <- list(schema="brohn-acquisition-publication/1.0",acquisition_id=record$id,acquisition_revision=record$revision,
    acquisition_hash=brohn_hash(record$body),project_id=record$project_id,implementation=.brohn_acq_publication_code,
    owner=list(manager_id=manager$id,process=manager$identity,workspace_id=store$workspace_id,workspace_root=store$root))
  brohn_store_batch(store,function() {
    .brohn_acq_publication_owner(store,record,manager)
    job <- brohn_enqueue_job(store,operation,request,paste0("acquisition-publication:",brohn_hash(request),":",brohn_id("attempt")))
    # The queue insertion and exact-id claim are invisible to other writers
    # until this transaction commits. Generic workers exclude both operations.
    changed <- DBI::dbExecute(store$con,"UPDATE jobs SET status='running',attempt=1,worker=?,token='1',lease_until=?,updated_at=? WHERE id=? AND status='queued'",
      params=list(manager$id,as.numeric(Sys.time())+300,.brohn_store_stamp(),job$id))
    brohn_require(changed==1L,"The acquisition publication could not acquire its exact job fence.")
    .brohn_store_audit(store,"job.claimed",job$id,list(attempt=1L,worker=manager$id,reclaimed=FALSE,owner="acquisition_manager"))
    brohn_get_job(store,job$id)
  })
}
.brohn_acq_publication_checkpoint <- function(store,record,manager,job) {
  check <- .brohn_publication_checkpoint(store,job); last <- 0
  function(force=FALSE) {
    check(force);now<-as.numeric(Sys.time())
    if(force || now-last>=1) {.brohn_acq_publication_owner(store,record,manager,job);last<<-now}
    invisible(TRUE)
  }
}
.brohn_acq_publication_failure <- function(store,job,error) {
  tryCatch(brohn_fail_job(store,job$id,job$worker,job$token,list(message=substr(conditionMessage(error),1,4000),source_preserved=TRUE)),error=function(e)NULL)
  stop(error)
}
.brohn_acq_publish_preservation <- function(store,record,manager,scratch) {
  job <- .brohn_acq_publication_job(store,record,manager,"acquisition_preserve")
  checkpoint <- .brohn_acq_publication_checkpoint(store,record,manager,job)
  archive <- document <- NULL; committed <- FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);if(!is.null(archive))brohn_close_publication(archive$guard,committed)},add=TRUE)
  tryCatch({
    brohn_require(identical(.brohn_acq_probe(record$body$process),"absent"),"Wait for the exact recorder process to exit before preserving it.")
    preserved <- .brohn_acq_preserve(store,record,scratch,checkpoint)
    archive <- .brohn_publication_stage(store,job,list(list(key="original-acquisition",kind="original-acquisition",path=preserved$archive,
      sha256=preserved$archive_hash,bytes=as.numeric(file.info(preserved$archive)$size),media_type="application/zip")))
    b <- record$body
    b$original <- archive$descriptors[[1L]][c("hash","size","media_type")]
    b$original_inventory <- preserved$inventory;b$inspection <- preserved$inspection;b$completion_status <- preserved$inspection$completion_status
    b$status <- b$completion_status;b$preserved_at <- brohn_now();b$error <- NULL
    b$preservation <- list(schema="brohn-acquisition-preservation/1.0",job_id=job$id,source_revision=record$revision,
      source_hash=job$request$acquisition_hash,owner=job$request$owner,implementation=.brohn_acq_publication_code,
      publication=.brohn_publication_processing(archive))
    document <- .brohn_publication_stage_json(store,job,list(schema="brohn-acquisition-preservation-result/1.0",acquisition=b),
      file.path(scratch,"preservation-publication.json"));checkpoint(TRUE)
    result <- brohn_store_batch(store,function() {
      .brohn_acq_publication_owner(store,record,manager,job)
      .brohn_publication_register(store,archive)
      b$preservation$result_object <- .brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
      saved <- brohn_put_entity(store,"acquisition",record$id,b,record$revision,record$project_id)
      brohn_complete_job(store,job$id,job$worker,job$token,list(acquisition_id=record$id,acquisition_revision=saved$revision,
        original_hash=b$original$hash,result_hash=b$preservation$result_object$hash))
      saved
    })
    committed<-TRUE;result
  },error=function(e).brohn_acq_publication_failure(store,job,e))
}
.brohn_acq_extract_original <- function(path,inventory,checkpoint) {
  members <- vapply(inventory,`[[`,character(1),"path")
  listing <- zip::zip_list(path)
  brohn_require(length(members)>0 && !anyDuplicated(members) && setequal(listing$filename,members) &&
    !anyDuplicated(listing$filename) && !any(grepl("(^[/\\\\]|^[A-Za-z]:|(^|[/\\\\])\\.\\.([/\\\\]|$))",members)),
    "The preserved recording archive has an unsafe or changed inventory.")
  directory <- tempfile("brohn-acq-review-");dir.create(directory);success<-FALSE
  on.exit(if(!success).brohn_acq_remove_extraction(directory),add=TRUE)
  zip::unzip(path,exdir=directory);checkpoint(TRUE)
  for(item in inventory) {checkpoint();member<-file.path(directory,item$path)
    brohn_require(file.exists(member) && !dir.exists(member) && file.info(member)$size==item$size && identical(.brohn_acq_hash(member),item$hash),
      "The extracted recording differs from its complete preserved inventory.")}
  .brohn_acq_walk(directory);success<-TRUE;directory
}
.brohn_acq_remove_extraction <- function(directory) {
  canonical<-normalizePath(directory,winslash="/",mustWork=TRUE)
  brohn_require(identical(dirname(canonical),normalizePath(tempdir(),winslash="/",mustWork=TRUE)) && startsWith(basename(canonical),"brohn-acq-review-"),
    "Refusing cleanup outside the owned recording extraction.")
  .brohn_acq_walk(canonical);unlink(canonical,recursive=TRUE,force=TRUE);invisible(NULL)
}
.brohn_acq_publish_review <- function(store,record,manager,scratch) {
  job <- .brohn_acq_publication_job(store,record,manager,"acquisition_prepare")
  checkpoint <- .brohn_acq_publication_checkpoint(store,record,manager,job)
  original <- bundle <- document <- extracted <- NULL;committed<-FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);if(!is.null(bundle))brohn_close_publication(bundle$guard,committed)
    if(!is.null(original))brohn_close_publication(original$guard,committed);if(!is.null(extracted)).brohn_acq_remove_extraction(extracted)},add=TRUE)
  tryCatch({
    b<-record$body
    brohn_require(identical(b$review$status,"queued") && identical(b$review$original_hash,b$original$hash),"Review refers to another original recording.")
    original_path<-brohn_object_path(store,b$original$hash,verify=FALSE)
    original<-.brohn_publication_stage(store,job,list(list(key="retained-original",kind="retained-original",path=original_path,
      sha256=b$original$hash,bytes=b$original$size,media_type="application/zip")))
    extracted<-.brohn_acq_extract_original(original$paths[["retained-original"]],b$original_inventory,checkpoint)
    output<-file.path(scratch,"stream-bundle.json")
    receipt<-.brohn_acq_run("export-bundle",recording=extracted,output=file.path(scratch,"export.json"),
      extra=c("--bundle-output",output,if(isTRUE(b$review$allow_incomplete))"--allow-incomplete"),checkpoint=checkpoint)
    brohn_require(identical(receipt$parent_journal_tip,b$inspection$journal_tip) && identical(receipt$sha256,.brohn_acq_hash(output)),
      "Export differs from the preserved original journal.")
    size<-as.numeric(file.info(output)$size);brohn_require(brohn_number(size,1,512*1024^2,TRUE),"The stream bundle exceeds its supported source limit.")
    bundle<-.brohn_publication_stage(store,job,list(list(key="stream-bundle",kind="acquisition-export",path=output,sha256=receipt$sha256,
      bytes=size,media_type="application/json")));checkpoint(TRUE)
    source<-c(bundle$descriptors[[1L]][c("hash","size","media_type")],list(filename="stream-bundle.json",format="json"))
    dataset_id<-brohn_id("dataset");dependent_id<-.brohn_store_id(store$con,"job")
    data<-list(schema_version="brohn-dataset/1.0.0",id=dataset_id,title=paste(b$title,"streams"),modality="multimodal",origin=b$origin,
      study_id=b$study_id,study_revision=b$study_revision,source=source,columns=list(),preview=list(),
      metadata=list(origin_statement=b$request$origin_statement,clock_policy="preserve_only"),status="accepted",data_revision=1L,notes="",
      source_provenance=list(imported_at=brohn_now(),source_hash=source$hash,parent_acquisition=list(id=record$id,original=b$original,
        journal_tip=b$inspection$journal_tip,completion_status=b$completion_status)))
    brohn_validate_dataset_mapping(data);brohn_validate_interchange_mapping(data)
    study<-brohn_study(store,b$study_id,b$study_revision)
    brohn_require(identical(study$project_id,record$project_id) && identical(brohn_hash(study$body),b$design_hash),"The frozen acquisition study is no longer available in this project.")
    request<-list(dataset_id=dataset_id,dataset_revision=1L,dataset_hash=brohn_hash(data),source_hash=source$hash,
      project_id=record$project_id,recipe="multistream-preservation/1.0.0")
    b$review$status<-"prepared";b$review$error<-NULL;b$import_dataset_id<-dataset_id;b$import_job_id<-dependent_id
    b$review$publication<-list(job_id=job$id,source_revision=record$revision,source_hash=job$request$acquisition_hash,
      owner=job$request$owner,implementation=.brohn_acq_publication_code,publication=.brohn_publication_processing(bundle))
    document<-.brohn_publication_stage_json(store,job,list(schema="brohn-acquisition-review-result/1.0",acquisition=b,dataset=data,
      dependent_job=list(id=dependent_id,request=request)),file.path(scratch,"review-publication.json"));checkpoint(TRUE)
    result<-brohn_store_batch(store,function() {
      .brohn_acq_publication_owner(store,record,manager,job)
      .brohn_publication_register(store,original);.brohn_publication_register(store,bundle)
      b$review$publication$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
      dataset<-brohn_put_entity(store,"dataset",dataset_id,data,project_id=record$project_id)
      dependent<-brohn_enqueue_job(store,"normalise_dataset",request,paste0("multistream:",brohn_hash(request)),prepared_id=dependent_id)
      brohn_require(identical(dependent$id,dependent_id),"The acquisition export's frozen processing identity changed.")
      saved<-brohn_put_entity(store,"acquisition",record$id,b,record$revision,record$project_id)
      brohn_complete_job(store,job$id,job$worker,job$token,list(acquisition_id=record$id,acquisition_revision=saved$revision,
        dataset_id=dataset_id,dependent_job_id=dependent_id,result_hash=b$review$publication$result_object$hash))
      saved
    })
    committed<-TRUE;result
  },error=function(e).brohn_acq_publication_failure(store,job,e))
}
.brohn_acq_update <- function(store, record, body, manager) brohn_store_batch(store,function() {
  .brohn_acq_assert(store,manager)
  brohn_put_entity(store,"acquisition",record$id,body,record$revision,record$project_id)
})
brohn_acquisition_tick <- function(store, manager) {
  if(isTRUE(manager$stopped)) return(invisible(NULL))
  service <- .brohn_acq_assert(store,manager)
  .brohn_acq_atomic(c(service$body,list(updated_at=brohn_now(),updated_epoch=as.numeric(Sys.time()))),.brohn_acq_path(store,"service.json"))
  work <- .brohn_acq_path(store,"work"); if(!dir.exists(work)) dir.create(work)
  active <- brohn_acquisitions(store, status = c("queued","starting","recording","stopping","attention_required"))
  brohn_require(length(active)<=1L,"Multiple unresolved recordings require manual review; no new writer was started.")
  if(length(active)) {
    r <- active[[1L]]; b <- r$body
    if(identical(b$status,"attention_required") && isTRUE(b$writer_exited)) return(invisible(NULL))
    if(b$status=="queued") {
      brohn_require(identical(b$request_hash,brohn_hash(b$request)) && identical(b$script_hash,.brohn_acq_hash(.brohn_acq_script())),"Frozen recording request or recorder code changed.")
      request_path <- file.path(work,paste0(r$id,"-request.json")); brohn_require(!file.exists(request_path),"A prior launch request exists; inspect it before starting another writer.")
      .brohn_acq_atomic(b$request,request_path,FALSE)
      b$status <- "starting"; b$manager_id <- manager$id; b$request_path <- request_path; b$request_file_hash <- .brohn_acq_hash(request_path)
      b$receipt_path <- file.path(work,paste0(r$id,"-receipt.json")); b$launch_started_at <- brohn_now()
      r <- .brohn_acq_update(store,r,b,manager)
      child <- processx::process$new(.brohn_acq_python(),c(.brohn_acq_script(),"record","--request",request_path,"--output",b$receipt_path),
        stdout=file.path(work,paste0(r$id,".stdout.txt")),stderr=file.path(work,paste0(r$id,".stderr.txt")),windows_hide_window=TRUE,cleanup_tree=TRUE)
      manager$children[[r$id]] <- child
      process_identity <- .brohn_acq_process(child$get_pid())
      # A concurrent stop action must not discard the child identity after spawn.
      r <- brohn_store_batch(store,function() {
        .brohn_acq_assert(store,manager); current <- brohn_acquisition(store,r$id); body <- current$body
        brohn_require(identical(body$request_hash,b$request_hash),"Recording identity changed during launch.")
        body$process <- process_identity
        brohn_put_entity(store,"acquisition",current$id,body,current$revision,current$project_id)
      })
    }
    b <- r$body; probe <- .brohn_acq_probe(b$process)
    if(probe=="unknown") {
      if(!identical(b$status,"attention_required")) {
        b$status <- "attention_required"; b$error <- "Writer ownership is uncertain. Original data are retained; no replacement is launched. Review the exact local process before recovery."
        .brohn_acq_update(store,r,b,manager)
      }
      return(invisible(NULL))
    }
    directory <- .brohn_acq_directory(store,r)
    if(probe=="owned_alive") {
      brohn_require(identical(.brohn_acq_hash(b$request_path),b$request_file_hash),"Writer request file changed; no control was sent.")
      snapshot <- .brohn_acq_read(file.path(directory,"status.json"),2*1024^2)
      if(!is.null(snapshot)) {
        brohn_require(identical(snapshot$recording_id,r$id),"Writer status belongs to another recording.")
        b$python_request_hash <- snapshot$request_sha256
        if(is.null(b$control)) b$status <- "recording"
        if(!is.null(b$control)) {
          control <- list(recording_id=r$id,request_sha256=snapshot$request_sha256,operation=b$control)
          path <- file.path(directory,"control.json")
          if(!file.exists(path)) .brohn_acq_atomic(control,path,FALSE) else brohn_require(identical(.brohn_acq_read(path),control),"A different stop control already exists; it was not replaced.")
        }
        # Raw status stays in the atomic polling file. Do not create immutable
        # entity revisions for every sample-count update.
        if(!identical(b$status,r$body$status) || is.null(r$body$python_request_hash)) .brohn_acq_update(store,r,b,manager)
      }
      return(invisible(NULL))
    }
    # Known writer exited: inspection never creates a replacement or repairs a
    # false completion marker. A missing/invalid journal is retained for review.
    scratch <- tempfile(paste0("preserve-",r$id,"-"),tmpdir=work); dir.create(scratch)
    preserved <- tryCatch(.brohn_acq_publish_preservation(store,r,manager,scratch),error=identity)
    if(inherits(preserved,"error")) {
      b$status <- "attention_required"; b$error <- conditionMessage(preserved); b$writer_exited <- TRUE
      .brohn_acq_update(store,r,b,manager); return(invisible(NULL))
    }
    return(invisible(NULL))
  }
  discoveries <- brohn_lsl_discoveries(store, status = "queued")
  if(length(discoveries)) {
    d <- discoveries[[1L]]; b <- d$body
    scratch <- tempfile(paste0("discovery-",d$id,"-"),tmpdir=work); dir.create(scratch)
    request <- file.path(scratch,"request.json"); brohn_write_json_file(b$request,request)
    b$status <- "running"; b$manager_id <- manager$id
    b$execution<-list(id=brohn_id("discovery-run"),manager_id=manager$id,manager_process=manager$identity,
      workspace_id=store$workspace_id,workspace_root=store$root,started_at=brohn_now(),request_path=request,
      request_file_hash=.brohn_acq_hash(request),receipt_path=file.path(scratch,"result.json"),script_hash=b$script_hash)
    d <- brohn_put_entity(store,"acquisition_discovery",d$id,b,d$revision,d$project_id)
    result <- tryCatch({
      brohn_require(identical(b$request_hash,brohn_hash(b$request)) && identical(b$script_hash,.brohn_acq_hash(.brohn_acq_script())),
        "The saved discovery request or recorder changed. Use Find local sources to review the current version.")
      result<-.brohn_acq_run("discover",request=request,output=b$execution$receipt_path)
      brohn_require(identical(result$schema,"brohn-lsl-discovery/1.0") && isTRUE(result$metadata_only) && identical(result$engine$script_sha256,b$script_hash),"Discovery identity is invalid.")
      result
    },error=identity)
    b$execution$finished_at<-brohn_now()
    if(inherits(result,"error")) {b$status <- "failed"; b$error <- conditionMessage(result)} else {
      b$status <- "ready"; b$result <- result; b$result_hash <- brohn_hash(result)
      b$result_object <- brohn_store_object(store,path=file.path(scratch,"result.json"),media_type="application/json")
    }
    .brohn_acq_assert(store,manager); brohn_put_entity(store,"acquisition_discovery",d$id,b,d$revision,d$project_id)
    return(invisible(NULL))
  }
  reviews <- brohn_acquisitions(store, review_status = "queued")
  if(length(reviews)) {
    r <- reviews[[1L]]; b <- r$body
    result <- tryCatch({
      scratch <- tempfile(paste0("import-",r$id,"-"),tmpdir=work); dir.create(scratch)
      .brohn_acq_publish_review(store,r,manager,scratch)
    },error=identity)
    if(inherits(result,"error")) {b$review$status <- "failed"; b$review$error <- conditionMessage(result); .brohn_acq_update(store,r,b,manager)}
  }
  invisible(NULL)
}
brohn_stop_acquisition_manager <- function(store, manager, timeout_seconds = 15) {
  if(isTRUE(manager$stopped)) return(invisible(NULL))
  # Stop intent targets the exact request, then lets the independent writer flush
  # and the manager preserve its complete original. Unknown processes stay alone.
  tryCatch({
    .brohn_acq_assert(store,manager)
    active <- brohn_acquisitions(store, status = c("queued","starting","recording","stopping"))
    for(r in active) if(is.null(r$body$control)) brohn_stop_acquisition(store,r$id,r$revision)
    deadline <- as.numeric(Sys.time())+timeout_seconds
    repeat {
      active <- brohn_acquisitions(store, status = c("starting","recording","stopping"))
      if(!length(active)||as.numeric(Sys.time())>=deadline) break
      tryCatch(brohn_acquisition_tick(store,manager),error=function(e) NULL)
      Sys.sleep(.05)
    }
  },error=function(e) NULL)
  manager$stopped <- TRUE
  # Timeout is an interrupted prefix, never a fabricated normal completion.
  for(child in manager$children) if(child$is_alive()) child$kill_tree()
  tryCatch(brohn_store_batch(store,function() {
    current <- .brohn_acq_assert(store,manager); body <- current$body; body$status <- "stopped"
    brohn_put_entity(store,"acquisition_service","local",body,current$revision)
    .brohn_acq_atomic(c(body,list(updated_at=brohn_now(),updated_epoch=as.numeric(Sys.time()))),.brohn_acq_path(store,"service.json"))
  }),error=function(e) NULL)
  invisible(NULL)
}
