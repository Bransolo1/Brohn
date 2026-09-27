# Exact historical distribution prerequisites with explicit server-side authority.
# Existing untagged distribution jobs retain their existing adapter.
.brohn_rpk_distribution_schema <- "brohn-report-package-distribution-job/0.1"
.brohn_rpk_distribution_choice_schema <- "brohn-report-package-distribution-job/0.2"
.brohn_rpk_distribution_admission <- function(request) {
  choice<-identical(request$schema,.brohn_rpk_distribution_choice_schema)
  brohn_require(choice||identical(request$schema,.brohn_rpk_distribution_schema),"The saved distribution request profile is unavailable.")
  if(choice){
    brohn_require(identical(request$source_admission,"task-choice-findings/0.1")&&
      identical(request$preparation_implementation_ref$profile,"saved-explicit-distribution/0.2"),"The choice response preparation lost its exact source admission.")
    return(request$source_admission)
  }
  brohn_require(!"source_admission" %in% names(request),"An earlier response preparation cannot acquire new source admission.")
  if(is.null(request$preparation_implementation_ref))"gaze-explicit-paired-findings/0.1"else{
    brohn_require(identical(request$preparation_implementation_ref$profile,"saved-explicit-distribution/0.1"),"The earlier response preparation has an incompatible implementation profile.")
    "task-findings/0.1"
  }
}
.brohn_rpk_distribution_implementation <- function(source_admission="task-findings/0.1") {
  brohn_require(source_admission %in% c("task-findings/0.1","task-choice-findings/0.1"),"Choose a supported pinned distribution implementation.")
  result<-list(profile=if(source_admission=="task-choice-findings/0.1")"saved-explicit-distribution/0.2"else"saved-explicit-distribution/0.1",
  sources=.brohn_rpk_loaded,distribution_sources=.brohn_ed_loaded,
  runtime=list(R=as.character(getRversion()),jsonlite=as.character(utils::packageVersion("jsonlite")),digest=as.character(utils::packageVersion("digest"))))
  if(source_admission=="task-choice-findings/0.1")result$source_admission<-source_admission
  result
}
.brohn_rpk_distribution_implementation_ref <- function(source_admission="task-findings/0.1") {
  x<-.brohn_rpk_distribution_implementation(source_admission);list(profile=x$profile,hash=brohn_hash(x))
}
.brohn_rpk_distribution_request <- function(store,report_ref,implementation_ref=NULL,source_admission=NULL) {
  if(is.null(source_admission))source_admission<-if(is.null(implementation_ref))"gaze-explicit-paired-findings/0.1"else"task-findings/0.1"
  choice<-identical(source_admission,"task-choice-findings/0.1")
  brohn_require(source_admission %in% c("gaze-explicit-paired-findings/0.1","task-findings/0.1","task-choice-findings/0.1")&&
    identical(is.null(implementation_ref),identical(source_admission,"gaze-explicit-paired-findings/0.1")),"Pin the implementation for this exact distribution source admission.")
  authority<-brohn_report_package_queue_authority(store,"explicit_distributions",report_ref$project_id)
  m<-.brohn_rpk_report_metadata(store,report_ref);.brohn_rpk_report_proof(store,m,source_admission=source_admission)
  brohn_require(identical(m$kind,"questionnaire"),"Choose a saved explicit-response report.")
  result<-list(schema=if(choice).brohn_rpk_distribution_choice_schema else .brohn_rpk_distribution_schema,project_id=report_ref$project_id,report_ref=report_ref,
    result_object=m$result_object,artifact=m$questionnaire_artifact,implementation=.brohn_rpk_loaded,distribution_implementation=.brohn_ed_loaded,authority=authority)
  if(!is.null(implementation_ref)){
    brohn_require(.brohn_rpk_same(implementation_ref,.brohn_rpk_distribution_implementation_ref(source_admission)),"The pinned response preparation changed. Prepare these choices as a new version.")
    result$preparation_implementation_ref<-implementation_ref
  }
  if(choice)result$source_admission<-source_admission
  result
}
.brohn_rpk_latest_job <- function(store,operation,fingerprint) {
  rows<-DBI::dbGetQuery(store$con,"SELECT * FROM jobs WHERE operation=? AND json_extract(request_json,'$.content_fingerprint')=? ORDER BY created_at DESC,rowid DESC LIMIT 1",params=list(operation,fingerprint))
  if(!nrow(rows))NULL else .brohn_store_job(rows)
}
brohn_queue_explicit_distributions_ref <- function(store,report_ref,retry=FALSE,implementation_ref=NULL,source_admission=NULL) {
  r<-.brohn_rpk_distribution_request(store,report_ref,implementation_ref,source_admission)
  r$content_fingerprint<-brohn_hash(r[setdiff(names(r),"authority")])
  brohn_store_batch(store,function(){
    old<-.brohn_rpk_latest_job(store,"explicit_distributions",r$content_fingerprint)
    if(!is.null(old)&&(!isTRUE(retry)||old$status %in% c("queued","running","succeeded")))return(old)
    brohn_enqueue_job(store,"explicit_distributions",r,paste0("report-distribution:",r$content_fingerprint,if(isTRUE(retry))paste0(":",brohn_id("retry"))else""))
  })
}
brohn_report_distribution_input <- function(store,job,verify=FALSE) {
  store<-brohn_report_package_job_authorize(store,job)
  r<-job$request;admission<-.brohn_rpk_distribution_admission(r);choice<-identical(admission,"task-choice-findings/0.1")
  fields<-c("schema","project_id","report_ref","result_object","artifact","implementation","distribution_implementation","authority","content_fingerprint")
  brohn_fields(r,c(fields,if(choice)c("source_admission","preparation_implementation_ref")),if(!choice)"preparation_implementation_ref"else character(),label="Exact distribution request")
  brohn_require(identical(job$operation,"explicit_distributions")&&
    .brohn_rpk_same(r$implementation,.brohn_rpk_loaded)&&.brohn_rpk_same(r$distribution_implementation,.brohn_ed_loaded),"Rebuild saved distributions with the current installation.")
  if(!is.null(r$preparation_implementation_ref))brohn_require(.brohn_rpk_same(r$preparation_implementation_ref,.brohn_rpk_distribution_implementation_ref(admission)),"The pinned response preparation changed.")
  brohn_require(identical(r$content_fingerprint,brohn_hash(r[setdiff(names(r),c("authority","content_fingerprint"))])),"The saved response preparation fingerprint changed.")
  m<-.brohn_rpk_report_metadata(store,r$report_ref);.brohn_rpk_report_proof(store,m,source_admission=admission)
  brohn_require(.brohn_rpk_same(m$result_object,r$result_object)&&.brohn_rpk_same(m$questionnaire_artifact,r$artifact),"The distribution prerequisite changed its pinned complete source.")
  list(schema="brohn-analysis-input/1.0",operation="explicit_distributions",project_id=r$project_id,report_ref=r$report_ref,content_fingerprint=r$content_fingerprint)
}
brohn_prepare_report_distribution_execution <- function(store,job,input,scratch) {
  store<-brohn_report_package_job_authorize(store,job);brohn_require(.brohn_rpk_same(input,brohn_report_distribution_input(store,job,FALSE)),"Distribution source input changed.")
  .brohn_rpk_check_code(job$request$implementation)
  admission<-.brohn_rpk_distribution_admission(job$request)
  m<-.brohn_rpk_source_metadata(store,list(job$request$report_ref),source_admission=admission);handle<-.brohn_rpk_hold_sources(store,m);ok<-FALSE
  on.exit(if(!ok).brohn_rpk_release(handle),add=TRUE)
  ref<-job$request$report_ref
  source<-.brohn_questionnaire_index_source(store,ref$id,ref$revision,ref$body_hash,ref$project_id,TRUE)
  if(identical(admission,"task-choice-findings/0.1")){
    complete<-.brohn_rpk_complete_sources(store,handle)
    brohn_require(length(complete$reports)==1L,"Response preparation requires its one complete original report.")
    brohn_validate_complete_report_analysis(complete$reports[[1L]][c("ref","saved_body","complete_analysis")],admission)
  }
  result<-list(schema="brohn-analysis-input/1.0",operation="explicit_distributions",project_id=ref$project_id,report_package_distribution=TRUE,
    index_input=list(schema="brohn-questionnaire-index-input/1.0",binding=source$binding,report=source$report$body,artifact_path=source$artifact_path))
  brohn_report_package_sources_current(store,handle);ok<-TRUE;list(input=result,handle=handle)
}
brohn_release_report_distribution_sources <- function(handle) .brohn_rpk_release(handle)
brohn_publish_report_distribution <- function(store,output,scratch,job,input,output_path) {
  store<-brohn_report_package_job_authorize(store,job,"publish");.brohn_publication_job(store,job)
  .brohn_publication_output_identity(output,c(.brohn_rpk_loaded,.brohn_ed_loaded))
  prepared<-brohn_prepare_report_distribution_execution(store,job,brohn_report_distribution_input(store,job,FALSE),scratch)
  on.exit(.brohn_rpk_release(prepared$handle),add=TRUE)
  output_guard<-.brohn_qexplorer_hold(output_path,file.info(output_path)$size);on.exit(.brohn_qexplorer_release(output_guard),add=TRUE)
  brohn_require(.brohn_rpk_same(prepared$input,input)&&.brohn_rpk_same(brohn_read_json_file(output_path),output),"Distribution source or worker output changed before publication.")
  result<-output$report$explicit_distributions
  brohn_require(identical(result$schema,"brohn-explicit-distributions/1.0")&&.brohn_rpk_same(result$binding,input$index_input$binding)&&nchar(brohn_json(result),type="bytes")<=8*1024^2,"The complete saved distribution exceeds its profile or source binding.")
  ref<-job$request$report_ref;source<-.brohn_questionnaire_index_source(store,ref$id,ref$revision,ref$body_hash,ref$project_id,FALSE)
  request<-list(report_id=ref$id,report_revision=ref$revision,report_hash=ref$body_hash,project_id=ref$project_id,catalog_hash=source$catalog_hash,
    artifact=source$artifact,result_object=source$result_object,binding=source$binding,implementation=.brohn_ed_loaded)
  id<-paste0("explicit-distributions-",sub("^job[_-]","",job$id))
  body<-list(schema="brohn-saved-explicit-distributions/1.0",id=id,report_id=ref$id,origin=input$index_input$binding$origin,request=request,result=result,
    created_at=brohn_now(),processing=list(job_id=job$id,attempt=job$attempt,code_hashes=output$code_identity,authority_profile="original_queued_actor_and_sealed_source/0.1"))
  if(!is.null(job$request$preparation_implementation_ref))body$preparation_implementation_ref<-job$request$preparation_implementation_ref
  if(identical(job$request$schema,.brohn_rpk_distribution_choice_schema))body$source_admission<-job$request$source_admission
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-distributions.json"));committed<-FALSE
  on.exit(brohn_close_publication(document$guard,committed),add=TRUE)
  receipt<-brohn_store_batch(store,function(){
    brohn_report_package_sources_current(store,prepared$handle);brohn_report_package_job_fence(store,job);.brohn_cm_guard_check(list(output_guard))
    body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"explicit_distributions",id,body,0L,ref$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(explicit_distributions_id=id,report_id=ref$id,output_hash=body$result_object$hash))
  });committed<-TRUE;receipt
}
