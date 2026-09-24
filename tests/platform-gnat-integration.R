# Full R receiver/store/export/portability integration with an authored journal.
# Browser execution and actual automatic workers have separate acceptance.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
source("tests/fixtures/gnat-journal.R",encoding="UTF-8")
local({
  args<-commandArgs(trailingOnly=TRUE);folder<-if(length(args))args[[1L]]else tempfile("gni-",tmpdir=Sys.getenv("BROHN_QA_EVIDENCE_PARENT",tempdir()))
  stopifnot(!dir.exists(folder));dir.create(folder,recursive=TRUE);folder<-normalizePath(folder,winslash="/")
  store<-brohn_open_store(file.path(folder,"w"));other<-brohn_open_store(file.path(folder,"p"))
  on.exit({for(j in brohn_list_jobs(store,limit=100L))if(j$status=="queued")brohn_cancel_job(store,j$id)
    brohn_close_store(other);brohn_close_store(store)},add=TRUE)
  brohn_initialise_library(store);brohn_initialise_library(other)
  checks<-character();check<-function(label,x){if(!isTRUE(x))stop(label,call.=FALSE);checks<<-c(checks,label);cat("PASS",label,"\n")}
  same<-function(a,b)identical(brohn_hash(a),brohn_hash(b));rejects<-function(x)inherits(try(force(x),silent=TRUE),"try-error")
  files<-c("R/platform-gnat.R","R/platform-gnat-import.R","R/platform-methods.R","R/platform-delivery.R",
    "R/platform-task-import.R","R/platform-task-evidence.R","R/platform-task-cohort.R","R/platform-core.R",
    "R/platform-portability.R","tests/fixtures/gnat-journal.R","tests/platform-gnat-integration.R")
  hashes<-function()setNames(lapply(files,function(p)digest::digest(file=p,algo="sha256")),files)
  start_hashes<-hashes();brohn_write_json_file(start_hashes,file.path(folder,"source-start.json"))
  on.exit(if(!file.exists(file.path(folder,"results.json")))brohn_write_json_file(list(passed=FALSE,checks=as.list(checks),
    source_start=start_hashes,source_end=hashes()),file.path(folder,"failure-progress.json")),add=TRUE)
  task<-brohn_task_new("gnat-brohn-single-target/1.0",id="original-gnat-integration-task")
  design<-brohn_new_design("Original GNAT receiver integration","blank",id="original-gnat-integration-study")
  design$blocks<-list(task);brohn_put_entity(store,"study",design$id,design)
  release<-brohn_publish(store,design$id,origin="sample",quota=2L);app<-brohn_delivery_app(store)
  call<-function(route,payload,token=NULL){
    bytes<-charToRaw(.brohn_store_json(payload))
    req<-list(PATH_INFO=route,REQUEST_METHOD="POST",HTTP_HOST="127.0.0.1:3840",HTTP_ORIGIN="http://127.0.0.1:3840",
      CONTENT_TYPE="application/json",CONTENT_LENGTH=as.character(length(bytes)),rook.input=list(read=function(n=-1L)bytes))
    if(!is.null(token))req$HTTP_AUTHORIZATION<-paste("Bearer",token)
    if(startsWith(route,"/api/start/"))req$HTTP_X_BROHN_PARTICIPANT_RUNTIME<-release$participant_runtime$manifest_hash
    result<-app$call(req)
    if(result$status!=200L)stop("Receiver ",result$status,": ",result$body,call.=FALSE)
    jsonlite::fromJSON(result$body,simplifyVector=FALSE)
  }
  journal_for<-function(protocol){
    events<-list();now<-10
    clock<-function(t)list(id="browser-monotonic",unit="ms",value=format(t,scientific=FALSE,trim=TRUE,digits=17),
      instance_id="original-gnat-page",time_origin_ms="1000000")
    append<-function(type,step=NULL,payload=structure(list(),names=character()),at=now+1){
      now<<-at;events[[length(events)+1L]]<<-list(sequence=length(events)+1L,id=paste0("original-event-",length(events)+1L),
        type=type,step_id=step$id,stimulus_id=step$stimulus_id,condition_id=step$condition_id,question_id=NULL,
        phase=if(type=="equipment_event")"equipment_setup"else if(is.null(step))"completion"else step$phase,clock=clock(at),payload=payload)
    }
    requirement<-brohn_equipment_requirements(protocol)
    if(length(requirement$required_codes))append("equipment_event",payload=list(schema="brohn-participant-equipment-check/1.0",policy_hash=requirement$policy_hash,
      kind="keyboard",attempt_id="original-keyboard-check",evidence=list(codes=requirement$required_codes,released=TRUE,focused=TRUE,visible=TRUE,last_input_ms=now)))
    if(isTRUE(requirement$controls))append("equipment_event",payload=list(schema="brohn-participant-equipment-check/1.0",policy_hash=requirement$policy_hash,
      kind="controls",attempt_id="original-controls-check",evidence=list(activation="keyboard_or_assistive",trusted=TRUE,last_input_ms=now)))
    for(step in protocol$timeline){
      append("step_started",step)
      if(step$type=="task")for(e in original_gnat_journal(step$task))append("task_event",step,e$payload,as.numeric(e$clock$value))
      append("step_finished",step)
    }
    append("run_finished",payload=list(outcome="completed"));events
  }
  attempts<-runs<-originals<-list()
  for(allocation in 1:2){
    label<-as.character(allocation)
    start<-call(paste0("/api/start/",release$token),list(consented=TRUE,client_id=paste0("gnat-client-",label),
      operation_id=paste0("gnat-start-",label),participant_alias=paste0("gnat-person-",label)))
    check(paste(label,"receiver assigns exact frozen GNAT allocation"),start$protocol$allocation_index==allocation &&
      identical(Filter(function(s)s$type=="task",start$protocol$timeline)[[1L]]$task$profile,task$profile))
    events<-journal_for(start$protocol);original_hash<-brohn_hash(events)
    for(first in seq.int(1L,length(events),100L)){
      last<-min(first+99L,length(events));receipt<-call(paste0("/api/events/",start$run_id),
        list(operation_id=paste0("gnat-batch-",label,"-",first),events=events[first:last]),start$access_token)
      check(paste(label,"durable contiguous evidence through",last),receipt$acked_sequence==last)
    }
    done<-call(paste0("/api/finish/",start$run_id),list(outcome="completed",final_sequence=length(events),operation_id=paste0("gnat-finish-",label)),start$access_token)
    queued<-Filter(function(j)j$status=="queued",brohn_list_jobs(store,limit=100L))
    check(paste(label,"completion queues exactly one automatic analysis"),done$status=="saved"&&length(queued)==1L&&queued[[1L]]$operation=="analyse_run")
    brohn_cancel_job(store,queued[[1L]]$id)
    run<-brohn_run(store,start$run_id);saved<-brohn_run_events(store,run$id)
    check(paste(label,"all original nested receipts are preserved"),identical(brohn_hash(saved),original_hash))
    evidence<-brohn_task_run_evidence(store,run$id,design$id,"default",task$id)
    check(paste(label,"native export verifies outer journal and retains384trials"),length(evidence$rows)==384L&&
      evidence$evidence$level=="brohn_journal_replayed"&&evidence$evidence$events_hash==original_hash)
    csv<-file.path(folder,paste0(label,".csv"));rp<-file.path(folder,paste0(label,".json"))
    brohn_export_task_trial_csv(evidence,csv);brohn_export_task_registry(evidence,rp)
    data<-brohn_read_table(csv,"csv",20000L);registry<-brohn_read_json_file(rp)
    check(paste(label,"actual CSV retains every exact native export cell"),nrow(data)==384L&&all(vapply(seq_len(384L),function(i)
      same(lapply(as.list(data[i,,drop=FALSE]),unname),evidence$rows[[i]]),logical(1))))
    m<-list(adapter=evidence$declarations$adapter,task_id=task$id,source_collection_id=release$id,
      origin_statement="Original synthetic receiver fixture exported unchanged.",source_software=NULL,
      source_rt_definition=evidence$declarations$source_rt_definition,terminal_response_rule=evidence$declarations$terminal_response_rule,evidence_level="declared_trial_summary")
    aliases<-c(participant="participant_id",session="session_id",attempt="attempt_id",protocol="protocol_id",trial="trial_id")
    for(field in .brohn_task_import_columns(m$adapter)){base<-sub("_column$","",field);m[[field]]<-if(base %in% names(aliases))unname(aliases[[base]])else base}
    src<-list(id=paste0("gnat-summary-",label),revision=1L,hash=digest::digest(file=csv,algo="sha256"),origin="sample",registry_object_hash=digest::digest(file=rp,algo="sha256"))
    imported<-brohn_import_task_trials(data,m,design,src,registry);a<-imported$task_attempts[[1L]]
    report<-brohn_analyse_runs(list(design=design,runs=list(run),events=setNames(list(saved),run$id)))
    native<-report$analysis$task_scores[[1L]]
    check(paste(label,"native and imported metrics counts and complete audits agree"),same(native$metrics,a$score$metrics)&&
      same(native$counts,a$score$counts)&&same(native$scoring_audit,a$score$scoring_audit))
    check(paste(label,"summary import retains its weaker evidence boundary"),!a$timing_quality$journal_replayed&&
      !a$timing_quality$physical_timing_qualified&&a$evidence_level=="declared_trial_summary")
    originals[[label]]<-list(protocol_hash=brohn_hash(run$protocol),events_hash=original_hash,evidence_hash=brohn_hash(evidence))
    runs[[label]]<-run;attempts[[label]]<-a
  }
  plan<-list(schema="brohn-task-cohort-plan/1.0",description="Two originally authored synthetic people",
    membership=unname(lapply(attempts,function(a)list(attempt_id=a$id,attempt_hash=brohn_hash(a)))),
    homogeneous=.brohn_task_cohort_identity(attempts[[1L]]),repeat_policy="one_selected_attempt_per_person")
  map<-brohn_task_cohort_identity_rows(unname(attempts));map$linkage_statement<-"Two distinct synthetic people explicitly assigned by this original fixture."
  map$participants<-lapply(map$participants,function(p){p$person_id<-p$participant_id;p})
  map$sessions<-lapply(map$sessions,function(s){s$session_id<-s$source_session_id;s})
  cohort<-brohn_task_cohort(unname(attempts),plan,map)
  check("Descriptive cohort has ten separate outcomes and two people rather than768trials",length(cohort$summaries)==10L&&
    all(vapply(cohort$summaries,function(s)s$contributing_person_count==2L&&s$unit=="dimensionless",logical(1)))&&!cohort$quality$inference_performed)
  for(item in list(brohn_clone_study(store,design$id),brohn_use_template(store,brohn_save_template(store,design$id)$id)))
    check("Clone/template retains reviewed procedure and fresh category/task identities",item$id!=design$id&&item$body$blocks[[1L]]$id!=task$id&&
      same(item$body$blocks[[1L]]$settings,task$settings)&&!any(brohn_ids(item$body$blocks[[1L]]$categories)%in%brohn_ids(task$categories)))
  zip<-file.path(folder,"gnat.brohn-study.zip");brohn_export_design(store,design$id,zip);restored<-brohn_import_design(other,zip)
  check("Portable design preserves all materials and384trial procedure",same(restored$body$blocks[[1L]]$settings,task$settings)&&
    length(Filter(function(t)t$type=="task_trial",brohn_task_compile(restored$body$blocks[[1L]])$timeline))==384L&&
    identical(vapply(restored$body$blocks[[1L]]$materials,`[[`,character(1),"content"),vapply(task$materials,`[[`,character(1),"content")))
  brohn_close_store(store);store<-brohn_open_store(file.path(folder,"w"))
  for(label in names(runs))check(paste(label,"restart retains exact protocol journal and native export"),
    brohn_hash(brohn_run(store,runs[[label]]$id)$protocol)==originals[[label]]$protocol_hash&&
    brohn_hash(brohn_run_events(store,runs[[label]]$id))==originals[[label]]$events_hash&&
    brohn_hash(brohn_task_run_evidence(store,runs[[label]]$id,design$id,"default",task$id))==originals[[label]]$evidence_hash)
  check("Component fixture never executes a scientific worker",all(vapply(brohn_list_jobs(store,limit=100L),function(j)j$status=="cancelled"&&j$attempt==0L,logical(1))))
  check("Exercised source stayed unchanged",identical(start_hashes,hashes()))
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),source_start=start_hashes,source_end=hashes(),originals=originals,
    scope="Full authored R receiver/store/export/import/cohort/clone/portable/reopen integration; no browser or actual scientific worker claim."),file.path(folder,"results.json"))
  cat("GNAT_INTEGRATION_PASS",length(checks),"\n")
})
