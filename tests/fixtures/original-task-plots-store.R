# Original synthetic frozen tables and complete receiver journal; no hardware
# or new worker qualification is claimed by these direct test publications.
source("tests/fixtures/original-task-cohort-store.R",encoding="UTF-8")
source("tests/fixtures/original-task-journal.R",encoding="UTF-8")
brohn_original_task_plot_fixture <- function(store) {
  f<-brohn_original_cohort_store_fixture(store)
  publish<-function(body){body$id<-brohn_id("report");body$schema_version<-"brohn-report/1.0.0";body$status<-"Available";body$created_at<-brohn_now()
    body$result_object<-brohn_store_object(store,bytes=charToRaw(enc2utf8(brohn_json(list(schema="brohn-analysis-output/1.0",report=body)))),media_type="application/json")
    brohn_put_entity(store,"report",body$id,body,project_id=body$provenance$design$project_id)}
  imported<-list();manifest<-brohn_read_json_file("tests/fixtures/task-import/manifest.json")
  for(name in names(manifest$fixtures)) {
    ref<-manifest$fixtures[[name]];registry<-brohn_read_json_file(file.path("tests/fixtures/task-import",ref$registry))
    design<-brohn_new_design(paste("Original",name,"task plots"),"blank",brohn_id("study"));design$blocks<-list(registry$task);brohn_put_entity(store,"study",design$id,design)
    reg<-brohn_store_object(store,path=file.path("tests/fixtures/task-import",ref$registry),media_type="application/json")
    data<-brohn_read_table(file.path("tests/fixtures/task-import",ref$csv),"csv",20000L)
    if(name=="iat") {
      trial<-Filter(function(t)t$type=="task_trial",registry$protocols[[1L]]$compiled$timeline)[[1L]]
      data$first_code[[1L]]<-setdiff(unlist(trial$allowed_codes),trial$correct_code)[[1L]];data$first_correct[[1L]]<-"false";data$first_response_ms[[1L]]<-"150.000"
    }
    file<-tempfile(fileext=".csv");utils::write.table(data,file,sep=",",row.names=FALSE,col.names=TRUE,quote=TRUE,qmethod="double",eol="\n",fileEncoding="UTF-8")
    original<-brohn_store_object(store,path=file,media_type="text/csv");unlink(file)
    source<-list(id=brohn_id("dataset"),revision=1L,hash=original$hash,origin="sample",registry_object_hash=reg$hash)
    a<-brohn_import_task_trials(data,ref$metadata,design,source,registry)
    imported[[name]]<-publish(list(title=paste("Original",name,"complete trial source"),study_id=design$id,dataset_id=NULL,origin="sample",
      provenance=list(design=design,design_hash=brohn_hash(design)),analysis=a))
  }
  partial<-f$source_report(person="Partial",mean_ms=500,partial=TRUE);incomplete<-f$source_report(person="Missing",incomplete=TRUE)
  unknown<-f$source_report(person="Unknown timing",unknown=TRUE)
  attempts<-lapply(c(f$reports,list(partial)),function(r)r$body$analysis$task_attempts[[1L]])
  plan<-list(schema="brohn-task-cohort-plan/1.0",description="Original task plot person arithmetic",membership=lapply(attempts,function(a)list(attempt_id=a$id,attempt_hash=brohn_hash(a))),
    homogeneous=.brohn_task_cohort_identity(attempts[[1L]]),repeat_policy="equal_attempts_within_session_then_equal_sessions_within_person")
  ca<-brohn_task_cohort(attempts,plan,brohn_original_cohort_map(attempts));cohort<-f$publish(ca,title="Original repeated-person cohort")
  study<-brohn_create_study(store,"Original replayed task plot source","blank");d<-study$body
  d$blocks<-list(brohn_task_new("rt-deary-liewald-choice/1.0",id="original-plot-task"));study<-brohn_save_study(store,d,study$revision)
  release<-brohn_publish(store,study$id,"sample",alias_required=TRUE)
  start<-.brohn_delivery_start(store,release$token,list(consented=TRUE,participant_alias="001",client_id="original-plot-client",operation_id="original-plot-start"))
  protocol<-brohn_run(store,start$run_id)$protocol
  events<-original_task_journal(protocol,function(t)if(!t$scored||t$trial_index==1L)list(outcome="correct",rt=500)else list(outcome="timeout"))
  .brohn_delivery_receive(store,start$run_id,start$access_token,list(events=events,operation_id="original-plot-events"))
  .brohn_delivery_finish(store,start$run_id,start$access_token,list(outcome="completed",final_sequence=length(events),operation_id="original-plot-finish"))
  for(j in brohn_list_jobs(store))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id)
  run<-brohn_run(store,start$run_id);native_body<-brohn_analyse_runs(list(design=run$protocol$design,runs=list(run),events=stats::setNames(list(events),run$id)))
  native<-publish(native_body)
  list(imported=imported,partial=partial,incomplete=incomplete,unknown=unknown,cohort=cohort,native=native,native_run=run,publish=publish,events=events)
}
