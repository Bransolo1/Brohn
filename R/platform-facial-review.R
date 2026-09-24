# Unwired saved-facial explorer domain. No inference or model updates.
.brohn_freview_recipe <- "saved-native-facial-review/1.0"
.brohn_freview_schema <- "brohn-saved-facial-review/1.0"
.brohn_freview_files <- c("R/platform-facial-review.R","scripts/workers/facial_review.py","scripts/workers/vision_explorer.py","scripts/workers/vision.py","scripts/workers/media_pixels.py","scripts/readiness/facial-runtime.json")
.brohn_freview_loaded <- stats::setNames(lapply(.brohn_freview_files,function(path)digest::digest(file=path,algo="sha256")),.brohn_freview_files)
.brohn_freview_hash <- function(x) brohn_text(x,64)&&grepl("^[a-f0-9]{64}$",x)
.brohn_freview_source <- function(store,report_id,report_revision,report_hash,project_id,verify=TRUE) {
  brohn_require(brohn_valid_id(report_id)&&brohn_number(report_revision,1,1e9,TRUE)&&.brohn_freview_hash(report_hash)&&brohn_text(project_id,96),"Choose the exact saved facial report and project.")
  catalog_hash<-.brohn_qexplorer_catalog(store,"report",report_id,report_revision,project_id);brohn_project(store,project_id)
  report<-brohn_get_entity(store,"report",report_id,report_revision);b<-report$body;a<-b$analysis;p<-b$provenance
  brohn_require(identical(b$id,report_id)&&identical(brohn_hash(b),report_hash)&&identical(a$kind,"facial_expression")&&identical(a$schema,"brohn-facial-expression-result/1.0")&&identical(a$status,"completed"),"This exact report has no supported saved native facial outputs.")
  brohn_require(identical(b$dataset_id,p$dataset_id)&&brohn_number(p$dataset_revision,1,1e9,TRUE)&&.brohn_freview_hash(p$dataset_hash),"The facial report has no exact frozen dataset provenance.")
  dataset_catalog<-.brohn_qexplorer_catalog(store,"dataset",p$dataset_id,p$dataset_revision,project_id)
  dataset<-brohn_get_entity(store,"dataset",p$dataset_id,p$dataset_revision)
  brohn_require(identical(brohn_hash(dataset$body),p$dataset_hash)&&identical(dataset$body$modality,"video")&&
    identical(brohn_hash(dataset$body$source),brohn_hash(p$source))&&identical(brohn_hash(dataset$body$metadata),brohn_hash(p$mapping))&&
    identical(a$source$sha256,p$source$hash),"The facial report's source, dataset or mapping changed.")
  brohn_require(brohn_number(a$source$bytes,1,512*1024^2,TRUE)&&identical(as.numeric(a$source$bytes),as.numeric(p$source$size)),"The saved facial byte count is inconsistent.")
  camera<-brohn_camera_analysis_report_source(store,report,verify=verify)
  artifacts<-Filter(function(x)x$kind%in%c("facial-observations","facial-values"),a$artifacts)
  brohn_require(length(artifacts)==2L&&identical(sort(vapply(artifacts,`[[`,character(1),"kind")),c("facial-observations","facial-values")),"Both complete original facial artifacts are required.")
  artifacts<-lapply(artifacts,function(x){brohn_require(.brohn_freview_hash(x$hash)&&brohn_number(x$size,1,64*1024^2,TRUE)&&isTRUE(x$complete),"Original facial artifact is incomplete.");list(kind=x$kind,sha256=x$hash,bytes=x$size)})
  paths<-lapply(artifacts,function(x)brohn_object_path(store,x$sha256,verify=verify))
  refs<-c(lapply(artifacts,function(x)list(hash=x$sha256,bytes=x$bytes)),list(list(hash=p$source$hash,bytes=p$source$size)))
  if(!is.null(b$result_object))refs<-c(refs,list(list(hash=b$result_object$hash,bytes=b$result_object$size)))
  if(!is.null(camera))refs<-c(refs,camera$source_refs)
  refs<-refs[!duplicated(vapply(refs,`[[`,character(1),"hash"))]
  if(!is.null(b$result_object)&&verify){retained<-brohn_read_json_file(brohn_object_path(store,b$result_object$hash));brohn_require(identical(retained$schema,"brohn-analysis-output/1.0")&&
    identical(brohn_hash(retained$report),brohn_hash(b[setdiff(names(b),"result_object")])),"Saved facial report differs from its retained worker result.")}
  brohn_require(is.list(a$parameters)&&is.list(a$engine)&&is.list(a$quality)&&isTRUE(a$quality$pts_validated)&&identical(a$quality$identity_tracking,FALSE),"Saved video clock/model declarations are unavailable.")
  binding<-list(workspace_id=store$workspace_id,project_id=project_id,report_id=report_id,report_revision=report_revision,report_hash=report_hash,
    report_catalog_hash=catalog_hash,dataset_id=p$dataset_id,dataset_revision=p$dataset_revision,dataset_hash=p$dataset_hash,dataset_catalog_hash=dataset_catalog,
    original_source=list(hash=p$source$hash,size=p$source$size),artifacts=artifacts,camera_authority=camera,parameters_hash=brohn_hash(a$parameters),engine_hash=brohn_hash(a$engine),origin=b$origin)
  list(report=report,binding=binding,artifacts=artifacts,artifact_paths=paths,source_objects=refs,result_object=b$result_object,catalog_hash=catalog_hash,dataset_catalog_hash=dataset_catalog)
}
brohn_prepare_facial_review <- function(store,report_id,report_revision,report_hash,project_id) {
  source<-.brohn_freview_source(store,report_id,report_revision,report_hash,project_id,FALSE)
  list(schema="brohn-facial-review-request/1.0",recipe=.brohn_freview_recipe,project_id=project_id,report_id=report_id,report_revision=report_revision,report_hash=report_hash,
    binding=source$binding,binding_json=brohn_json(source$binding),binding_sha256=brohn_hash(source$binding),artifacts=source$artifacts,source_objects=source$source_objects,result_object=source$result_object,implementation=.brohn_freview_loaded)
}
brohn_queue_facial_review <- function(store,report_id,report_revision,report_hash,project_id,rebuild=FALSE) {
  brohn_require(is.logical(rebuild)&&length(rebuild)==1L&&!is.na(rebuild),"Choose whether to reuse or rebuild this saved facial view.")
  r<-brohn_prepare_facial_review(store,report_id,report_revision,report_hash,project_id)
  brohn_store_batch(store,function(){
    brohn_require(identical(.brohn_qexplorer_catalog(store,"report",report_id,report_revision,project_id),r$binding$report_catalog_hash)&&
      identical(.brohn_qexplorer_catalog(store,"dataset",r$binding$dataset_id,r$binding$dataset_revision,project_id),r$binding$dataset_catalog_hash),"Saved video authority changed before queueing.")
    brohn_project(store,project_id)
    key<-paste0("facial-review:",brohn_hash(r))
    if(!rebuild){old<-DBI::dbGetQuery(store$con,"SELECT * FROM jobs WHERE operation='facial_review' AND request_hash=? ORDER BY created_at DESC,rowid DESC LIMIT 1",params=list(.brohn_store_hash(charToRaw(.brohn_store_json(r)))))
      if(nrow(old))return(.brohn_store_job(old))}
    brohn_enqueue_job(store,"facial_review",r,if(rebuild)paste0(key,":",brohn_id("rebuild"))else key)
  })
}
brohn_facial_review_input <- function(store,job) {
  r<-job$request
  brohn_require(identical(job$operation,"facial_review"),"Choose a saved facial index job.")
  expected<-brohn_prepare_facial_review(store,r$report_id,r$report_revision,r$report_hash,r$project_id)
  brohn_require(identical(brohn_hash(expected),brohn_hash(r))&&all(vapply(names(r$implementation),function(path)identical(digest::digest(file=path,algo="sha256"),r$implementation[[path]]),logical(1))),"Saved video source or explorer code changed; prepare a new view.")
  s<-.brohn_freview_source(store,r$report_id,r$report_revision,r$report_hash,r$project_id,TRUE);a<-s$report$body$analysis
  list(schema="brohn-analysis-input/1.0",operation="facial_review",project_id=r$project_id,
    source_objects=r$source_objects,facial_review_input=list(schema="brohn-facial-review-request/1.0",operation="build",
      artifacts=Map(function(x,path)c(x,list(path=path)),s$artifacts,s$artifact_paths),analysis=a,binding_json=r$binding_json,binding_sha256=r$binding_sha256))
}
.brohn_freview_run <- function(request,directory,timeout=120) {
  brohn_require(dir.exists(directory),"Choose an existing owned explorer work directory.")
  in_path<-file.path(directory,"vision-explorer-request.json");out_path<-file.path(directory,"vision-explorer-result.json")
  brohn_write_json_file(request,in_path)
  process<-processx::run(.brohn_publication_python(),c("-B","scripts/workers/facial_review.py","--request",in_path,"--output",out_path),
    timeout=timeout,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(file.exists(out_path),paste("Facial explorer produced no response.",substr(process$stderr,1,1200)))
  result<-brohn_read_json_file(out_path,2*1024^2)
  brohn_require(process$status==0L&&!identical(result$status,"error"),paste("Facial explorer needs attention:",brohn_default(result$error$message,substr(process$stderr,1,1000))))
  result
}
brohn_analyse_facial_review <- function(input,scratch) {
  brohn_require(identical(input$schema,"brohn-analysis-input/1.0")&&identical(input$operation,"facial_review"),"Unsupported saved facial build input.")
  directory<-file.path(scratch,"artifacts");brohn_require(!dir.exists(directory)&&dir.create(directory),"Choose a fresh owned facial index directory.")
  request<-input$facial_review_input;request$index_path<-normalizePath(file.path(directory,"facial-review.sqlite"),winslash="/",mustWork=FALSE)
  list(facial_review=.brohn_freview_run(request,scratch,timeout=20*60))
}
.brohn_freview_guards <- function(store,request) {
  guards<-list();success<-FALSE;on.exit(if(!success)for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  refs<-lapply(request$source_objects,function(x)list(hash=x$hash,size=x$bytes))
  for(ref in refs)if(!is.null(ref))guards[[length(guards)+1L]]<-.brohn_qexplorer_hold(brohn_object_path(store,ref$hash,verify=FALSE),ref$size)
  success<-TRUE;guards
}
brohn_publish_facial_review <- function(store,output,scratch,job,input,output_path) {
  brohn_require(.Platform$OS.type=="windows"&&!RSQLite::sqliteIsTransacting(store$con),"Facial index publication needs the qualified native Windows guard outside a writer transaction.")
  .brohn_publication_output_identity(output,.brohn_freview_loaded);.brohn_publication_job(store,job)
  output_path<-.brohn_store_contained(store,output_path)
  brohn_require(file.exists(output_path)&&!dir.exists(output_path)&&identical(tolower(dirname(output_path)),tolower(normalizePath(scratch,winslash="/",mustWork=TRUE))),"Facial worker output leaves its owned attempt directory.")
  guards<-.brohn_freview_guards(store,job$request);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  brohn_require(identical(brohn_hash(input),brohn_hash(brohn_facial_review_input(store,job)))&&identical(brohn_hash(output),brohn_hash(brohn_read_json_file(output_path))),"Facial publication substituted its frozen input or output.")
  result<-output$report$facial_review;ref<-result$index;m<-result$manifest
  brohn_require(identical(result$schema,"brohn-facial-review-result/1.0")&&identical(result$status,"complete")&&identical(m$schema,"brohn-facial-review-index/1.0")&&
    identical(m$binding_sha256,job$request$binding_sha256)&&identical(m$binding_json,job$request$binding_json)&&
    identical(brohn_hash(m$parameters),brohn_hash(input$facial_review_input$analysis$parameters))&&identical(brohn_hash(m$engine),brohn_hash(input$facial_review_input$analysis$engine))&&
    brohn_number(ref$bytes,1,64*1024^2,TRUE),"Facial index changed its source/model/resource declaration.")
  path<-brohn_checked_artifact_path(store,ref$path,scratch)
  context<-.brohn_publication_stage(store,job,list(list(key="facial-review",kind="facial-review",path=path,sha256=ref$sha256,bytes=ref$bytes,media_type="application/vnd.sqlite3")))
  document<-NULL;committed<-FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);brohn_close_publication(context$guard,committed)},add=TRUE)
  verify_request<-list(schema="brohn-facial-review-request/1.0",operation="catalog",index_path=context$paths[["facial-review"]],index=ref,binding_sha256=job$request$binding_sha256)
  verify_dir<-file.path(scratch,"verify-index");brohn_require(dir.create(verify_dir),"Could not create owned index verification work directory.")
  verified<-.brohn_freview_run(verify_request,verify_dir)
  brohn_require(identical(brohn_hash(verified$manifest),brohn_hash(m)),"The staged index differs from its worker manifest.")
  index<-c(ref[setdiff(names(ref),c("path","sha256","bytes"))],context$descriptors[[1L]][c("hash","size")])
  id<-paste0("facial-review-",sub("^job_","",job$id))
  body<-list(schema=.brohn_freview_schema,id=id,recipe=.brohn_freview_recipe,request=job$request,request_hash=brohn_hash(job$request),
    binding=job$request$binding,index=index,manifest=m,created_at=brohn_now(),processing=list(job_id=job$id,attempt=job$attempt,
      worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity,publication=.brohn_publication_processing(context)))
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-facial-review.json"))
  receipt<-brohn_store_batch(store,function(){
    r<-job$request;brohn_project(store,r$project_id)
    brohn_require(identical(.brohn_qexplorer_catalog(store,"report",r$report_id,r$report_revision,r$project_id),r$binding$report_catalog_hash)&&
      identical(.brohn_qexplorer_catalog(store,"dataset",r$binding$dataset_id,r$binding$dataset_revision,r$project_id),r$binding$dataset_catalog_hash),"Original video authority changed before publication.")
    .brohn_freview_source(store,r$report_id,r$report_revision,r$report_hash,r$project_id,FALSE)
    for(g in guards).Call(g$native$check,g$pointer)
    .brohn_publication_register(store,context);body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"facial_review",id,body,0L,project_id=r$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(facial_review_id=id,report_id=r$report_id,index_hash=brohn_hash(body),artifact_hash=index$hash,output_hash=body$result_object$hash))
  });committed<-TRUE;receipt
}
brohn_close_facial_review <- function(opened) {
  a<-opened$authority
  if(is.environment(a)&&environmentIsLocked(a))for(g in a$guards).brohn_qexplorer_release(g)
  invisible(NULL)
}
brohn_begin_facial_review_open <- function(store,index_id,index_hash,report_id,report_revision,report_hash,project_id) {
  brohn_require(brohn_valid_id(index_id)&&.brohn_freview_hash(index_hash),"Choose the exact saved facial index.")
  record<-brohn_get_entity(store,"facial_review",index_id)
  brohn_require(!is.null(record)&&identical(record$project_id,project_id)&&identical(brohn_hash(record$body),index_hash),"This facial index is unavailable in the selected project.")
  b<-record$body;r<-b$request
  brohn_require(identical(b$schema,.brohn_freview_schema)&&identical(r$report_id,report_id)&&identical(as.numeric(r$report_revision),as.numeric(report_revision))&&identical(r$report_hash,report_hash),"The index belongs to another exact facial report.")
  source<-.brohn_freview_source(store,report_id,report_revision,report_hash,project_id,FALSE)
  brohn_require(identical(brohn_hash(source$binding),brohn_hash(b$binding))&&identical(brohn_hash(r),b$request_hash),"Facial index source authority changed.")
  job<-brohn_get_job(store,b$processing$job_id)
  brohn_require(identical(job$operation,"facial_review")&&identical(job$status,"succeeded")&&identical(job$result$facial_review_id,index_id)&&identical(job$result$index_hash,index_hash)&&
    identical(job$result$artifact_hash,b$index$hash)&&identical(job$result$output_hash,b$result_object$hash)&&identical(brohn_hash(job$request),b$request_hash),"Facial index has no matching completed publication receipt.")
  guards<-.brohn_freview_guards(store,r);success<-FALSE;on.exit(if(!success)for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  guards[[length(guards)+1L]]<-.brohn_qexplorer_hold(brohn_object_path(store,b$result_object$hash,verify=FALSE),b$result_object$size)
  path<-brohn_object_path(store,b$index$hash,verify=FALSE);guards[[length(guards)+1L]]<-.brohn_qexplorer_hold(path,b$index$size)
  context<-list(workspace_id=store$workspace_id,root=store$root,project_id=project_id,report_id=report_id,report_revision=report_revision,report_hash=report_hash,
    report_catalog=source$catalog_hash,dataset_id=b$binding$dataset_id,dataset_revision=b$binding$dataset_revision,dataset_catalog=source$dataset_catalog_hash,
    index_id=index_id,index_revision=record$revision,index_hash=index_hash,index_catalog=.brohn_qexplorer_catalog(store,"facial_review",index_id,record$revision,project_id))
  authority<-new.env(parent=emptyenv());authority$context<-context;authority$record<-record;authority$guards<-guards;authority$path<-path;authority$artifact_paths<-source$artifact_paths;authority$verified<-FALSE
  lockEnvironment(authority,bindings=TRUE);opened<-list(record=record,context=context,authority=authority)
  refs<-c(lapply(r$source_objects,function(x)list(hash=x$hash,size=x$bytes)),list(b$result_object,list(hash=b$index$hash,size=b$index$size)))
  files<-lapply(refs,function(ref)list(path=brohn_object_path(store,ref$hash,verify=FALSE),sha256=ref$hash,bytes=ref$size))
  payload<-brohn_json(files);payload_hash<-brohn_hash(files)
  index_request<-list(index_path=path,index=list(sha256=b$index$hash,bytes=b$index$size,manifest_sha256=b$index$manifest_sha256),binding_sha256=r$binding_sha256)
  code<-paste(c("import hashlib,importlib.util,json,os,sys;sys.path.insert(0,'scripts/workers')", "raw=sys.argv[1];items=json.loads(raw)",
    "for x in items:"," assert os.path.getsize(x['path'])==x['bytes'],'Saved source size changed'",
    " with open(x['path'],'rb') as f: assert hashlib.file_digest(f,'sha256').hexdigest()==x['sha256'],'Saved source digest changed'",
    "spec=importlib.util.spec_from_file_location('facial_review','scripts/workers/facial_review.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)",
    "with v.opened(json.loads(sys.argv[2])) as (_,manifest): manifest_hash=v.common.sha(v.encoded(manifest))",
    "print(json.dumps({'status':'verified','request_sha256':hashlib.sha256(raw.encode()).hexdigest(),'manifest_sha256':manifest_hash}))"),collapse="\n")
  process<-processx::process$new(.brohn_publication_python(),c("-B","-c",code,payload,brohn_json(index_request)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
  pending<-new.env(parent=emptyenv());pending$opened<-opened;pending$process<-process;pending$request_hash<-payload_hash
  pending$state<-new.env(parent=emptyenv());pending$state$owns_guards<-TRUE
  lockEnvironment(pending,bindings=TRUE);success<-TRUE;pending
}
brohn_cancel_facial_review_open <- function(pending) {
  if(is.environment(pending)&&environmentIsLocked(pending)&&isTRUE(pending$state$owns_guards)){
    if(pending$process$is_alive())pending$process$kill_tree()
    brohn_close_facial_review(pending$opened)
    state<-pending$state;state$owns_guards<-FALSE
  };invisible(NULL)
}
brohn_poll_facial_review_open <- function(store,pending) {
  brohn_require(is.environment(pending)&&environmentIsLocked(pending)&&isTRUE(pending$state$owns_guards),"Choose an owned pending video verification that has not been adopted or cancelled.")
  opened<-pending$opened;c<-opened$context;success<-FALSE
  on.exit(if(!success)brohn_cancel_facial_review_open(pending),add=TRUE)
  brohn_check_facial_review_context(store,opened,c$report_id,c$report_revision,c$report_hash,c$project_id,.pending=TRUE)
  if(pending$process$is_alive()){success<-TRUE;return(NULL)}
  stdout<-pending$process$read_all_output();stderr<-pending$process$read_all_error()
  brohn_require(pending$process$get_exit_status()==0L&&nchar(stdout,type="bytes")<=4096,paste("Facial source verification needs attention:",substr(stderr,1,1200)))
  proof<-brohn_parse(stdout,4096);brohn_require(identical(proof$status,"verified")&&identical(proof$request_sha256,pending$request_hash),"Background verification belongs to another exact source.")
  b<-opened$record$body;r<-b$request
  brohn_require(identical(proof$manifest_sha256,b$index$manifest_sha256),"Background index verification changed its saved manifest.")
  # The native handles stayed open across the background full-byte check.
  # These bounded JSON documents now need only their semantic/source comparison.
  saved<-brohn_read_json_file(brohn_object_path(store,b$result_object$hash,verify=FALSE))
  brohn_require(identical(brohn_hash(saved),brohn_hash(b[setdiff(names(b),"result_object")])),"Index publication document changed.")
  if(!is.null(r$result_object)){
    source<-.brohn_freview_source(store,c$report_id,c$report_revision,c$report_hash,c$project_id,FALSE)
    retained<-brohn_read_json_file(brohn_object_path(store,r$result_object$hash,verify=FALSE));body<-source$report$body
    brohn_require(identical(retained$schema,"brohn-analysis-output/1.0")&&identical(brohn_hash(retained$report),brohn_hash(body[setdiff(names(body),"result_object")])),"Saved video differs from its retained original result.")
  }
  authority<-list2env(as.list(opened$authority),parent=emptyenv());authority$verified<-TRUE;lockEnvironment(authority,bindings=TRUE);opened$authority<-authority
  catalog<-brohn_facial_review_read(store,opened,"catalog");brohn_require(identical(brohn_hash(catalog$manifest),brohn_hash(b$manifest)),"Opened facial index changed its manifest.")
  state<-pending$state;state$owns_guards<-FALSE;success<-TRUE;opened
}
# Synchronous convenience for command-line/storage tests only. Shiny uses begin,
# non-blocking poll and cancel, retaining all native handles across verification.
brohn_open_facial_review <- function(store,index_id,index_hash,report_id,report_revision,report_hash,project_id) {
  pending<-brohn_begin_facial_review_open(store,index_id,index_hash,report_id,report_revision,report_hash,project_id)
  success<-FALSE;on.exit(if(!success)brohn_cancel_facial_review_open(pending),add=TRUE)
  pending$process$wait(20*60*1000);result<-brohn_poll_facial_review_open(store,pending)
  brohn_require(!is.null(result),"Facial source verification exceeded its wait limit.");success<-TRUE;result
}
brohn_check_facial_review_context <- function(store,opened,report_id,report_revision,report_hash,project_id,.pending=FALSE) {
  a<-opened$authority;c<-opened$context
  brohn_require(is.environment(a)&&environmentIsLocked(a)&&(isTRUE(a$verified)||isTRUE(.pending))&&identical(brohn_hash(a$context),brohn_hash(c))&&identical(brohn_hash(a$record),brohn_hash(opened$record))&&
    identical(c$workspace_id,store$workspace_id)&&identical(c$root,store$root)&&identical(c$project_id,project_id)&&identical(c$report_id,report_id)&&
    identical(as.numeric(c$report_revision),as.numeric(report_revision))&&identical(c$report_hash,report_hash),"Reopen this facial view in its exact original source context.")
  brohn_project(store,project_id)
  brohn_require(identical(.brohn_qexplorer_catalog(store,"report",c$report_id,c$report_revision,project_id),c$report_catalog)&&
    identical(.brohn_qexplorer_catalog(store,"dataset",c$dataset_id,c$dataset_revision,project_id),c$dataset_catalog)&&
    identical(.brohn_qexplorer_catalog(store,"facial_review",c$index_id,c$index_revision,project_id),c$index_catalog),"Saved video authority is no longer current in this project.")
  .brohn_freview_source(store,c$report_id,c$report_revision,c$report_hash,c$project_id,FALSE)
  for(g in a$guards){brohn_require(is.environment(g)&&!is.null(g$pointer),"Reopen the closed immutable facial view.");.Call(g$native$check,g$pointer)}
  invisible(TRUE)
}
brohn_facial_review_read <- function(store,opened,operation=c("catalog","page","detail","plot"),selection=list()) {
  operation<-match.arg(operation);a<-opened$authority;c<-opened$context
  brohn_check_facial_review_context(store,opened,c$report_id,c$report_revision,c$report_hash,c$project_id)
  allowed<-switch(operation,catalog=character(),page=c("metric","range","limit","offset"),detail="frame_index",plot=c("metric","range"))
  brohn_require(is.list(selection)&&all(names(selection)%in%allowed)&&!anyDuplicated(names(selection)),"Unsupported facial view selection.")
  b<-a$record$body;index<-c(list(sha256=b$index$hash,bytes=b$index$size),b$index[c("schema","manifest_sha256")])
  request<-c(list(schema="brohn-facial-review-request/1.0",operation=operation,index_path=a$path,index=index,binding_sha256=b$request$binding_sha256,guarded_verified=TRUE),selection)
  directory<-tempfile("brohn-video-read-",tmpdir=file.path(store$root,"work"));brohn_require(dir.create(directory,recursive=TRUE),"Cannot prepare owned video read work.")
  directory<-.brohn_store_contained(store,directory)
  parent<-normalizePath(file.path(store$root,"work"),winslash="/",mustWork=TRUE)
  brohn_require(identical(tolower(dirname(directory)),tolower(parent))&&startsWith(basename(directory),"brohn-video-read-"),"Owned video read directory escaped its workspace.")
  # Only this freshly-created private directory is removed; the immutable index
  # and original source paths are never cleanup targets.
  on.exit(unlink(directory,recursive=TRUE,force=TRUE),add=TRUE)
  result<-.brohn_freview_run(request,directory)
  brohn_check_facial_review_context(store,opened,c$report_id,c$report_revision,c$report_hash,c$project_id)
  result
}

# Unwired exact recorded-frame jobs. The saved observation index supplies identity.
.brohn_fframe_files<-.brohn_freview_files
.brohn_fframe_loaded<-setNames(lapply(.brohn_fframe_files,function(p)digest::digest(file=p,algo="sha256")),.brohn_fframe_files)
.brohn_fframe_recipe<-"saved-native-facial-frame/1.0"
.brohn_fframe_index<-function(store,r) {
  record<-brohn_get_entity(store,"facial_review",r$index_id)
  brohn_require(!is.null(record)&&identical(record$project_id,r$project_id)&&identical(brohn_hash(record$body),r$index_hash),"The recorded frame belongs to another saved facial view.")
  b<-record$body;q<-b$request
  brohn_require(identical(q$report_id,r$report_id)&&identical(as.numeric(q$report_revision),as.numeric(r$report_revision))&&identical(q$report_hash,r$report_hash),"The frame's exact original report changed.")
  source<-.brohn_freview_source(store,r$report_id,r$report_revision,r$report_hash,r$project_id,FALSE)
  brohn_require(identical(brohn_hash(source$binding),brohn_hash(b$binding))&&identical(brohn_hash(q),b$request_hash),"The frame's original source authority changed.")
  job<-brohn_get_job(store,b$processing$job_id)
  brohn_require(identical(job$status,"succeeded")&&identical(job$operation,"facial_review")&&identical(job$result$facial_review_id,r$index_id)&&
    identical(job$result$index_hash,r$index_hash)&&identical(job$result$artifact_hash,b$index$hash)&&identical(job$result$output_hash,b$result_object$hash),"This facial index has no matching completed publication.")
  list(record=record,source=source)
}
brohn_queue_facial_frame<-function(store,opened,frame_index,rebuild=FALSE) {
  c<-opened$context;brohn_check_facial_review_context(store,opened,c$report_id,c$report_revision,c$report_hash,c$project_id)
  brohn_require(brohn_number(frame_index,0,35999,TRUE)&&is.logical(rebuild)&&length(rebuild)==1L&&!is.na(rebuild),"Choose an exact saved frame.")
  detail<-brohn_facial_review_read(store,opened,"detail",list(frame_index=frame_index))
  r<-list(schema="brohn-facial-frame-job/1.0",recipe=.brohn_fframe_recipe,index_id=c$index_id,index_hash=c$index_hash,
    report_id=c$report_id,report_revision=c$report_revision,report_hash=c$report_hash,project_id=c$project_id,frame=detail$observation,implementation=.brohn_fframe_loaded)
  .brohn_fframe_index(store,r)
  brohn_store_batch(store,function(){.brohn_fframe_index(store,r);key<-paste0("facial-frame:",brohn_hash(r))
    if(!rebuild){old<-DBI::dbGetQuery(store$con,"SELECT * FROM jobs WHERE operation='facial_frame' AND request_hash=? ORDER BY created_at DESC,rowid DESC LIMIT 1",params=list(.brohn_store_hash(charToRaw(.brohn_store_json(r)))))
      if(nrow(old))return(.brohn_store_job(old))}
    brohn_enqueue_job(store,"facial_frame",r,if(rebuild)paste0(key,":",brohn_id("rebuild"))else key)})
}
.brohn_fframe_guards<-function(store,request) {
  x<-.brohn_fframe_index(store,request);b<-x$record$body
  guards<-.brohn_freview_guards(store,b$request);success<-FALSE;on.exit(if(!success)for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  refs<-list(b$result_object,b$index,b$binding$original_source)
  for(ref in refs)guards[[length(guards)+1L]]<-.brohn_qexplorer_hold(brohn_object_path(store,ref$hash,verify=FALSE),ref$size)
  success<-TRUE;guards
}
brohn_facial_frame_input<-function(store,job) {
  r<-job$request
  brohn_fields(r,c("schema","recipe","index_id","index_hash","report_id","report_revision","report_hash","project_id","frame","implementation"),label="Recorded frame request")
  brohn_require(identical(job$operation,"facial_frame")&&identical(r$schema,"brohn-facial-frame-job/1.0")&&identical(r$recipe,.brohn_fframe_recipe)&&
    identical(brohn_hash(r$implementation),brohn_hash(.brohn_fframe_loaded))&&all(vapply(names(r$implementation),function(p)identical(digest::digest(file=p,algo="sha256"),r$implementation[[p]]),logical(1))),"Prepare a recorded frame with the current exact extraction implementation.")
  x<-.brohn_fframe_index(store,r);b<-x$record$body
  opened<-brohn_open_facial_review(store,r$index_id,r$index_hash,r$report_id,r$report_revision,r$report_hash,r$project_id);on.exit(brohn_close_facial_review(opened),add=TRUE)
  detail<-brohn_facial_review_read(store,opened,"detail",list(frame_index=as.numeric(r$frame$frame_index)))
  brohn_require(identical(brohn_hash(detail$observation),brohn_hash(r$frame)),"The selected original frame/PTS changed.")
  source<-b$binding$original_source
  list(schema="brohn-analysis-input/1.0",operation="facial_frame",project_id=r$project_id,
    source_objects=c(b$request$source_objects,list(list(hash=b$index$hash,bytes=b$index$size),list(hash=b$result_object$hash,bytes=b$result_object$size))),facial_frame_input=list(schema="brohn-facial-frame-request/1.0",operation="frame",source_path=brohn_object_path(store,source$hash),source=list(sha256=source$hash,bytes=source$size),
      index_path=opened$authority$path,index=list(sha256=b$index$hash,bytes=b$index$size,manifest_sha256=b$index$manifest_sha256),binding_sha256=b$request$binding_sha256,
      frame_index=as.numeric(r$frame$frame_index)))
}
brohn_analyse_facial_frame<-function(input,scratch) {
  brohn_require(identical(input$operation,"facial_frame"),"Unsupported frame operation.")
  directory<-file.path(scratch,"artifacts");brohn_require(!dir.exists(directory)&&dir.create(directory),"Choose a fresh owned frame output directory.")
  request<-input$facial_frame_input;request$output_directory<-normalizePath(directory,winslash="/",mustWork=TRUE)
  in_path<-file.path(scratch,"frame-request.json");out_path<-file.path(scratch,"frame-result.json");brohn_write_json_file(request,in_path)
  p<-processx::run(.brohn_publication_python(),c("-B","scripts/workers/facial_review.py","--request",in_path,"--output",out_path),timeout=1200,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(file.exists(out_path),paste("Recorded frame returned no response.",substr(p$stderr,1,1000)))
  result<-brohn_read_json_file(out_path,2*1024^2)
  brohn_require(p$status==0L&&identical(result$status,"complete")&&identical(result$schema,"brohn-facial-recorded-frame/1.0"),paste("Recorded frame needs attention:",brohn_default(result$error$message,substr(p$stderr,1,1000))))
  list(facial_frame=result)
}
brohn_publish_facial_frame<-function(store,output,scratch,job,input,output_path) {
  brohn_require(.Platform$OS.type=="windows"&&!RSQLite::sqliteIsTransacting(store$con),"Recorded-frame publication needs the native guard outside a writer transaction.")
  .brohn_publication_output_identity(output,.brohn_fframe_loaded);.brohn_publication_job(store,job)
  output_path<-.brohn_store_contained(store,output_path)
  brohn_require(file.exists(output_path)&&identical(tolower(dirname(output_path)),tolower(normalizePath(scratch,winslash="/",mustWork=TRUE))),"Frame output leaves its owned attempt.")
  guards<-.brohn_fframe_guards(store,job$request);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  brohn_require(identical(brohn_hash(input),brohn_hash(brohn_facial_frame_input(store,job)))&&identical(brohn_hash(output),brohn_hash(brohn_read_json_file(output_path))),"Frame publication changed its frozen input or output.")
  x<-.brohn_fframe_index(store,job$request);b<-x$record$body;value<-output$report$facial_frame;ref<-value$image
  brohn_require(identical(value$schema,"brohn-facial-recorded-frame/1.0")&&identical(value$status,"complete")&&identical(value$binding_sha256,b$request$binding_sha256)&&
    identical(value$index_sha256,b$index$hash)&&identical(brohn_hash(value$source),brohn_hash(input$facial_frame_input$source))&&
    identical(brohn_hash(value$artifacts),brohn_hash(b$manifest$artifacts))&&identical(brohn_hash(value$frame),brohn_hash(job$request$frame))&&
    identical(value$extraction$policy,"sequential_original_rgb24_no_seek_no_autorotation")&&identical(value$extraction$orientation,b$manifest$parameters$orientation)&&
    identical(value$extraction$ffmpeg,b$manifest$engine$ffmpeg)&&identical(value$extraction$ffprobe,b$manifest$engine$ffprobe)&&
    identical(value$extraction$rgb24_sha256,job$request$frame$decoded_rgb_sha256)&&
    identical(value$extraction$runtime_manifest_sha256,b$manifest$engine$runtime_manifest_sha256)&&
    brohn_number(ref$bytes,1,32*1024^2,TRUE)&&identical(ref$media_type,"image/png"),"Recorded-frame identity or extraction policy changed.")
  path<-brohn_checked_artifact_path(store,ref$path,scratch)
  con<-file(path,"rb");header<-tryCatch(readBin(con,"raw",33L),finally=close(con))
  brohn_require(length(header)==33L&&identical(header[1:8],as.raw(c(137,80,78,71,13,10,26,10)))&&identical(header[13:16],charToRaw("IHDR")),"Recorded frame has no complete PNG header.")
  integer32<-function(x)sum(as.numeric(x)*c(16777216,65536,256,1))
  dimensions<-list(width=integer32(header[17:20]),height=integer32(header[21:24]))
  brohn_require(integer32(header[9:12])==13&&dimensions$width>0&&dimensions$height>0&&dimensions$width*dimensions$height<=3840*2160,"Recorded PNG leaves the original video pixel bound.")
  brohn_require(identical(as.numeric(dimensions$width),as.numeric(b$manifest$parameters$width))&&identical(as.numeric(dimensions$height),as.numeric(b$manifest$parameters$height))&&
    identical(as.numeric(ref$width),as.numeric(dimensions$width))&&identical(as.numeric(ref$height),as.numeric(dimensions$height)),"The recorded image changed original dimensions.")
  context<-.brohn_publication_stage(store,job,list(list(key="recorded-frame",kind="recorded-frame",path=path,sha256=ref$sha256,bytes=ref$bytes,media_type="image/png")))
  document<-NULL;committed<-FALSE;on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);brohn_close_publication(context$guard,committed)},add=TRUE)
  value$image<-c(ref[setdiff(names(ref),c("path","sha256","bytes"))],context$descriptors[[1L]][c("hash","size")])
  id<-paste0("facial-frame-",sub("^job_","",job$id))
  body<-list(schema="brohn-saved-facial-frame/1.0",id=id,recipe=.brohn_fframe_recipe,request=job$request,request_hash=brohn_hash(job$request),frame=value,created_at=brohn_now(),
    processing=list(job_id=job$id,attempt=job$attempt,worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity,publication=.brohn_publication_processing(context)))
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-facial-frame.json"))
  result<-brohn_store_batch(store,function(){.brohn_fframe_index(store,job$request);for(g in guards).Call(g$native$check,g$pointer)
    .brohn_publication_register(store,context);body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"facial_frame",id,body,0L,project_id=job$request$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(facial_frame_id=id,frame_hash=brohn_hash(body),image_hash=value$image$hash,output_hash=body$result_object$hash))})
  committed<-TRUE;result
}
brohn_close_facial_frame<-function(view) {
  if(is.environment(view$authority)&&environmentIsLocked(view$authority))for(g in view$authority$guards).brohn_qexplorer_release(g)
  invisible(NULL)
}
.brohn_fframe_open_context<-function(store,record,opened,frame_index) {
  c<-opened$context;brohn_check_facial_review_context(store,opened,c$report_id,c$report_revision,c$report_hash,c$project_id)
  b<-record$body;r<-b$request
  brohn_require(identical(record$project_id,c$project_id)&&identical(r$index_id,c$index_id)&&identical(r$index_hash,c$index_hash)&&
    identical(as.numeric(b$frame$frame$frame_index),as.numeric(frame_index)),"Open the recorded image for this exact selected frame and facial view.")
  .brohn_fframe_index(store,r)
  brohn_require(identical(brohn_hash(brohn_get_entity(store,"facial_frame",record$id)$body),brohn_hash(b)),"The saved recorded frame changed.")
  job<-brohn_get_job(store,b$processing$job_id)
  brohn_require(identical(job$status,"succeeded")&&identical(job$operation,"facial_frame")&&identical(job$result$facial_frame_id,record$id)&&
    identical(job$result$frame_hash,brohn_hash(b))&&identical(job$result$image_hash,b$frame$image$hash)&&identical(job$result$output_hash,b$result_object$hash)&&
    identical(brohn_hash(job$request),b$request_hash),"Recorded image has no matching completed publication receipt.")
  invisible(TRUE)
}
brohn_begin_facial_frame_open<-function(store,opened,frame_id,frame_hash,frame_index) {
  record<-brohn_get_entity(store,"facial_frame",frame_id)
  brohn_require(!is.null(record)&&identical(brohn_hash(record$body),frame_hash),"Choose the exact saved recorded frame.")
  .brohn_fframe_open_context(store,record,opened,frame_index)
  refs<-list(record$body$frame$image,record$body$result_object);guards<-list();success<-FALSE
  on.exit(if(!success)for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  files<-lapply(refs,function(ref){path<-brohn_object_path(store,ref$hash,verify=FALSE);guards[[length(guards)+1L]]<<-.brohn_qexplorer_hold(path,ref$size);list(path=path,sha256=ref$hash,bytes=ref$size)})
  code<-paste(c("import hashlib,json,os,sys","raw=sys.argv[1]","for x in json.loads(raw):",
    " assert os.path.getsize(x['path'])==x['bytes'],'Recorded image size changed'",
    " with open(x['path'],'rb') as f: assert hashlib.file_digest(f,'sha256').hexdigest()==x['sha256'],'Recorded image bytes changed'",
    "print(hashlib.sha256(raw.encode()).hexdigest())"),collapse="\n")
  process<-processx::process$new(.brohn_publication_python(),c("-B","-c",code,brohn_json(files)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
  pending<-new.env(parent=emptyenv());pending$record<-record;pending$opened<-opened;pending$frame_index<-frame_index;pending$guards<-guards;pending$files<-files
  pending$process<-process;pending$request_hash<-brohn_hash(files);pending$state<-new.env(parent=emptyenv());pending$state$owns_guards<-TRUE
  lockEnvironment(pending,bindings=TRUE);success<-TRUE;pending
}
brohn_cancel_facial_frame_open<-function(pending) {
  if(is.environment(pending)&&environmentIsLocked(pending)&&isTRUE(pending$state$owns_guards)) {
    if(pending$process$is_alive())pending$process$kill_tree()
    for(g in pending$guards).brohn_qexplorer_release(g)
    state<-pending$state;state$owns_guards<-FALSE
  };invisible(NULL)
}
brohn_poll_facial_frame_open<-function(store,pending) {
  brohn_require(is.environment(pending)&&environmentIsLocked(pending)&&isTRUE(pending$state$owns_guards),"Choose a pending recorded image that has not been adopted or cancelled.")
  success<-FALSE;on.exit(if(!success)brohn_cancel_facial_frame_open(pending),add=TRUE)
  .brohn_fframe_open_context(store,pending$record,pending$opened,pending$frame_index)
  for(g in pending$guards).Call(g$native$check,g$pointer)
  if(pending$process$is_alive()){success<-TRUE;return(NULL)}
  stdout<-pending$process$read_all_output();stderr<-pending$process$read_all_error()
  brohn_require(pending$process$get_exit_status()==0L&&identical(trimws(stdout),pending$request_hash),paste("Recorded image needs attention:",substr(stderr,1,1000)))
  b<-pending$record$body;retained<-brohn_read_json_file(pending$files[[2L]]$path)
  brohn_require(identical(brohn_hash(retained),brohn_hash(b[setdiff(names(b),"result_object")])),"Recorded-frame publication document changed.")
  a<-new.env(parent=emptyenv());a$record<-pending$record;a$index_authority<-pending$opened$authority;a$guards<-pending$guards;a$path<-pending$files[[1L]]$path
  lockEnvironment(a,bindings=TRUE);view<-list(record=pending$record,authority=a)
  state<-pending$state;state$owns_guards<-FALSE;success<-TRUE;view
}
brohn_check_facial_frame_context<-function(store,view,opened,frame_index) {
  a<-view$authority
  brohn_require(is.environment(a)&&environmentIsLocked(a)&&identical(a$index_authority,opened$authority)&&identical(brohn_hash(a$record),brohn_hash(view$record)),"Reopen this exact recorded frame.")
  .brohn_fframe_open_context(store,view$record,opened,frame_index)
  for(g in a$guards){brohn_require(!is.null(g$pointer),"Reopen the closed recorded image.");.Call(g$native$check,g$pointer)}
  invisible(TRUE)
}

brohn_begin_facial_csv<-function(store,opened,selection) {
  c<-opened$context;brohn_check_facial_review_context(store,opened,c$report_id,c$report_revision,c$report_hash,c$project_id)
  brohn_require(is.list(selection)&&identical(sort(names(selection)),c("metric","range"))&&!is.null(selection$metric),"Choose an exact saved measurement to export.")
  directory<-tempfile("brohn-facial-export-",tmpdir=file.path(store$root,"work"));brohn_require(dir.create(directory,recursive=TRUE),"Cannot prepare the exact video export.")
  directory<-.brohn_store_contained(store,directory);parent<-normalizePath(file.path(store$root,"work"),winslash="/",mustWork=TRUE)
  brohn_require(identical(tolower(dirname(directory)),tolower(parent))&&startsWith(basename(directory),"brohn-facial-export-"),"Video export work leaves its workspace.")
  success<-FALSE;held<-list();on.exit(if(!success){for(g in held).brohn_qexplorer_release(g);unlink(directory,recursive=TRUE,force=TRUE)},add=TRUE)
  b<-opened$record$body;request<-c(list(schema="brohn-facial-review-request/1.0",operation="export_csv",index_path=opened$authority$path,
    index=list(sha256=b$index$hash,bytes=b$index$size,manifest_sha256=b$index$manifest_sha256),binding_sha256=b$request$binding_sha256,guarded_verified=TRUE,output_path=file.path(directory,"values.csv")),selection)
  held[[1L]]<-.brohn_qexplorer_hold(opened$authority$path,b$index$size)
  request_path<-file.path(directory,"request.json");output_path<-file.path(directory,"result.json");brohn_write_json_file(request,request_path)
  process<-processx::process$new(.brohn_publication_python(),c("-B","scripts/workers/facial_review.py","--request",request_path,"--output",output_path),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
  pending<-new.env(parent=emptyenv());pending$opened<-opened;pending$selection<-selection;pending$directory<-directory;pending$request<-request;pending$output_path<-output_path
  pending$state<-new.env(parent=emptyenv());pending$state$process<-process;pending$state$guards<-held;pending$state$phase<-"build";pending$state$closed<-FALSE;pending$state$result<-NULL
  lockEnvironment(pending,bindings=TRUE);success<-TRUE;pending
}
brohn_close_facial_csv<-function(pending) {
  if(!is.environment(pending)||!environmentIsLocked(pending)||isTRUE(pending$state$closed))return(invisible(NULL))
  s<-pending$state;if(!is.null(s$process)&&s$process$is_alive()){s$process$kill_tree();s$process$wait(2000)}
  for(g in s$guards).brohn_qexplorer_release(g)
  # Only begin's verified fresh direct child of workspace/work is a cleanup target.
  unlink(pending$directory,recursive=TRUE,force=TRUE);s$closed<-TRUE;invisible(NULL)
}
brohn_poll_facial_csv<-function(store,pending) {
  brohn_require(is.environment(pending)&&environmentIsLocked(pending)&&!isTRUE(pending$state$closed),"Prepare the complete selected video CSV first.")
  success<-FALSE;on.exit(if(!success)brohn_close_facial_csv(pending),add=TRUE);s<-pending$state;c<-pending$opened$context
  brohn_check_facial_review_context(store,pending$opened,c$report_id,c$report_revision,c$report_hash,c$project_id)
  for(g in s$guards).Call(g$native$check,g$pointer)
  if(identical(s$phase,"ready")){success<-TRUE;return(s$result)}
  if(s$process$is_alive()){success<-TRUE;return(NULL)}
  stderr<-s$process$read_all_error();stdout<-s$process$read_all_output()
  brohn_require(s$process$get_exit_status()==0L,paste("Complete video CSV needs attention:",substr(stderr,1,1000)))
  if(identical(s$phase,"build")) {
    result<-brohn_read_json_file(pending$output_path,2*1024^2)
    brohn_require(identical(result$schema,"brohn-facial-numeric-export/1.0")&&identical(result$binding_sha256,pending$request$binding_sha256)&&
      identical(result$metric,pending$selection$metric)&&identical(brohn_hash(result$range),brohn_hash(pending$selection$range))&&
      brohn_number(result$rows,0,4800,TRUE)&&brohn_number(result$bytes,1,64*1024^2,TRUE)&&.brohn_freview_hash(result$sha256)&&
      identical(normalizePath(result$path,winslash="/",mustWork=TRUE),normalizePath(pending$request$output_path,winslash="/",mustWork=TRUE)),"The prepared CSV changed its exact source or selection.")
    s$guards[[length(s$guards)+1L]]<-.brohn_qexplorer_hold(result$path,result$bytes);s$result<-result
    code<-"import hashlib,sys;f=open(sys.argv[1],'rb');print(hashlib.file_digest(f,'sha256').hexdigest());f.close()"
    s$process<-processx::process$new(.brohn_publication_python(),c("-B","-c",code,result$path),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE);s$phase<-"verify"
    success<-TRUE;return(NULL)
  }
  brohn_require(identical(trimws(stdout),s$result$sha256),"The prepared complete CSV failed verification under its native read seal.")
  s$phase<-"ready";s$process<-NULL;success<-TRUE;s$result
}
brohn_facial_csv_manifest<-function(pending) {
  brohn_require(is.environment(pending)&&!isTRUE(pending$state$closed)&&identical(pending$state$phase,"ready"),"Verify the complete CSV first.")
  b<-pending$opened$record$body;r<-pending$state$result;metric<-r$metric
  list(schema="brohn-facial-numeric-export-manifest/1.0",csv=list(sha256=r$sha256,bytes=r$bytes,rows=r$rows,media_type="text/csv; charset=utf-8"),
    source=b$binding,index=list(id=b$id,sha256=b$index$hash),metric=metric,range=r$range,number_encoding=r$number_encoding,missing_value=r$missing_value,
    parameters=b$manifest$parameters,engine=b$manifest$engine,columns=list(frame_index="original zero-based decoded frame",source_pts="original integer source PTS",source_time_base="original rational seconds per PTS tick",source_pts_s="original printed source timestamp",
      relative_time_numerator="exact recording-relative rational numerator",relative_time_denominator="exact recording-relative rational denominator",time_s="original numeric relative-time token",
      state="original detection state",eligible="original single-face summary eligibility",face_count="original number of frame-local faces",face_ordinal="local row number in this frame only, not identity",face_valid="original native completeness",metric="exact native identifier",native_value="original numeric token, native score0to1; empty means unavailable"))
}
