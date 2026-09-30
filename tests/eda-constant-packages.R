# Genuine joined review/preparation/export on a fresh copy of frozen native sources.
# Rscript this-file <config.json>; scientific workers must not run in this phase.
args<-commandArgs(TRUE);stopifnot(length(args)==1L)
cfg<-jsonlite::fromJSON(args[[1L]],simplifyVector=FALSE)
setwd(cfg$checkout);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("R/platform-report-package-views.R",encoding="UTF-8")
local({
 store<-brohn_open_store(file.path(cfg$out,"workspace"));out<-cfg$out
 checks<-list();packages<-list();reviews<-list();passed<-FALSE;failure<-NULL
 check<-function(label,value){if(!isTRUE(value))stop(label,call.=FALSE);checks[[length(checks)+1L]]<<-label;cat("PASS",label,"\n")}
 reject<-function(expr)inherits(tryCatch({force(expr);NULL},error=function(e)e),"error")
 prior<-brohn_read_json_file(file.path(out,"native-results.json"))
 refs<-c(prior$reports,prior$original_reports)
 before_jobs<-DBI::dbGetQuery(store$con,"SELECT id,operation,status FROM jobs ORDER BY id")
 on.exit({
  for(j in brohn_list_jobs(store,limit=1000L))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id)
  brohn_write_json_file(list(schema="brohn-eda-constant-native-package-checks/0.1",passed=passed,checks=checks,failure=failure,packages=packages,reviews=reviews,
   scope="Actual native read-only review, preparation and package execution. Synthetic original source conservation; no scientific reanalysis, physical-device or construct qualification."),file.path(out,"results.json"))
  brohn_close_store(store)
 },add=TRUE)
 process<-function(expected=NULL){j<-brohn_claim_job(store,"eda-constant-package-qa",lease_seconds=60L)
  stopifnot(!is.null(j),j$operation %in% c("eda_continuous_review","eda_display","explicit_distributions","report_package"))
  if(!is.null(expected))stopifnot(identical(j$id,expected))
  brohn_process_job(store,j,timeout_seconds=300L);done<-brohn_get_job(store,j$id)
  if(done$status!="succeeded")stop(j$operation,": ",brohn_json(done$error));done}
 report<-function(key){r<-refs[[key]];brohn_get_entity(store,"report",r$id,r$revision)}
 tryCatch({
  for(key in c("levels-us","mixed")){
   r<-report(key);status<-if(key=="mixed")"computed"else"descriptive_only"
   cell<-Filter(function(x)identical(x$status,status),r$body$analysis$recordings)[[1L]]
   selected<-c(cell[c("recording_id","segment_id","channel")],list(start_s=.brohn_ecr_shortest(cell$start_time_s),end_s=.brohn_ecr_shortest(cell$end_time_s)))
   job<-brohn_queue_eda_continuous_review(store,r$id,r$revision,brohn_hash(r$body),selected)
   done<-process(job$id);saved<-brohn_eda_continuous_review_record(store,done$result$eda_continuous_review_id,r$id,r$project_id)
   check(paste(key,"actual standalone new-version review"),saved$body$request$recipe=="saved-continuous-eda-review/1.1"&&saved$body$result$schema=="brohn-eda-continuous-review/1.1"&&done$attempt==1L)
   model<-saved$body$result
   if(status=="descriptive_only")check("Constant review retains all coordinates without processed points",model$status=="raw_description_only"&&model$counts$selected_coordinate_rows==1200L&&model$counts$selected_numerical_candidate_rows==0L&&!length(model$rows)&&!length(model$processed_components))
   else check("Ordinary1.1 review retains genuine processed waveform",model$status=="available"&&length(model$series$clean_us)>0L)
   reviews[[key]]<-list(id=saved$id,hash=brohn_hash(saved$body),exports=saved$body$exports)
  }
  count<-nrow(DBI::dbGetQuery(store$con,"SELECT id FROM jobs"))
  check("Legacy preparation explicitly refuses new scientific grammar",reject(brohn_queue_eda_display(store,refs[["levels-us"]],preparation_profile="saved-eda-display/0.1")))
  check("Version refusal does not enqueue work",nrow(DBI::dbGetQuery(store$con,"SELECT id FROM jobs"))==count)
  selected<-refs[c("levels-us","level-siemens","mixed","continuous","event","liking")]
  choices<-lapply(selected,function(r)brohn_report_package_report_choice(store,r))
  req<-list(schema="brohn-report-package-intent-request/0.1",study_id=report("levels-us")$body$study_id,project_id="default",title="Constant, ordinary and explicit findings",
   report_refs=unname(selected),requested_sections=unname(.brohn_rpv_default_sections(choices)),eda_display_requests=list(),
   contents_policy=list(profile="complete-findings/0.1",audience="research_team",identifier_mode="package_aliases",stimulus_images="excluded_by_choice",complete_selected_numerical_evidence=TRUE,include_original_evidence=FALSE,include_raw_recordings=FALSE),
   limits_profile="controlled-task-choice-eda-report-package/0.1",renderer_profile="controlled-gaze-explicit-task-choice-eda-paired/0.2")
  finish<-function(intent){for(attempt in seq_len(10L)){
   intent<-brohn_continue_report_package_intent(store,intent$intent_ref)
   if(intent$status=="waiting_for_display"){
    pending<-Filter(function(d)d$status %in% c("queued","running"),intent$dependencies)
    stopifnot(length(pending)>0L);for(d in pending)process(d$job_id)
   }else if(intent$status=="assembly_queued"){
    process();return(brohn_read_report_package_intent(store,intent$intent_ref$id,intent$request$project_id))
   }else stop(brohn_json(intent))
  };stop("Package preparation did not settle")}
  for(key in c("mixed-all","evidence-only")){
   if(key=="evidence-only"){req$title<-"Complete evidence without figures";req$requested_sections<-list()}
   intent<-brohn_save_report_package_intent(store,paste0("constant-",key),req)
   intent<-finish(intent);check(paste(key,"new0.2 native package succeeds"),intent$status=="succeeded")
   s<-brohn_get_entity(store,"report_package_selection",intent$selection_ref$id,intent$selection_ref$revision)$body
   eda<-Filter(function(x)x$adapter=="eda-display",s$prepared_sources)
   check(paste(key,"one exact0.2 preparation per old or new EDA source"),length(eda)==5L&&all(vapply(eda,function(x)x$implementation_ref$profile=="saved-eda-display/0.2",logical(1))))
   opened<-brohn_open_report_package_resources(store,intent$package_ref,"default")
   tryCatch({
    current<-brohn_report_package_resources_current(store,opened$handle)
    destination<-file.path(out,key);dir.create(destination)
    producer<-brohn_get_job(store,opened$record$body$processing$job_id)
    sources<-.brohn_rpk_complete_sources(store,opened$handle$source_handle)
    bundle<-c(list(schema="brohn-report-package-render-input/0.1",selection=s),sources,list(implementation=producer$request$implementation,limits=producer$request$limits))
    brohn_eda_write_json_file(bundle,file.path(destination,"original-source-bundle.json"),maximum=128*1024^2)
    artifacts<-list()
    for(kind in names(current$artifacts)){a<-current$artifacts[[kind]];path<-file.path(destination,a$file);stopifnot(file.copy(a$path,path))
     check(paste(key,kind,"matches exact published bytes"),identical(digest::digest(file=path,algo="sha256"),a$hash));artifacts[[kind]]<-a[c("file","hash","bytes")]}
    packages[[key]]<-list(intent_ref=intent$intent_ref,selection_ref=intent$selection_ref,package_ref=intent$package_ref,artifacts=artifacts)
   },finally=brohn_release_report_package_resources(opened$handle))
  }
  for(r in refs)check(paste("Original scientific report preserved",r$id),identical(brohn_hash(brohn_get_entity(store,"report",r$id,r$revision)$body),r$body_hash))
  after<-DBI::dbGetQuery(store$con,"SELECT id,operation,status FROM jobs ORDER BY id")
  new<-after[!after$id %in% before_jobs$id,,drop=FALSE]
  check("Every added job is read-only and succeeds",all(new$operation %in% c("eda_continuous_review","eda_display","explicit_distributions","report_package"))&&all(new$status=="succeeded"))
  check("Original job states remain unchanged",identical(after[after$id %in% before_jobs$id,]$status,before_jobs$status))
  passed<-TRUE
 },error=function(e){failure<<-conditionMessage(e);stop(e)})
 cat(length(checks),"joined native package checks passed\n")
})
