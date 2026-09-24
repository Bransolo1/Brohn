# Actual receiver/store and portable/export/import integration; no browser or worker claim.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
source("tests/fixtures/sciat-window-journal.R",encoding="UTF-8")
local({
  args<-commandArgs(trailingOnly=TRUE);folder<-if(length(args))args[[1L]]else tempfile("brohn-sciat-window-integration-")
  stopifnot(!dir.exists(folder));dir.create(folder,recursive=TRUE);folder<-normalizePath(folder,winslash="/")
  store<-brohn_open_store(file.path(folder,"workspace"));other<-brohn_open_store(file.path(folder,"portable-workspace"))
  on.exit({for(j in brohn_list_jobs(store,limit=100L))if(j$status=="queued")brohn_cancel_job(store,j$id);brohn_close_store(other);brohn_close_store(store)},add=TRUE)
  brohn_initialise_library(store);brohn_initialise_library(other)
  checks<-character();check<-function(label,x){if(!isTRUE(x))stop(label,call.=FALSE);checks<<-c(checks,label);cat("PASS",label,"\n")}
  rejects<-function(x)inherits(try(force(x),silent=TRUE),"try-error")
  same<-function(a,b)identical(brohn_hash(a),brohn_hash(b))
  near<-function(a,b)isTRUE(all.equal(a,b,tolerance=1e-12,check.attributes=FALSE))
  files<-c("R/platform-sciat-window.R","R/platform-sciat-window-delivery.R","R/platform-sciat-window-score.R","R/platform-methods.R",
    "R/platform-delivery.R","R/platform-task-import.R","R/platform-task-evidence.R","R/platform-task-cohort.R","R/platform-task-plots.R",
    "R/platform-materials.R","R/platform-core.R","R/platform-portability.R","www/participant/event-batch.js",
    "tests/fixtures/sciat-window-journal.R","tests/fixtures/participant-event-envelope.mjs","tests/platform-sciat-window-integration.R")
  hashes<-function()setNames(lapply(files,function(p)digest::digest(file=p,algo="sha256")),files)
  started_hashes<-hashes();brohn_write_json_file(started_hashes,file.path(folder,"source-start.json"))
  on.exit(if(!file.exists(file.path(folder,"results.json")))brohn_write_json_file(list(passed=FALSE,completed_checks=as.list(checks),source_hashes=hashes()),file.path(folder,"failure-progress.json")),add=TRUE)
  legacy<-brohn_read_json_file("tests/fixtures/sciat-legacy-profile-contract.json")
  check("Exact five prior profile snapshots remain unchanged",brohn_hash(legacy)=="9b4045230a5a6885341f6179ccfe2219a3f31c84a021e4978e442a406435f653"&&same(brohn_task_profiles()[names(legacy)],legacy))
  design<-brohn_new_design("Original SC-IAT receiver integration","blank",id="original-sciat-integration-study")
  task<-brohn_task_new("sciat-brohn-response-window-im100/1.0",id="original-sciat-integration-task")
  design$blocks<-list(task);design_hash<-brohn_hash(design);brohn_put_entity(store,"study",design$id,design)
  release<-brohn_publish(store,design$id,origin="sample",quota=2L)
  app<-brohn_delivery_app(store)
  call<-function(route,payload=NULL,token=NULL,raw_body=NULL) {
    bytes<-if(!is.null(raw_body))raw_body else if(is.null(payload))raw()else charToRaw(.brohn_store_json(payload))
    req<-list(PATH_INFO=route,REQUEST_METHOD=if(is.null(payload)&&is.null(raw_body))"GET"else"POST",HTTP_HOST="127.0.0.1:3840",
      HTTP_ORIGIN="http://127.0.0.1:3840",CONTENT_TYPE="application/json",CONTENT_LENGTH=as.character(length(bytes)),rook.input=list(read=function(n=-1L)bytes))
    if(!is.null(token))req$HTTP_AUTHORIZATION<-paste("Bearer",token)
    if(startsWith(route,"/api/start/"))req$HTTP_X_BROHN_PARTICIPANT_RUNTIME<-release$participant_runtime$manifest_hash
    result<-app$call(req);value<-if(is.character(result$body))jsonlite::fromJSON(result$body,simplifyVector=FALSE)else NULL
    if(result$status!=200L)stop("Receiver failure ",route," ",result$status,": ",result$body,call.=FALSE)
    value
  }
  wrapper<-function(protocol) {
    events<-list();now<-10
    clock<-function(t)list(id="browser-monotonic",unit="ms",value=format(t,scientific=FALSE,trim=TRUE,digits=17),instance_id="original-sciat-probe-page",time_origin_ms="1000000")
    append<-function(type,step=NULL,payload=structure(list(),names=character()),at=now+1) {
      now<<-at;e<-list(sequence=length(events)+1L,id=paste0("original-event-",length(events)+1L),type=type,
        step_id=step$id,stimulus_id=step$stimulus_id,condition_id=step$condition_id,question_id=NULL,
        phase=if(type=="equipment_event")"equipment_setup"else if(is.null(step))"completion"else step$phase,clock=clock(at),payload=payload)
      events[[length(events)+1L]]<<-e
    }
    requirement<-brohn_equipment_requirements(protocol)
    if(length(requirement$required_codes))append("equipment_event",payload=list(schema="brohn-participant-equipment-check/1.0",policy_hash=requirement$policy_hash,
      kind="keyboard",attempt_id="original-keyboard-check",evidence=list(codes=requirement$required_codes,released=TRUE,focused=TRUE,visible=TRUE,last_input_ms=now)))
    if(isTRUE(requirement$controls))append("equipment_event",payload=list(schema="brohn-participant-equipment-check/1.0",policy_hash=requirement$policy_hash,
      kind="controls",attempt_id="original-controls-check",evidence=list(activation="keyboard_or_assistive",trusted=TRUE,last_input_ms=now)))
    for(step in protocol$timeline) {
      append("step_started",step)
      if(step$type=="task")for(e in original_sciat_window_journal(step$task))append("task_event",step,e$payload,as.numeric(e$clock$value))
      append("step_finished",step)
    }
    append("run_finished",payload=list(outcome="completed"));events
  }
  runs<-journals<-evidence<-imports<-native_scores<-list();source_objects<-list()
  for(allocation in 1:2) {
    label<-c("A","B")[[allocation]]
    start<-call(paste0("/api/start/",release$token),list(consented=TRUE,client_id=paste0("original-client-",label),operation_id=paste0("start-",label),participant_alias=paste0("original-person-",label)))
    check(paste(label,"real receiver assigned expected frozen mapping"),start$protocol$allocation_index==allocation&&Filter(function(s)s$type=="task",start$protocol$timeline)[[1]]$task$assignment$initial_mapping==label)
    journal<-wrapper(start$protocol);snapshot<-brohn_hash(journal)
    for(first in seq.int(1L,length(journal),100L)) {
      last<-min(first+99L,length(journal));request<-list(operation_id=paste0("batch-",label,"-",first),events=journal[first:last])
      receipt<-call(paste0("/api/events/",start$run_id),request,start$access_token)
      check(paste(label,"receiver durable contiguous receipt through",last),receipt$acked_sequence==last)
    }
    done<-call(paste0("/api/finish/",start$run_id),list(outcome="completed",final_sequence=length(journal),operation_id=paste0("finish-",label)),start$access_token)
    jobs<-brohn_list_jobs(store,limit=100L);queued<-Filter(function(j)j$status=="queued",jobs)
    check(paste(label,"complete receiver queues its analysis without running a worker"),done$status=="saved"&&length(queued)==1L&&queued[[1]]$operation=="analyse_run")
    for(j in queued)brohn_cancel_job(store,j$id)
    run<-brohn_run(store,start$run_id);saved_events<-brohn_run_events(store,run$id)
    check(paste(label,"all outer event fields and nested evidence survive receiver persistence"),brohn_hash(saved_events)==snapshot&&run$completion_status=="completed"&&run$transfer_status=="saved")
    source_objects[[label]]<-list(protocol_hash=brohn_hash(run$protocol),events_hash=brohn_hash(saved_events))
    ex<-brohn_task_run_evidence(store,run$id,design$id,"default",task$id)
    check(paste(label,"native export replays complete journal and all192trials"),length(ex$rows)==192L&&ex$evidence$level=="brohn_journal_replayed"&&ex$evidence$events_hash==snapshot)
    csv<-file.path(folder,paste0("original-",label,".csv"));registry_file<-file.path(folder,paste0("original-",label,"-registry.json"))
    brohn_export_task_trial_csv(ex,csv);brohn_export_task_registry(ex,registry_file)
    data<-brohn_read_table(csv,"csv",20000L);registry<-brohn_read_json_file(registry_file)
    check(paste(label,"CSV and registry preserve every original export cell"),nrow(data)==192L&&all(vapply(seq_len(192L),function(i)identical(lapply(as.list(data[i,,drop=FALSE]),unname),ex$rows[[i]]),logical(1)))&&same(registry,ex$registry))
    mapping<-list(task_id=task$id,source_collection_id=release$id,origin_statement="Original synthetic receiver fixture exported without changes.",source_software=NULL,
      source_rt_definition=ex$declarations$source_rt_definition,terminal_response_rule=ex$declarations$terminal_response_rule,evidence_level="declared_trial_summary",
      participant_column="participant_id",participant_linkage_column="participant_linkage",session_column="session_id",attempt_column="attempt_id",protocol_column="protocol_id",
      presentation_index_column="presentation_index",trial_column="trial_id",presented_column="presented",outcome_column="outcome",first_code_column="first_code",final_code_column="final_code",
      first_correct_column="first_correct",first_response_ms_column="first_response_ms",final_correct_ms_column="final_correct_ms",missing_reason_column="missing_reason")
    src<-list(id=paste0("original-summary-",label),revision=1L,hash=digest::digest(file=csv,algo="sha256"),origin="sample",registry_object_hash=digest::digest(file=registry_file,algo="sha256"))
    imported<-brohn_import_task_trials(data,mapping,design,src,registry);attempt<-imported$task_attempts[[1L]]
    full<-brohn_analyse_runs(list(design=design,runs=list(run),events=setNames(list(saved_events),run$id)))
    scored<-full$analysis$task_scores[[1L]]
    check(paste(label,"native and imported first-response arithmetic agree exactly"),same(scored$metrics,attempt$score$metrics)&&same(scored$scoring_audit,attempt$score$scoring_audit)&&same(scored$counts,attempt$score$counts))
    check(paste(label,"summary import cannot inherit native replay or clock qualification"),attempt$evidence_level=="declared_trial_summary"&&!attempt$timing_quality$journal_replayed&&!attempt$timing_quality$physical_timing_qualified&&is.null(attempt$timing_quality$key_history)&&is.null(attempt$timing_quality$source_clock))
    check(paste(label,"all192source rows remain complete and auditable"),length(imported$source_rows)==192L&&length(attempt$trial_audit)==192L&&all(vapply(seq_len(192L),function(i)same(imported$source_rows[[i]]$original_cells,ex$rows[[i]]),logical(1))))
    compiled<-registry$protocols[[1L]]$compiled;trials<-Filter(function(t)t$type=="task_trial",compiled$timeline)
    rows<-Filter(function(e)e$type=="task_event"&&e$payload$kind=="task_trial_finished",saved_events)
    scored_indices<-which(vapply(trials,`[[`,logical(1),"scored"));latencies<-vapply(rows[scored_indices],function(e)e$payload$data$response_ms,numeric(1))
    correct<-vapply(rows[scored_indices],function(e)e$payload$data$correct,logical(1));maps<-vapply(trials[scored_indices],`[[`,character(1),"mapping")
    adjusted<-latencies;for(m in c("A","B"))adjusted[maps==m&!correct]<-mean(latencies[maps==m])+400
    expected<-(mean(adjusted[maps=="B"])-mean(adjusted[maps=="A"]))/stats::sd(latencies[correct])
    check(paste(label,"independent144trial error-mean and pooled-correct denominator arithmetic"),near(scored$metrics[[1L]]$value,expected)&&scored$counts$practice==48L&&scored$counts$scored==144L&&scored$counts$retained_errors==1L)
    imodel<-brohn_task_plot_attempt(attempt);nmodel<-brohn_task_plot_native(ex,full,full$provenance$runs[[1L]])
    check(paste(label,"native and imported trial plots retain identical192raw measurements"),same(imodel$rows,nmodel$rows)&&length(nmodel$rows)==192L&&nmodel$evidence_level=="brohn_journal_replayed")
    first_view<-brohn_task_plot_selection(imodel);correct_view<-brohn_task_plot_selection(imodel,"final_correct_ms")
    check(paste(label,"plot counts omissions and wrong first responses without inventing correction"),first_view$available==191L&&first_view$missing==1L&&correct_view$available==189L&&correct_view$missing==3L&&correct_view$label=="Correct first-response latency")
    check(paste(label,"scored plots use144test positions and original latencies"),length(brohn_task_plot_selection(imodel,scope="scored")$rows)==144L&&sum(vapply(first_view$bins,`[[`,numeric(1),"count"))==191)
    check(paste(label,"wrong first key and omission stay explicit in CSV"),data$outcome[[1L]]=="incorrect"&&data$final_correct_ms[[1L]]==""&&data$outcome[[3L]]=="timeout"&&data$first_response_ms[[3L]]==""&&data$final_correct_ms[[3L]]=="")
    bad<-data;bad$final_correct_ms[[1L]]<-"500";bad$final_code[[1L]]<-trials[[1L]]$correct_code
    check(paste(label,"summary cannot invent correction after wrong first response"),rejects(brohn_import_task_trials(bad,mapping,design,src,registry)))
    forged<-mapping;forged$evidence_level<-"brohn_journal_replayed"
    check(paste(label,"summary cannot claim native journal evidence"),rejects(brohn_import_task_trials(data,forged,design,src,registry)))
    if(allocation==1L)brohn_write_json_file(rows[[1L]],file.path(folder,"envelope-source-event.json"))
    runs[[label]]<-run;journals[[run$id]]<-saved_events;evidence[[label]]<-ex;imports[[label]]<-attempt;native_scores[[label]]<-scored
  }
  plan<-list(schema="brohn-task-cohort-plan/1.0",description="Two independently received original synthetic administrations",membership=unname(lapply(imports,function(a)list(attempt_id=a$id,attempt_hash=brohn_hash(a)))),
    homogeneous=.brohn_task_cohort_identity(imports[[1]]),repeat_policy="one_selected_attempt_per_person")
  map<-brohn_task_cohort_identity_rows(unname(imports));map$linkage_statement<-"Original fixture explicitly assigns two different synthetic people."
  map$participants<-lapply(map$participants,function(p){p$person_id<-p$participant_id;p});map$sessions<-lapply(map$sessions,function(s){s$session_id<-s$source_session_id;s})
  cohort<-brohn_task_cohort(unname(imports),plan,map);summary<-cohort$summaries[[1L]]
  check("Cohort accepts exact new recipe without pooling192trials as people",summary$metric=="SCIAT_target_positive_D"&&summary$unit=="D"&&summary$contributing_person_count==2L&&summary$selected_attempt_count==2L&&near(summary$mean,mean(vapply(native_scores,function(s)s$metrics[[1]]$value,numeric(1))))&&!cohort$quality$inference_performed)
  people<-brohn_task_plot_people(cohort,"SCIAT_target_positive_D")
  check("Person plot preserves both complete saved scores and descriptive units",length(people$rows)==2L&&people$unit=="D"&&same(people$summary,summary))
  wrong<-imports[[1L]];wrong$score$scoring_recipe<-"unsupported/9"
  check("Cohort refuses invented SC-IAT scoring recipe",rejects(.brohn_task_cohort_attempt(wrong)))
  clone<-brohn_clone_study(store,design$id);template<-brohn_save_template(store,design$id);reused<-brohn_use_template(store,template$id)
  for(item in list(clone,reused))check("Cloned/template study retains procedure with fresh task and category IDs",item$id!=design$id&&item$body$blocks[[1]]$id!=task$id&&identical(item$body$blocks[[1]]$profile,task$profile)&&same(item$body$blocks[[1]]$settings,task$settings)&&!any(brohn_ids(item$body$blocks[[1]]$categories)%in%brohn_ids(task$categories))&&length(brohn_task_compile(item$body$blocks[[1]])$timeline)==196L)
  material<-task$materials[[1L]];image_design<-brohn_material_attach_png(store,design,"exemplar",material$id,task$id,"examples/stimuli/sample-design-a.png",image_alt="Original synthetic package illustration")
  image<-image_design$blocks[[1L]]$materials[[1L]]
  check("SC-IAT image authoring pins decoded PNG and reviewed alt text",image$type=="image"&&image$asset$hash==digest::digest(file="examples/stimuli/sample-design-a.png",algo="sha256")&&image$image_alt=="Original synthetic package illustration")
  broken<-image_design;broken$blocks[[1]]$materials[[1]]$image_alt<-NULL
  check("Missing SC-IAT image description refuses design and release validation",rejects(brohn_validate_design(broken)))
  brohn_put_entity(store,"study",design$id,image_design,expected_revision=1L)
  portable<-file.path(folder,"original-sciat.brohn-study.zip");brohn_export_design(store,design$id,portable);restored<-brohn_import_design(other,portable)
  restored_task<-restored$body$blocks[[1L]]
  check("Portable ZIP preserves exact image bytes, alt text, recipe and settings",restored_task$profile==task$profile&&same(restored_task$settings,task$settings)&&restored_task$materials[[1]]$asset$hash==image$asset$hash&&file.exists(brohn_object_path(other,image$asset$hash,verify=TRUE))&&restored_task$materials[[1]]$image_alt==image$image_alt&&length(brohn_task_compile(restored_task,2L)$timeline)==196L)
  for(label in names(runs))check(paste(label,"draft image edit and reuse never alter original released session"),same(brohn_run(store,runs[[label]]$id)$protocol,runs[[label]]$protocol)&&same(brohn_run_events(store,runs[[label]]$id),journals[[runs[[label]]$id]])&&brohn_run(store,runs[[label]]$id)$protocol$design_hash==design_hash)
  # Exact JS-selected wire bytes enter the real R request parser and canonical cap.
  node<-Sys.which("node");stopifnot(nzchar(node));log<-file.path(folder,"envelope-node.log")
  status<-system2(node,c("tests/fixtures/participant-event-envelope.mjs",shQuote(folder)),stdout=log,stderr=log);stopifnot(status==0L)
  selected<-brohn_read_json_file(file.path(folder,"envelope-selection.json"));wire_path<-file.path(folder,"selected-envelope.json");raw<-readBin(wire_path,"raw",n=file.info(wire_path)$size)
  parsed<-.brohn_delivery_request(list(CONTENT_LENGTH=as.character(length(raw)),CONTENT_TYPE="application/json",rook.input=list(read=function(n=-1L)raw)))
  canonical_bytes<-nchar(.brohn_store_json(parsed,maximum=4*1024^2),type="bytes")
  check("3MiB JS envelope with5000native-shaped decimal keys per event passes actual R parser/canonical cap",length(raw)==selected$wire_bytes&&length(raw)<=3*1024^2&&canonical_bytes<=4*1024^2&&length(parsed$events)==selected$batch$last&&all(vapply(parsed$events,function(e)length(e$payload$data$keys)==5000L,logical(1))))
  check("No scientific worker ran; all automatic analysis jobs are explicitly cancelled",all(vapply(brohn_list_jobs(store,limit=100L),function(j)j$status=="cancelled"&&j$attempt==0L,logical(1))))
  check("All tested product and original fixture sources stayed unchanged",identical(started_hashes,hashes()))
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),source_hashes=hashes(),scope="Original synthetic full outer receiver/store integration; pure scoring/import/cohort and portable image design; no browser/scientific worker execution or physical timing qualification.",
    allocations=lapply(runs,function(r)list(run_id=r$id,allocation=r$allocation_index,final_sequence=r$acked_sequence)),source_objects=source_objects,
    scores=lapply(native_scores,function(s)list(metrics=s$metrics,counts=s$counts)),envelope=list(selection=selected,wire_bytes=length(raw),canonical_bytes=canonical_bytes),
    jobs=lapply(brohn_list_jobs(store,limit=100L),function(j)list(id=j$id,operation=j$operation,status=j$status,attempt=j$attempt))),file.path(folder,"results.json"))
  cat("PASS",length(checks),"SC-IAT integration checks\n",folder,"\n")
})
