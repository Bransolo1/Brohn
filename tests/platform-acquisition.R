# Original local synthetic outlet, isolated manager processes and temporary store.
source("R/platform-load.R",encoding="UTF-8"); brohn_load(ui=FALSE)
source("R/platform-acquisition.R",encoding="UTF-8")
local({
  checks <- 0L
  check <- function(name,ok) {if(!isTRUE(ok)) stop(paste("Acquisition QA failed:",name),call.=FALSE); checks <<- checks+1L}
  rejected <- function(value) inherits(try(force(value),silent=TRUE),"try-error")
  until <- function(fn,timeout=30) {
    end <- as.numeric(Sys.time())+timeout
    repeat {if(isTRUE(fn())) return(TRUE); if(as.numeric(Sys.time())>=end) return(FALSE); Sys.sleep(.05)}
  }
  root <- tempfile("brohn-acquisition-r-qa-"); dir.create(root); root <- normalizePath(root,winslash="/")
  store <- brohn_open_store(file.path(root,"workspace")); brohn_initialise_library(store)
  children <- list(); manager <- NULL
  on.exit({
    for(child in children) if(child$is_alive()) {child$kill_tree(); child$wait(5000)}
    brohn_close_store(store)
    actual <- normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),grepl("^brohn-acquisition-r-qa-",basename(actual)))
    unlink(actual,recursive=TRUE,force=TRUE)
  },add=TRUE)
  session <- brohn_id("synthetic"); source_id <- brohn_id("source")
  config <- file.path(root,"lsl.cfg")
  writeLines(c("[multicast]","ResolveScope = machine","[lab]","KnownPeers = {127.0.0.1}",paste("SessionID =",session)),config)
  fixture <- file.path(root,"original-outlet.py")
  writeLines(c("import os,time,json", "from pathlib import Path", "import pylsl",
    "info=pylsl.StreamInfo('Brohn original R QA','EDA',1,50,'double64',os.environ['BROHN_QA_SOURCE'])",
    "info.desc().append_child_value('origin','synthetic')",
    "c=info.desc().append_child('channels').append_child('channel')",
    "c.append_child_value('label','original_eda'); c.append_child_value('unit','uS'); c.append_child_value('type','EDA')",
    "outlet=pylsl.StreamOutlet(info,chunk_size=1,max_buffered=5)",
    "Path(os.environ['BROHN_QA_READY']).write_text('original outlet ready')",
    "i=0",
    "while True:",
    "    if outlet.have_consumers():",
    "        outlet.push_sample([float(i%5)],timestamp=pylsl.local_clock()); i+=1",
    "    time.sleep(.02)"),fixture)
  outlet <- processx::process$new(.brohn_acq_python(),fixture,
    env=c("current",LSLAPICFG=config,BROHN_QA_SOURCE=source_id,BROHN_QA_READY=file.path(root,"outlet-ready")),
    stdout=file.path(root,"outlet.stdout"),stderr=file.path(root,"outlet.stderr"),windows_hide_window=TRUE,cleanup_tree=TRUE)
  children[[length(children)+1L]] <- outlet
  check("original isolated synthetic outlet starts",until(function() file.exists(file.path(root,"outlet-ready"))))
  start_manager <- function(label) {
    process <- processx::process$new(brohn_rscript(),c("--vanilla","scripts/run-acquisition.R","--root",store$root),
      env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),
      stdout=file.path(root,paste0(label,".stdout")),stderr=file.path(root,paste0(label,".stderr")),windows_hide_window=TRUE,cleanup_tree=TRUE)
    children[[length(children)+1L]] <<- process
    check(paste(label,"manager ready with owned process identity"),until(function() brohn_acquisition_ready(store$root)))
    process
  }
  manager <- start_manager("first")
  study <- brohn_create_study(store,"Original acquisition R acceptance")
  discovery <- brohn_queue_lsl_discovery(store,study$id,session,source_id)
  check("discovery uses dedicated entity queue",length(brohn_list_jobs(store))==0 && discovery$body$status=="queued")
  check("actual manager completes metadata-only discovery",until(function() brohn_get_entity(store,"acquisition_discovery",discovery$id)$body$status %in% c("ready","failed")))
  discovery <- brohn_get_entity(store,"acquisition_discovery",discovery$id)
  if(discovery$body$status!="ready") stop(brohn_json(discovery$body))
  check("discovery source metadata stored immutably",isTRUE(discovery$body$result$metadata_only) && length(discovery$body$result$streams)==1 &&
    identical(.brohn_acq_hash(brohn_object_path(store,discovery$body$result_object$hash)),discovery$body$result_object$hash))
  observed <- discovery$body$result$streams[[1L]]
  channels <- list(list(id="eda",label="Original EDA",type="EDA",unit="uS",value_type="float64"))
  selected <- brohn_lsl_selection(discovery,observed$uid,"eda","declared-eda-clock","monotonic","signal",channels,"Original synthetic outlet declaration",.1)
  limits <- list(max_duration_s=30,max_samples=10000,max_bytes=4*1024^2,chunk_samples=32,inlet_buffer=2)
  identity <- list(participant_id="explicit-P1",session_id="explicit-S1")
  queue <- function(revision=study$revision,origin="sample",reviewed=TRUE) brohn_queue_acquisition(store,study$id,discovery$id,list(selected),identity,origin,
    "Original synthetic acceptance data only.",limits,revision,reviewed)
  check("review confirmation required",rejected(queue(reviewed=FALSE)))
  check("source sample origin cannot be relabelled live",rejected(queue(origin="live")))
  check("stale study revision rejected",rejected(queue(revision=study$revision+1)))
  record <- queue()
  check("second active recording rejected atomically",rejected(queue()))
  check("recording does not consume analysis job queue",length(brohn_list_jobs(store))==0)
  check("real recording reaches samples",until(function() {r <- brohn_acquisition(store,record$id); !is.null(r$live_snapshot) && r$live_snapshot$samples>=10}))
  record <- brohn_acquisition(store,record$id)
  check("frozen explicit identities and source units retained",identical(record$body$request$identity,identity) && identical(record$body$request$streams[[1L]]$channels,channels))
  check("writer request hash command and cwd identify owned child",identical(.brohn_acq_probe(record$body$process),"owned_alive") &&
    identical(.brohn_acq_hash(record$body$request_path),record$body$request_file_hash) && identical(record$body$process$cwd,normalizePath(".",winslash="/")))
  check("stale stop CAS rejected",rejected(brohn_stop_acquisition(store,record$id,0)))
  # Stop with a fresh revision; retries account for the manager's status refresh.
  check("exact recording stop accepted",until(function() {r<-brohn_acquisition(store,record$id); !rejected(brohn_stop_acquisition(store,r$id,r$revision))}))
  preserved <- until(function() !is.null(brohn_acquisition(store,record$id)$body$original),timeout=15)
  if(!preserved) cat(brohn_acquisition(store,record$id)$body$error,"\n")
  check("stopped recording original is archived",preserved)
  record <- brohn_acquisition(store,record$id)
  if (!isTRUE(record$body$completion_status == "completed" && record$body$inspection$samples >= 10 &&
      isTRUE(record$body$inspection$complete) && identical(record$body$inspection$quality_qualified, FALSE) &&
      identical(record$body$inspection$signal_quality,"not_qualified") && identical(record$body$inspection$quality_evidence,"verified_final_manifest")))
    cat("Completion evidence: ", brohn_json(list(completion_status = record$body$completion_status,
      inspection = record$body$inspection, live_snapshot = record$live_snapshot, error = record$body$error)), "\n", sep = "")
  check("completion distinct from unqualified signal quality",record$body$completion_status=="completed" && record$body$inspection$samples>=10 &&
    isTRUE(record$body$inspection$complete) && identical(record$body$inspection$quality_qualified,FALSE) &&
    identical(record$body$inspection$signal_quality,"not_qualified") && identical(record$body$inspection$quality_evidence,"verified_final_manifest"))
  archive <- brohn_acquisition_download(store,record$id); archive_hash <- .brohn_acq_hash(archive)
  listing <- zip::zip_list(archive)
  check("original archive contains full journal and every canonical source member",all(c("request.json","streams.json","journal.jsonl","manifest.json","control.json") %in% listing$filename) && any(startsWith(listing$filename,"chunks/")))
  extracted <- file.path(root,"downloaded-original"); dir.create(extracted); zip::unzip(archive,exdir=extracted)
  check("downloaded original bytes match complete hashed inventory",all(vapply(record$body$original_inventory,function(x)
    identical(.brohn_acq_hash(file.path(extracted,x$path)),x$hash),logical(1))))
  check("no import occurs before explicit review",length(brohn_list_entities(store,"dataset"))==0)
  reviewed <- brohn_review_acquisition(store,record$id,record$revision)
  check("review queues existing multistream pipeline",until(function() {r<-brohn_acquisition(store,record$id); !is.null(r$body$import_job_id)||identical(r$body$review$status,"failed")}))
  record <- brohn_acquisition(store,record$id)
  if(is.null(record$body$import_job_id)) stop(brohn_json(record$body$review))
  dataset <- brohn_get_entity(store,"dataset",record$body$import_dataset_id)
  check("import keeps pinned design origin and immutable parent recording",dataset$body$status=="accepted" && dataset$body$origin=="sample" &&
    dataset$body$study_revision==study$revision && identical(dataset$body$source_provenance$parent_acquisition$original$hash,record$body$original$hash))
  check("normalisation is queued for independent analysis worker",brohn_get_job(store,record$body$import_job_id)$operation=="normalise_dataset")

  # A second manager must not take over the live manager's lease or process.
  duplicate <- processx::process$new(brohn_rscript(),c("--vanilla","scripts/run-acquisition.R","--root",store$root,"--once"),
    env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),stdout="|",stderr="|",windows_hide_window=TRUE,cleanup_tree=TRUE)
  children[[length(children)+1L]] <- duplicate; duplicate$wait(5000)
  check("duplicate manager fails without touching active owner",!duplicate$is_alive() && duplicate$get_exit_status()!=0 && manager$is_alive() && brohn_acquisition_ready(store$root))

  crash <- queue(); check("second explicit recording starts",until(function() {r<-brohn_acquisition(store,crash$id); !is.null(r$live_snapshot)&&r$live_snapshot$samples>=5}))
  crash <- brohn_acquisition(store,crash$id)
  # Kill only the test-owned manager process tree: real journal crash prefix.
  manager$kill_tree(); manager$wait(5000)
  check("test manager crash is isolated and actual",!manager$is_alive())
  manager <- start_manager("restarted")
  check("new manager preserves interrupted original without duplicate writer",until(function() !is.null(brohn_acquisition(store,crash$id)$body$original)))
  crash <- brohn_acquisition(store,crash$id)
  check("hard crash is honestly interrupted",crash$body$completion_status=="interrupted" && !isTRUE(crash$body$inspection$complete) && crash$body$inspection$samples>=5)
  check("hard crash never infers final quality from absent manifest",is.null(crash$body$inspection$quality_qualified) &&
    is.null(crash$body$inspection$signal_quality) && identical(crash$body$inspection$quality_evidence,"missing_final_manifest"))
  check("interrupted import requires explicit subset approval",rejected(brohn_review_acquisition(store,crash$id,crash$revision)))
  brohn_close_store(store); store <- brohn_open_store(file.path(root,"workspace"))
  reopened <- brohn_acquisition(store,record$id)
  check("restart and reopen retain original archive byte identity",identical(.brohn_acq_hash(brohn_acquisition_download(store,reopened$id)),archive_hash))
  check("process identity cannot be substituted by PID alone",identical(.brohn_acq_probe(modifyList(.brohn_acq_process(),list(cwd=root))),"unknown"))
  # Simulate the narrow crash gap after launch intent but before child identity
  # was persisted. Recovery must refuse a duplicate and keep the source intent.
  uncertain<-queue(); body<-uncertain$body;body$status<-"starting";body$manager_id<-"prior-manager";body$launch_started_at<-brohn_now()
  brohn_put_entity(store,"acquisition",uncertain$id,body,uncertain$revision,uncertain$project_id)
  check("ambiguous launch gap fails closed for explicit local review",until(function() identical(brohn_acquisition(store,uncertain$id)$body$status,"attention_required")))
  check("ambiguous ownership never starts a replacement writer",is.null(brohn_acquisition(store,uncertain$id)$body$process) && rejected(queue()))
  source("R/platform-acquisition-views.R",encoding="UTF-8")
  check("complete quality copy comes from immutable inspection",grepl("not qualified",brohn_acquisition_quality_text(record$body$inspection),fixed=TRUE))
  check("crash and legacy quality copy say final evidence unavailable",grepl("unavailable",brohn_acquisition_quality_text(crash$body$inspection),fixed=TRUE) &&
    grepl("unavailable",brohn_acquisition_quality_text(list(complete=TRUE)),fixed=TRUE))
  if(.Platform$OS.type=="windows") {
    check("unsupported workspace path rejected before metadata discovery",rejected(brohn_queue_lsl_discovery(list(root=paste0(store$root,"/",strrep("x",180))),study$id,session,source_id)))
    check("Windows path budget counts supplementary Unicode in UTF-16 units",rejected(.brohn_acq_check_path_budget(list(root=paste0("C:/",paste(rep(intToUtf8(0x1F600),80),collapse=""))))))
  }
  check("acquisition UI module exposes installer and card",is.function(brohn_acquisition_ui)&&is.function(brohn_install_acquisition_server))
  form_state<-list(page="study",stage="Collect",study_id=study$id)
  form_input<-list(study_form_identity=paste(study$id,"Collect",sep=":"))
  check("current study Collect form permits acquisition controls",brohn_acquisition_form_current(form_state,form_input))
  check("late controls from other page or stage fail closed",!brohn_acquisition_form_current(modifyList(form_state,list(page="home")),form_input) &&
    !brohn_acquisition_form_current(modifyList(form_state,list(stage="Plan")),form_input))
  check("previous study hidden form cannot control a newly selected study",!brohn_acquisition_form_current(modifyList(form_state,list(study_id="different-study")),form_input))
  check("missing form identity cannot start acquisition",!brohn_acquisition_form_current(form_state,list()))
  control_manager<-list(id=brohn_id("manager-test"),identity=list(created=1788841191.00869))
  control_path<-.brohn_acq_path(store,paste0("stop-",control_manager$id,".json"))
  stop_control<-list(operation="stop",manager_id=control_manager$id,workspace_id=store$workspace_id,
    process_created=control_manager$identity$created+.00000025)
  .brohn_acq_atomic(stop_control,control_path,FALSE)
  check("manager stop survives sub-microsecond JSON epoch rounding",brohn_acquisition_stop_requested(store,control_manager))
  .brohn_acq_atomic(modifyList(stop_control,list(manager_id="another-manager")),control_path)
  check("another manager's stop cannot be reused",!brohn_acquisition_stop_requested(store,control_manager))
  .brohn_acq_atomic(modifyList(stop_control,list(workspace_id="another-workspace")),control_path)
  check("another workspace's stop cannot be reused",!brohn_acquisition_stop_requested(store,control_manager))
  .brohn_acq_atomic(modifyList(stop_control,list(process_created=control_manager$identity$created+1)),control_path)
  check("different process creation rejects a stop",!brohn_acquisition_stop_requested(store,control_manager))
  cat(sprintf("Platform acquisition: %d scoped checks passed.\n",checks))
})
