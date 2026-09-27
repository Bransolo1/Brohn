# Original synthetic source producers only. No new report/export adapter job.
args<-commandArgs(TRUE);stopifnot(length(args)==1L)
config<-jsonlite::fromJSON(args[[1L]],simplifyVector=FALSE);setwd(config$checkout)
Sys.setenv(BROHN_PUBLICATION_NATIVE_MANIFEST=config$native_manifest)
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("R/platform-task-plots.R",encoding="UTF-8")
source("tests/fixtures/original-task-journal.R",encoding="UTF-8")
source("tests/fixtures/gnat-journal.R",encoding="UTF-8")
source("tests/fixtures/sciat-window-journal.R",encoding="UTF-8")
local({
  out<-config$out;checks<-list();passed<-FALSE;failure<-NULL;entries<-list();reports<-list()
  store<-brohn_open_store(file.path(out,"workspace"));brohn_initialise_library(store)
  check<-function(name,x){if(!isTRUE(x))stop(name,call.=FALSE);checks[[length(checks)+1L]]<<-name;cat("PASS",name,"\n")}
  ref<-function(r)list(kind="report",id=r$id,revision=r$revision,body_hash=brohn_hash(r$body),project_id=r$project_id)
  on.exit({
    for(j in brohn_list_jobs(store,limit=100L))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id)
    objects<-DBI::dbGetQuery(store$con,"SELECT * FROM objects")
    brohn_write_json_file(list(schema="brohn-seven-task-source-corpus/0.1",passed=passed,checks=checks,failure=failure,entries=entries,
      reports=lapply(reports,ref),jobs=lapply(brohn_list_jobs(store,limit=100L),function(j)list(id=j$id,operation=j$operation,status=j$status,attempt=j$attempt,error=j$error,result=j$result)),
      objects=lapply(seq_len(nrow(objects)),function(i)as.list(objects[i,,drop=FALSE])),
      qualification="Original synthetic journal receiver and imported CSV sources through unmodified existing scientific workers, followed by saved descriptive cohort producer. Scientific production precedes any future task display/package. No browser, person, hardware, new adapter or estimator qualification."),file.path(out,"results.json"))
    brohn_close_store(store)
  },add=TRUE)
  runjob<-function(job){force(job);claim<-brohn_claim_job(store,"seven-task-source-corpus",lease_seconds=120L);stopifnot(identical(claim$id,job$id))
    brohn_process_job(store,claim,timeout_seconds=180);done<-brohn_get_job(store,job$id)
    if(done$status!="succeeded")stop("Scientific source worker failed: ",brohn_json(done$error))
    r<-brohn_get_entity(store,"report",done$result$report_id);reports[[length(reports)+1L]]<<-r;r}
  special_journal<-function(protocol,kind){
    events<-list();now<-10;instance<-if(kind=="gnat")"original-gnat-page"else"original-sciat-probe-page"
    clock<-function(t)list(id="browser-monotonic",unit="ms",value=format(t,scientific=FALSE,trim=TRUE,digits=17),instance_id=instance,time_origin_ms="1000000")
    append<-function(type,step=NULL,payload=structure(list(),names=character()),at=now+1){now<<-at;events[[length(events)+1L]]<<-list(sequence=length(events)+1L,id=paste0("original-event-",length(events)+1L),type=type,step_id=step$id,stimulus_id=step$stimulus_id,condition_id=step$condition_id,question_id=NULL,phase=if(type=="equipment_event")"equipment_setup"else if(is.null(step))"completion"else step$phase,clock=clock(at),payload=payload)}
    requirement<-brohn_equipment_requirements(protocol)
    if(length(requirement$required_codes))append("equipment_event",payload=list(schema="brohn-participant-equipment-check/1.0",policy_hash=requirement$policy_hash,kind="keyboard",attempt_id="original-keyboard-check",evidence=list(codes=requirement$required_codes,released=TRUE,focused=TRUE,visible=TRUE,last_input_ms=now)))
    if(isTRUE(requirement$controls))append("equipment_event",payload=list(schema="brohn-participant-equipment-check/1.0",policy_hash=requirement$policy_hash,kind="controls",attempt_id="original-controls-check",evidence=list(activation="keyboard_or_assistive",trusted=TRUE,last_input_ms=now)))
    for(step in protocol$timeline){append("step_started",step)
      if(step$type=="task")for(e in if(kind=="gnat")original_gnat_journal(step$task)else original_sciat_window_journal(step$task))append("task_event",step,e$payload,as.numeric(e$clock$value))
      append("step_finished",step)}
    append("run_finished",payload=list(outcome="completed"));events
  }
  tryCatch({
    profiles<-names(brohn_task_profiles());stopifnot(length(profiles)==7L)
    expected<-c(180L,96L,96L,28L,48L,192L,384L);scored<-c(120L,64L,80L,20L,40L,144L,240L)
    profile_order<-c("iat-gnb2003-d1/1.0","biat-nosek2014-goodfocal/1.0","aat-keyboard-cue-balanced/1.0","rt-deary-liewald-simple/1.0","rt-deary-liewald-choice/1.0","sciat-brohn-response-window-im100/1.0","gnat-brohn-single-target/1.0")
    names(expected)<-names(scored)<-profile_order
    for(index in seq_along(profile_order)){
      profile<-profile_order[[index]];kind<-brohn_task_profile(profile)$kind;folder<-file.path(out,sprintf("profile-%02d",index));dir.create(folder)
      study<-brohn_create_study(store,paste("Original complete",kind,"report sources"),"blank");d<-study$body;d$questionnaire_navigation<-NULL
      d$blocks<-list(brohn_task_new(profile,id=paste0("corpus-task-",index)));d$questions<-list()
      study<-brohn_save_study(store,d,study$revision);release<-brohn_publish(store,study$id,"sample",alias_required=TRUE)
      start<-.brohn_delivery_start(store,release$token,list(consented=TRUE,participant_alias="001",client_id=paste0("seven-source-",index),operation_id=paste0("seven-start-",index)))
      protocol<-brohn_run(store,start$run_id)$protocol
      if(kind %in% c("gnat","sciat_window"))events<-special_journal(protocol,kind) else events<-original_task_journal(protocol,function(t){
        if(kind=="choice_rt"&&t$scored&&t$trial_index>1L)return(list(outcome="timeout"))
        value<-if(kind=="choice_rt")500 else if(kind=="simple_rt")400+t$trial_index*10 else if(kind=="aat") {
          if(t$category_id=="target-a")if(t$action=="avoid")700 else 500 else 600
        }else 450+(t$trial_index%%11L)*17+as.numeric(sub(".*-b","",t$block_id))*20
        list(outcome="correct",rt=value)
      })
      for(first in seq.int(1L,length(events),100L)) .brohn_delivery_receive(store,start$run_id,start$access_token,list(events=events[first:min(first+99L,length(events))],operation_id=paste0("seven-events-",index,"-",first)))
      .brohn_delivery_finish(store,start$run_id,start$access_token,list(outcome="completed",final_sequence=length(events),operation_id=paste0("seven-finish-",index)))
      jobs<-brohn_list_jobs(store,limit=100L,request_filters=list(run_id=start$run_id));stopifnot(length(jobs)==1L)
      native<-runjob(jobs[[1L]]);evidence<-brohn_task_run_evidence(store,start$run_id,study$id,"default",d$blocks[[1L]]$id)
      compiled<-evidence$registry$protocols[[1L]]$compiled;trials<-Filter(function(t)t$type=="task_trial",compiled$timeline)
      check(paste(profile,"native expected/scored positions and complete original receipt"),length(evidence$rows)==expected[[profile]]&&sum(vapply(trials,`[[`,logical(1),"scored"))==scored[[profile]]&&length(native$body$provenance$run_evidence$runs)==1L)
      csv<-file.path(folder,"original-trials.csv");registry_path<-file.path(folder,"original-registry.json")
      brohn_export_task_trial_csv(evidence,csv);brohn_export_task_registry(evidence,registry_path)
      metadata<-list(task_id=d$blocks[[1L]]$id,source_collection_id=release$id,origin_statement="Original synthetic complete receiver fixture; no participant or physical timing qualification.",source_software=NULL,source_rt_definition=evidence$declarations$source_rt_definition,terminal_response_rule=evidence$declarations$terminal_response_rule,evidence_level="declared_trial_summary")
      if(kind=="gnat")metadata$adapter<-.brohn_gnat_import_adapter
      aliases<-c(participant="participant_id",session="session_id",attempt="attempt_id",protocol="protocol_id",trial="trial_id")
      for(field in .brohn_task_import_columns(metadata$adapter)){base<-sub("_column$","",field);metadata[[field]]<-if(base %in% names(aliases))unname(aliases[[base]])else base}
      metadata$task_column<-"task_id";metadata$origin_column<-"origin"
      importfile<-function(path,label){dataset<-brohn_ingest_dataset(store,path,label,modality="implicit",origin="sample")
        m<-metadata;m$protocol_registry<-brohn_stage_task_registry(store,registry_path,basename(registry_path),dataset$id,dataset$revision,study$id,study$revision,d$blocks[[1L]]$id)
        curated<-brohn_curate_dataset(store,dataset$id,m,dataset$revision,study$id,study$revision);runjob(brohn_queue_dataset(store,curated$id))}
      imported<-importfile(csv,paste("Original",kind,"declared summary"));attempt<-imported$body$analysis$task_attempts[[1L]]
      check(paste(profile,"genuine import retains all original rows and declaration"),length(imported$body$analysis$source_rows)==expected[[profile]]&&length(attempt$trial_audit)==expected[[profile]]&&attempt$evidence_level=="declared_trial_summary"&&!attempt$timing_quality$journal_replayed)
      check(paste(profile,"native/import saved metric and count agreement"),identical(brohn_hash(native$body$analysis$task_scores[[1L]]$metrics),brohn_hash(attempt$score$metrics))&&identical(brohn_hash(native$body$analysis$task_scores[[1L]]$counts),brohn_hash(attempt$score$counts)))
      brohn_write_json_file(native,file.path(folder,"native-report.json"));brohn_write_json_file(imported,file.path(folder,"import-report.json"));brohn_write_json_file(evidence,file.path(folder,"native-terminal-evidence.json"));brohn_write_json_file(events,file.path(folder,"original-journal.json"))
      brohn_write_json_file(brohn_task_plot_native(evidence,native$body,native$body$provenance$runs[[1L]]),file.path(folder,"native-display-reference.json"));brohn_write_json_file(brohn_task_plot_attempt(attempt),file.path(folder,"import-display-reference.json"))
      entries[[profile]]<-list(profile=profile,folder=basename(folder),native_ref=ref(native),import_ref=ref(imported),positions=length(trials),profile_scored=sum(vapply(trials,`[[`,logical(1),"scored")),compiled_hash=brohn_hash(compiled),native_score_hash=brohn_hash(native$body$analysis$task_scores[[1L]]),import_attempt_hash=brohn_hash(attempt))
      if(kind=="choice_rt"){
        original<-brohn_read_table(csv,"csv",20000L);p2<-original;q<-original
        p2$session_id<-"visit-two";p2$attempt_id<-"attempt-two";p2$first_response_ms<-p2$final_correct_ms<-"700";p2$first_correct<-"true";p2$outcome<-"correct"
        for(i in seq_along(trials))p2$first_code[[i]]<-p2$final_code[[i]]<-trials[[i]]$correct_code
        q$participant_id<-"002";q$session_id<-"visit-q";q$attempt_id<-"attempt-q"
        active<-nzchar(q$first_response_ms);q$first_response_ms[active]<-q$final_correct_ms[active]<-"300"
        repeat_path<-file.path(folder,"original-repeat-and-partial.csv");utils::write.csv(rbind(p2,q),repeat_path,row.names=FALSE,na="",fileEncoding="UTF-8")
        repeats<-importfile(repeat_path,"Original repeat visit and metric-unavailable person")
        catalog<-brohn_task_cohort_catalog(store,study$id,list(imported$id,repeats$id));map<-brohn_task_cohort_identity_rows(catalog$attempts)
        map$linkage_statement<-"Original synthetic identity register explicitly defines person001 two visits and person002 one visit."
        map$participants<-lapply(map$participants,function(p){p$person_id<-p$participant_id;p});map$sessions<-lapply(map$sessions,function(s){s$session_id<-s$source_session_id;s})
        cohort<-runjob(brohn_queue_task_cohort(store,study$id,list(imported$id,repeats$id),lapply(catalog$attempts,`[[`,"id"),map,"equal_attempts_within_session_then_equal_sessions_within_person","Original repeated-visit corpus",catalog$selection_hash))
        a<-cohort$body$analysis;summary<-function(name)Filter(function(s)s$metric==name,a$summaries)[[1L]]
        check("cohort saved equal-person mean450 from P(500,700) and Q300",summary("correct_test_rt_mean")$mean==450&&summary("correct_test_rt_mean")$contributing_person_count==2L&&summary("correct_test_rt_mean")$selected_attempt_count==3L)
        check("cohort retains unavailable person SD separately from valid mean",summary("correct_test_rt_sd")$contributing_person_count==1L&&length(Filter(function(p)p$metric=="correct_test_rt_sd"&&is.null(p$value),a$per_person))==1L)
        brohn_write_json_file(repeats,file.path(folder,"repeat-import-report.json"));brohn_write_json_file(cohort,file.path(folder,"cohort-report.json"));brohn_write_json_file(lapply(a$summaries,function(s)brohn_task_plot_people(a,s$metric)),file.path(folder,"cohort-display-reference.json"))
      }
    }
    check("all seven profile source pairs cover1024 positions and708 profile-scored positions",length(entries)==7L&&sum(vapply(entries,`[[`,integer(1),"positions"))==1024L&&sum(vapply(entries,`[[`,integer(1),"profile_scored"))==708L)
    check("all scientific source jobs are terminal before future report preparation",all(vapply(brohn_list_jobs(store,limit=100L),function(j)j$status=="succeeded",logical(1))))
    passed<-TRUE
  },error=function(e){failure<<-conditionMessage(e);stop(e)})
  cat("Seven task source corpus:",length(checks),"checks passed\n")
})
