# Asynchronous named map saves. Only bounded metadata is resolved on queue;
# original bytes and arithmetic are verified by the existing background service.
.brohn_clock_map_save_files <- c("R/platform-clock-authority.R","R/platform-clock-map-save.R","R/platform-clock-map.R","R/platform-clock-preview.R","R/platform-clock-jobs.R",
  "scripts/workers/clock_affine.py","scripts/workers/validate_clock_preview_math.py")
.brohn_clock_map_save_loaded <- setNames(lapply(.brohn_clock_map_save_files,function(p)digest::digest(file=p,algo="sha256")),.brohn_clock_map_save_files)
.brohn_cms_code <- function()brohn_require(all(vapply(names(.brohn_clock_map_save_loaded),function(p)
  identical(digest::digest(file=p,algo="sha256"),.brohn_clock_map_save_loaded[[p]]),logical(1))),"Clock save implementation changed. Restart services before saving.")
brohn_clock_map_save_metadata <- function(store,request) {
  r<-request;brohn_fields(r,c("schema","action","project_id","preview","previous","title","map_id","expected_revision","operation_id","implementation","authority"),label="Named clock save request")
  brohn_hosted_require_session(store);brohn_hosted_require_project(store,r$project_id);brohn_project(store,r$project_id)
  brohn_require(identical(r$schema,"brohn-clock-map-save-job/0.1")&&r$action %in% c("save","rename")&&brohn_text(r$title,240)&&
    brohn_valid_id(r$map_id)&&brohn_valid_id(r$operation_id)&&brohn_number(r$expected_revision,0,1e9,TRUE)&&
    .brohn_cm_same(r$implementation,.brohn_clock_map_save_loaded),"Retain the exact named save operation, implementation and expected revision.")
  .brohn_cms_code();preview<-.brohn_cm_record(store,"clock_preview",r$preview,r$project_id,FALSE)
  previous<-NULL
  if(r$expected_revision>0L){
    .brohn_cm_ref_valid(r$previous)
    brohn_require(identical(r$previous$id,r$map_id)&&r$previous$revision==r$expected_revision,"The previous map must be the exact edited revision.")
    previous<-.brohn_cm_record(store,"clock_map",r$previous,r$project_id,FALSE)
  }else brohn_require(is.null(r$previous),"New maps cannot substitute a previous version.")
  if(r$action=="rename")brohn_require(!is.null(previous)&&.brohn_cm_same(r$preview,previous$body$preview),"Renaming retains the previous map's exact accepted preview.")
  list(preview=preview,previous=previous)
}
brohn_queue_clock_map_save <- function(store,preview_ref,title,project_id,map_id,expected_revision,operation_id,action="save") {
  previous<-if(expected_revision>0L)brohn_get_entity(store,"clock_map",map_id,expected_revision)else NULL
  brohn_require(expected_revision==0L||!is.null(previous),"Reopen the existing map version before editing.")
  r<-list(schema="brohn-clock-map-save-job/0.1",action=action,project_id=project_id,preview=preview_ref,
    previous=if(is.null(previous))NULL else .brohn_cm_ref(previous),title=title,map_id=map_id,expected_revision=expected_revision,
    operation_id=operation_id,implementation=.brohn_clock_map_save_loaded,authority=brohn_clock_queue_authority(store,"save_clock_map",project_id))
  brohn_clock_map_save_metadata(store,r)
  key<-paste("clock-map-save",project_id,operation_id,sep=":")
  old<-DBI::dbGetQuery(store$con,"SELECT id FROM jobs WHERE idempotency_key=?",params=list(key))
  if(nrow(old)){prior<-brohn_get_job(store,old$id[[1L]])
    brohn_require(identical(prior$operation,"save_clock_map")&&.brohn_cm_same(prior$request[setdiff(names(prior$request),"authority")],r[setdiff(names(r),"authority")]),
      "This save operation already belongs to another frozen request. Recover its original job.")
    return(prior)}
  brohn_enqueue_job(store,"save_clock_map",r,key)
}
brohn_clock_map_save_input <- function(store,job,verify=TRUE) {
  brohn_require(identical(job$operation,"save_clock_map"),"Choose a registered clock map save.")
  store<-brohn_clock_job_authorize(store,job)
  r<-job$request;meta<-brohn_clock_map_save_metadata(store,r)
  scratch<-file.path(store$root,"scratch");dir.create(scratch,showWarnings=FALSE)
  runtime<-brohn_clock_preview_runtime(scratch)
  accepted<-brohn_clock_map_preview(store,r$preview,r$project_id,runtime,fresh=r$action=="save",verify=verify)
  refs<-accepted$input$source_objects
  if(!is.null(meta$previous)){
    old<-brohn_clock_map_record(store,r$previous,r$project_id,runtime,verify)
    brohn_require(.brohn_cm_same(old$body$family,.brohn_cm_family(accepted$record$body$request,accepted$record$body$result)),"Revisions retain the same original recording family.")
    old_preview<-.brohn_cm_record(store,"clock_preview",old$body$preview,r$project_id,verify)
    refs<-c(refs,lapply(list(old$body$result_object,old_preview$body$result_object),function(a)list(hash=a$hash,bytes=a$size)))
  }
  list(schema="brohn-analysis-input/1.0",operation="save_clock_map",project_id=r$project_id,binding=r,
    accepted_preview=accepted$record$body,original_input=accepted$original_input,source_objects=refs)
}
.brohn_cms_result <- function(input,runtime)list(schema="brohn-clock-map-save-check/0.1",request_hash=brohn_hash(input$binding),
  preview=input$binding$preview,previous=input$binding$previous,result_hash=brohn_hash(input$accepted_preview$result),validator=runtime$identity,
  scope="accepted_preview_consistency_no_new_scientific_scoring")
brohn_analyse_clock_map_save <- function(input,scratch) {
  .brohn_cms_code();runtime<-brohn_clock_preview_runtime(scratch)
  brohn_validate_clock_preview_result(input$accepted_preview$result,input$original_input,runtime)
  list(clock_map_save=.brohn_cms_result(input,runtime))
}
brohn_publish_clock_map_save <- function(store,output,scratch,job,input,output_path) {
  store<-brohn_clock_job_authorize(store,job,"publish")
  .brohn_publication_output_identity(output,.brohn_clock_map_save_loaded);.brohn_publication_job(store,job)
  guards<-brohn_hold_signal_value_sources(store,input);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  guard<-.brohn_qexplorer_hold(output_path,file.info(output_path)$size);on.exit(.brohn_qexplorer_release(guard),add=TRUE)
  runtime<-brohn_clock_preview_runtime(scratch)
  brohn_require(.brohn_cm_same(input,brohn_clock_map_save_input(store,job))&&.brohn_cm_same(output,brohn_read_json_file(output_path))&&
    .brohn_cm_same(output$report$clock_map_save,.brohn_cms_result(input,runtime)),"The save command, source authority or verified worker output changed.")
  r<-job$request
  transaction<-list(fence=function(){.brohn_cms_code();brohn_clock_job_fence(store,job);.brohn_cm_guard_check(c(guards,list(guard)))},
    complete=function(saved){brohn_clock_job_fence(store,job)
      brohn_complete_job(store,job$id,job$worker,job$token,list(clock_map=.brohn_cm_ref(saved),output_hash=saved$body$result_object$hash,
        operation_id=r$operation_id,action=r$action))})
  if(r$action=="save")brohn_save_clock_map(store,r$preview,r$title,r$project_id,r$map_id,r$expected_revision,r$operation_id,runtime,.transaction=transaction)
  else brohn_rename_clock_map(store,r$map_id,r$expected_revision,r$title,r$project_id,r$operation_id,runtime,.transaction=transaction)
  brohn_get_job(store,job$id)
}
