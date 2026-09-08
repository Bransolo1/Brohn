# Original retained-object fixtures for source adapters. These are deliberately
# direct fixture publications, not claims of supervised worker qualification.
brohn_original_cohort_store_fixture <- function(store) {
  manifest<-brohn_read_json_file("tests/fixtures/task-import/manifest.json")
  f<-manifest$fixtures$choice
  registry<-brohn_read_json_file(file.path("tests/fixtures/task-import",f$registry))
  registry_object<-brohn_store_object(store,path=file.path("tests/fixtures/task-import",f$registry),media_type="application/json")
  d<-brohn_new_design("Original task cohort storage study","blank",brohn_id("study"));d$blocks<-list(registry$task)
  study<-brohn_put_entity(store,"study",d$id,d)
  source_table<-brohn_read_table(file.path("tests/fixtures/task-import",f$csv),"csv",20000L)
  publish<-function(analysis,design=d,title="Original task source",origin="sample",project_id=design$project_id) {
    id<-brohn_id("report")
    body<-list(schema_version="brohn-report/1.0.0",id=id,title=title,created_at=brohn_now(),status="Available",study_id=design$id,dataset_id=NULL,origin=origin,
      provenance=list(design=design,design_hash=brohn_hash(design)),analysis=analysis)
    body$result_object<-brohn_store_object(store,bytes=charToRaw(enc2utf8(brohn_json(list(schema="brohn-analysis-output/1.0",report=body)))),media_type="application/json")
    brohn_put_entity(store,"report",id,body,project_id=project_id)
  }
  source_report<-function(person="P",session="S1",attempt="A1",mean_ms=1,partial=FALSE,unknown=FALSE,incomplete=FALSE,collection="original-collection") {
    data<-source_table;m<-f$metadata
    data[[m$participant_column]]<-person;data[[m$session_column]]<-session;data[[m$attempt_column]]<-attempt
    data$first_response_ms<-data$final_correct_ms<-as.character(mean_ms);m$source_collection_id<-collection
    if(unknown)m$source_rt_definition<-"unknown"
    if(partial) {
      trials<-Filter(function(s)s$type=="task_trial",registry$protocols[[1L]]$compiled$timeline)
      indices<-which(vapply(trials,`[[`,logical(1),"scored"))[-1L]
      data$outcome[indices]<-"timeout";data$first_correct[indices]<-"false"
      for(field in c("first_code","final_code","first_response_ms","final_correct_ms"))data[[field]][indices]<-""
    }
    if(incomplete)data<-data[-nrow(data),,drop=FALSE]
    file<-tempfile("original-cohort-",fileext=".csv");on.exit(unlink(file),add=TRUE)
    utils::write.table(data,file,sep=",",row.names=FALSE,col.names=TRUE,quote=TRUE,qmethod="double",eol="\n",fileEncoding="UTF-8")
    original<-brohn_store_object(store,path=file,media_type="text/csv")
    source<-list(id=brohn_id("dataset"),revision=1L,hash=original$hash,origin="sample",registry_object_hash=registry_object$hash)
    analysis<-brohn_import_task_trials(brohn_read_table(file,"csv",20000L),m,d,source,registry)
    publish(analysis,title=paste("Original",person,session,attempt))
  }
  a<-source_report();b<-source_report(session="S2");c<-source_report(person="Q",mean_ms=3)
  list(study=study,reports=list(a,b,c),publish=publish,source_report=source_report,registry=registry)
}
brohn_original_cohort_map <- function(attempts) {
  map<-brohn_task_cohort_identity_rows(attempts);map$linkage_statement<-"Original fixture participant register and session log were explicitly reviewed."
  map$participants<-lapply(map$participants,function(p){p$person_id<-p$participant_id;p})
  map$sessions<-lapply(map$sessions,function(s){s$session_id<-s$source_session_id;s});map
}
