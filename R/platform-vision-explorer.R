# Unwired saved-video explorer domain. No inference or model updates.
.brohn_vexplorer_recipe <- "saved-video-geometry-explorer/1.0"
.brohn_vexplorer_schema <- "brohn-saved-vision-index/1.0"
.brohn_vexplorer_files <- c("R/platform-vision-explorer.R","scripts/workers/vision_explorer.py")
.brohn_vexplorer_loaded <- stats::setNames(lapply(.brohn_vexplorer_files,function(path)digest::digest(file=path,algo="sha256")),.brohn_vexplorer_files)
.brohn_vexplorer_hash <- function(x) brohn_text(x,64)&&grepl("^[a-f0-9]{64}$",x)
.brohn_vexplorer_source <- function(store,report_id,report_revision,report_hash,project_id,verify=TRUE) {
  brohn_require(brohn_valid_id(report_id)&&brohn_number(report_revision,1,1e9,TRUE)&&.brohn_vexplorer_hash(report_hash)&&brohn_text(project_id,96),"Choose the exact saved video report and project.")
  catalog_hash<-.brohn_qexplorer_catalog(store,"report",report_id,report_revision,project_id);brohn_project(store,project_id)
  report<-brohn_get_entity(store,"report",report_id,report_revision);b<-report$body;a<-b$analysis;p<-b$provenance
  brohn_require(identical(b$id,report_id)&&identical(brohn_hash(b),report_hash)&&identical(a$kind,"video")&&identical(a$schema,"brohn-vision-result/1.0"),"This exact report has no supported saved video geometry.")
  brohn_require(identical(b$dataset_id,p$dataset_id)&&brohn_number(p$dataset_revision,1,1e9,TRUE)&&.brohn_vexplorer_hash(p$dataset_hash),"The video report has no exact frozen dataset provenance.")
  dataset_catalog<-.brohn_qexplorer_catalog(store,"dataset",p$dataset_id,p$dataset_revision,project_id)
  dataset<-brohn_get_entity(store,"dataset",p$dataset_id,p$dataset_revision)
  brohn_require(identical(brohn_hash(dataset$body),p$dataset_hash)&&identical(dataset$body$modality,"video")&&
    identical(brohn_hash(dataset$body$source),brohn_hash(p$source))&&identical(brohn_hash(dataset$body$metadata),brohn_hash(p$mapping))&&
    identical(a$source$sha256,p$source$hash),"The video report's source, dataset or mapping changed.")
  brohn_require(brohn_number(a$source$bytes,1,512*1024^2,TRUE)&&identical(as.numeric(a$source$bytes),as.numeric(p$source$size)),"The saved video byte count is inconsistent.")
  artifacts<-Filter(function(x)identical(x$kind,"vision-observations"),a$artifacts)
  brohn_require(length(artifacts)==1L&&.brohn_vexplorer_hash(artifacts[[1L]]$hash)&&brohn_number(artifacts[[1L]]$size,1,2*1024^3,TRUE),"Choose a report with one complete original observation artifact.")
  artifact<-list(sha256=artifacts[[1L]]$hash,bytes=artifacts[[1L]]$size)
  artifact_path<-brohn_object_path(store,artifact$sha256,verify=verify)
  if(!is.null(b$result_object)&&verify){retained<-brohn_read_json_file(brohn_object_path(store,b$result_object$hash));brohn_require(identical(retained$schema,"brohn-analysis-output/1.0")&&
    identical(brohn_hash(retained$report),brohn_hash(b[setdiff(names(b),"result_object")])),"Saved video report differs from its retained worker result.")}
  brohn_require(is.list(a$parameters)&&is.list(a$engine)&&is.list(a$quality)&&isTRUE(a$quality$pts_validated)&&identical(a$quality$identity_tracking,FALSE),"Saved video clock/model declarations are unavailable.")
  binding<-list(workspace_id=store$workspace_id,project_id=project_id,report_id=report_id,report_revision=report_revision,report_hash=report_hash,
    report_catalog_hash=catalog_hash,dataset_id=p$dataset_id,dataset_revision=p$dataset_revision,dataset_hash=p$dataset_hash,dataset_catalog_hash=dataset_catalog,
    original_source=list(hash=p$source$hash,size=p$source$size),artifact=artifact,parameters_hash=brohn_hash(a$parameters),engine_hash=brohn_hash(a$engine),origin=b$origin)
  list(report=report,binding=binding,artifact=artifact,artifact_path=artifact_path,result_object=b$result_object,catalog_hash=catalog_hash,dataset_catalog_hash=dataset_catalog)
}
brohn_prepare_vision_index <- function(store,report_id,report_revision,report_hash,project_id) {
  source<-.brohn_vexplorer_source(store,report_id,report_revision,report_hash,project_id,FALSE)
  list(schema="brohn-vision-index-request/1.0",recipe=.brohn_vexplorer_recipe,project_id=project_id,report_id=report_id,report_revision=report_revision,report_hash=report_hash,
    binding=source$binding,binding_json=brohn_json(source$binding),binding_sha256=brohn_hash(source$binding),artifact=source$artifact,result_object=source$result_object,implementation=.brohn_vexplorer_loaded)
}
brohn_queue_vision_index <- function(store,report_id,report_revision,report_hash,project_id,rebuild=FALSE) {
  brohn_require(is.logical(rebuild)&&length(rebuild)==1L&&!is.na(rebuild),"Choose whether to reuse or rebuild this saved video view.")
  r<-brohn_prepare_vision_index(store,report_id,report_revision,report_hash,project_id)
  brohn_store_batch(store,function(){
    brohn_require(identical(.brohn_qexplorer_catalog(store,"report",report_id,report_revision,project_id),r$binding$report_catalog_hash)&&
      identical(.brohn_qexplorer_catalog(store,"dataset",r$binding$dataset_id,r$binding$dataset_revision,project_id),r$binding$dataset_catalog_hash),"Saved video authority changed before queueing.")
    brohn_project(store,project_id)
    key<-paste0("vision-index:",brohn_hash(r))
    if(!rebuild){old<-DBI::dbGetQuery(store$con,"SELECT * FROM jobs WHERE operation='vision_index' AND request_hash=? ORDER BY created_at DESC,rowid DESC LIMIT 1",params=list(.brohn_store_hash(charToRaw(.brohn_store_json(r)))))
      if(nrow(old))return(.brohn_store_job(old))}
    brohn_enqueue_job(store,"vision_index",r,if(rebuild)paste0(key,":",brohn_id("rebuild"))else key)
  })
}
brohn_vision_index_input <- function(store,job) {
  r<-job$request
  brohn_require(identical(job$operation,"vision_index"),"Choose a saved video index job.")
  expected<-brohn_prepare_vision_index(store,r$report_id,r$report_revision,r$report_hash,r$project_id)
  brohn_require(identical(brohn_hash(expected),brohn_hash(r))&&all(vapply(names(r$implementation),function(path)identical(digest::digest(file=path,algo="sha256"),r$implementation[[path]]),logical(1))),"Saved video source or explorer code changed; prepare a new view.")
  s<-.brohn_vexplorer_source(store,r$report_id,r$report_revision,r$report_hash,r$project_id,TRUE);a<-s$report$body$analysis
  list(schema="brohn-analysis-input/1.0",operation="vision_index",project_id=r$project_id,
    vision_input=list(schema="brohn-vision-explorer-request/1.0",operation="build",artifact_path=s$artifact_path,artifact=s$artifact,
      binding_json=r$binding_json,binding_sha256=r$binding_sha256,parameters=a$parameters,quality=a$quality,engine=a$engine))
}
.brohn_vexplorer_run <- function(request,directory,timeout=120) {
  brohn_require(dir.exists(directory),"Choose an existing owned explorer work directory.")
  in_path<-file.path(directory,"vision-explorer-request.json");out_path<-file.path(directory,"vision-explorer-result.json")
  brohn_write_json_file(request,in_path)
  process<-processx::run(.brohn_publication_python(),c("-B","scripts/workers/vision_explorer.py","--request",in_path,"--output",out_path),
    timeout=timeout,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(file.exists(out_path),paste("Video explorer produced no response.",substr(process$stderr,1,1200)))
  result<-brohn_read_json_file(out_path,2*1024^2)
  brohn_require(process$status==0L&&!identical(result$status,"error"),paste("Video explorer needs attention:",brohn_default(result$error$message,substr(process$stderr,1,1000))))
  result
}
brohn_analyse_vision_index <- function(input,scratch) {
  brohn_require(identical(input$schema,"brohn-analysis-input/1.0")&&identical(input$operation,"vision_index"),"Unsupported saved video build input.")
  directory<-file.path(scratch,"artifacts");brohn_require(!dir.exists(directory)&&dir.create(directory),"Choose a fresh owned video index directory.")
  request<-input$vision_input;request$index_path<-normalizePath(file.path(directory,"vision-index.sqlite"),winslash="/",mustWork=FALSE)
  list(vision_index=.brohn_vexplorer_run(request,scratch,timeout=20*60))
}
.brohn_vexplorer_guards <- function(store,request) {
  guards<-list();success<-FALSE;on.exit(if(!success)for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  refs<-list(list(hash=request$artifact$sha256,size=request$artifact$bytes),request$result_object)
  for(ref in refs)if(!is.null(ref))guards[[length(guards)+1L]]<-.brohn_qexplorer_hold(brohn_object_path(store,ref$hash,verify=FALSE),ref$size)
  success<-TRUE;guards
}
brohn_publish_vision_index <- function(store,output,scratch,job,input,output_path) {
  brohn_require(.Platform$OS.type=="windows"&&!RSQLite::sqliteIsTransacting(store$con),"Video index publication needs the qualified native Windows guard outside a writer transaction.")
  .brohn_publication_output_identity(output,.brohn_vexplorer_loaded);.brohn_publication_job(store,job)
  output_path<-.brohn_store_contained(store,output_path)
  brohn_require(file.exists(output_path)&&!dir.exists(output_path)&&identical(tolower(dirname(output_path)),tolower(normalizePath(scratch,winslash="/",mustWork=TRUE))),"Video worker output leaves its owned attempt directory.")
  guards<-.brohn_vexplorer_guards(store,job$request);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  brohn_require(identical(brohn_hash(input),brohn_hash(brohn_vision_index_input(store,job)))&&identical(brohn_hash(output),brohn_hash(brohn_read_json_file(output_path))),"Video publication substituted its frozen input or output.")
  result<-output$report$vision_index;ref<-result$index;m<-result$manifest
  brohn_require(identical(result$schema,"brohn-vision-index-result/1.0")&&identical(result$status,"complete")&&identical(m$schema,"brohn-vision-explorer-index/1.0")&&
    identical(m$binding_sha256,job$request$binding_sha256)&&identical(m$binding_json,job$request$binding_json)&&
    identical(brohn_hash(m$parameters),brohn_hash(input$vision_input$parameters))&&identical(brohn_hash(m$engine),brohn_hash(input$vision_input$engine))&&
    brohn_number(ref$bytes,1,256*1024^2,TRUE),"Video index changed its source/model/resource declaration.")
  path<-brohn_checked_artifact_path(store,ref$path,scratch)
  context<-.brohn_publication_stage(store,job,list(list(key="vision-index",kind="vision-index",path=path,sha256=ref$sha256,bytes=ref$bytes,media_type="application/vnd.sqlite3")))
  document<-NULL;committed<-FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);brohn_close_publication(context$guard,committed)},add=TRUE)
  verify_request<-list(schema="brohn-vision-explorer-request/1.0",operation="catalog",index_path=context$paths[["vision-index"]],index=ref,binding_sha256=job$request$binding_sha256)
  verify_dir<-file.path(scratch,"verify-index");brohn_require(dir.create(verify_dir),"Could not create owned index verification work directory.")
  verified<-.brohn_vexplorer_run(verify_request,verify_dir)
  brohn_require(identical(brohn_hash(verified$manifest),brohn_hash(m)),"The staged index differs from its worker manifest.")
  index<-c(ref[setdiff(names(ref),c("path","sha256","bytes"))],context$descriptors[[1L]][c("hash","size")])
  id<-paste0("vision-index-",sub("^job_","",job$id))
  body<-list(schema=.brohn_vexplorer_schema,id=id,recipe=.brohn_vexplorer_recipe,request=job$request,request_hash=brohn_hash(job$request),
    binding=job$request$binding,index=index,manifest=m,created_at=brohn_now(),processing=list(job_id=job$id,attempt=job$attempt,
      worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity,publication=.brohn_publication_processing(context)))
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-vision-index.json"))
  receipt<-brohn_store_batch(store,function(){
    r<-job$request;brohn_project(store,r$project_id)
    brohn_require(identical(.brohn_qexplorer_catalog(store,"report",r$report_id,r$report_revision,r$project_id),r$binding$report_catalog_hash)&&
      identical(.brohn_qexplorer_catalog(store,"dataset",r$binding$dataset_id,r$binding$dataset_revision,r$project_id),r$binding$dataset_catalog_hash),"Original video authority changed before publication.")
    for(g in guards).Call(g$native$check,g$pointer)
    .brohn_publication_register(store,context);body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"vision_index",id,body,0L,project_id=r$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(vision_index_id=id,report_id=r$report_id,index_hash=brohn_hash(body),artifact_hash=index$hash,output_hash=body$result_object$hash))
  });committed<-TRUE;receipt
}
brohn_close_vision_index <- function(opened) {
  a<-opened$authority
  if(is.environment(a)&&environmentIsLocked(a))for(g in a$guards).brohn_qexplorer_release(g)
  invisible(NULL)
}
brohn_begin_vision_index_open <- function(store,index_id,index_hash,report_id,report_revision,report_hash,project_id) {
  brohn_require(brohn_valid_id(index_id)&&.brohn_vexplorer_hash(index_hash),"Choose the exact saved video index.")
  record<-brohn_get_entity(store,"vision_index",index_id)
  brohn_require(!is.null(record)&&identical(record$project_id,project_id)&&identical(brohn_hash(record$body),index_hash),"This video index is unavailable in the selected project.")
  b<-record$body;r<-b$request
  brohn_require(identical(b$schema,.brohn_vexplorer_schema)&&identical(r$report_id,report_id)&&identical(as.numeric(r$report_revision),as.numeric(report_revision))&&identical(r$report_hash,report_hash),"The index belongs to another exact video report.")
  source<-.brohn_vexplorer_source(store,report_id,report_revision,report_hash,project_id,FALSE)
  brohn_require(identical(brohn_hash(source$binding),brohn_hash(b$binding))&&identical(brohn_hash(r),b$request_hash),"Video index source authority changed.")
  job<-brohn_get_job(store,b$processing$job_id)
  brohn_require(identical(job$operation,"vision_index")&&identical(job$status,"succeeded")&&identical(job$result$vision_index_id,index_id)&&identical(job$result$index_hash,index_hash)&&
    identical(job$result$artifact_hash,b$index$hash)&&identical(job$result$output_hash,b$result_object$hash)&&identical(brohn_hash(job$request),b$request_hash),"Video index has no matching completed publication receipt.")
  guards<-.brohn_vexplorer_guards(store,r);success<-FALSE;on.exit(if(!success)for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  guards[[length(guards)+1L]]<-.brohn_qexplorer_hold(brohn_object_path(store,b$result_object$hash,verify=FALSE),b$result_object$size)
  path<-brohn_object_path(store,b$index$hash,verify=FALSE);guards[[length(guards)+1L]]<-.brohn_qexplorer_hold(path,b$index$size)
  context<-list(workspace_id=store$workspace_id,root=store$root,project_id=project_id,report_id=report_id,report_revision=report_revision,report_hash=report_hash,
    report_catalog=source$catalog_hash,dataset_id=b$binding$dataset_id,dataset_revision=b$binding$dataset_revision,dataset_catalog=source$dataset_catalog_hash,
    index_id=index_id,index_revision=record$revision,index_hash=index_hash,index_catalog=.brohn_qexplorer_catalog(store,"vision_index",index_id,record$revision,project_id))
  authority<-new.env(parent=emptyenv());authority$context<-context;authority$record<-record;authority$guards<-guards;authority$path<-path;authority$artifact_path<-source$artifact_path;authority$verified<-FALSE
  lockEnvironment(authority,bindings=TRUE);opened<-list(record=record,context=context,authority=authority)
  refs<-list(list(hash=r$artifact$sha256,size=r$artifact$bytes),r$result_object,b$result_object,list(hash=b$index$hash,size=b$index$size));refs<-Filter(Negate(is.null),refs)
  files<-lapply(refs,function(ref)list(path=brohn_object_path(store,ref$hash,verify=FALSE),sha256=ref$hash,bytes=ref$size))
  payload<-brohn_json(files);payload_hash<-brohn_hash(files)
  index_request<-list(index_path=path,index=list(sha256=b$index$hash,bytes=b$index$size,manifest_sha256=b$index$manifest_sha256),binding_sha256=r$binding_sha256)
  code<-paste(c("import hashlib,importlib.util,json,os,sys", "raw=sys.argv[1];items=json.loads(raw)",
    "for x in items:"," assert os.path.getsize(x['path'])==x['bytes'],'Saved source size changed'",
    " with open(x['path'],'rb') as f: assert hashlib.file_digest(f,'sha256').hexdigest()==x['sha256'],'Saved source digest changed'",
    "spec=importlib.util.spec_from_file_location('vision_explorer','scripts/workers/vision_explorer.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)",
    "with v.opened(json.loads(sys.argv[2])) as (_,manifest): manifest_hash=v.sha(v.encoded(manifest))",
    "print(json.dumps({'status':'verified','request_sha256':hashlib.sha256(raw.encode()).hexdigest(),'manifest_sha256':manifest_hash}))"),collapse="\n")
  process<-processx::process$new(.brohn_publication_python(),c("-B","-c",code,payload,brohn_json(index_request)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
  pending<-new.env(parent=emptyenv());pending$opened<-opened;pending$process<-process;pending$request_hash<-payload_hash
  pending$state<-new.env(parent=emptyenv());pending$state$owns_guards<-TRUE
  lockEnvironment(pending,bindings=TRUE);success<-TRUE;pending
}
brohn_cancel_vision_index_open <- function(pending) {
  if(is.environment(pending)&&environmentIsLocked(pending)&&isTRUE(pending$state$owns_guards)){
    if(pending$process$is_alive())pending$process$kill_tree()
    brohn_close_vision_index(pending$opened)
    state<-pending$state;state$owns_guards<-FALSE
  };invisible(NULL)
}
brohn_poll_vision_index_open <- function(store,pending) {
  brohn_require(is.environment(pending)&&environmentIsLocked(pending)&&isTRUE(pending$state$owns_guards),"Choose an owned pending video verification that has not been adopted or cancelled.")
  opened<-pending$opened;c<-opened$context;success<-FALSE
  on.exit(if(!success)brohn_cancel_vision_index_open(pending),add=TRUE)
  brohn_check_vision_index_context(store,opened,c$report_id,c$report_revision,c$report_hash,c$project_id,.pending=TRUE)
  if(pending$process$is_alive()){success<-TRUE;return(NULL)}
  stdout<-pending$process$read_all_output();stderr<-pending$process$read_all_error()
  brohn_require(pending$process$get_exit_status()==0L&&nchar(stdout,type="bytes")<=4096,paste("Video source verification needs attention:",substr(stderr,1,1200)))
  proof<-brohn_parse(stdout,4096);brohn_require(identical(proof$status,"verified")&&identical(proof$request_sha256,pending$request_hash),"Background verification belongs to another exact source.")
  b<-opened$record$body;r<-b$request
  brohn_require(identical(proof$manifest_sha256,b$index$manifest_sha256),"Background index verification changed its saved manifest.")
  # The native handles stayed open across the background full-byte check.
  # These bounded JSON documents now need only their semantic/source comparison.
  saved<-brohn_read_json_file(brohn_object_path(store,b$result_object$hash,verify=FALSE))
  brohn_require(identical(brohn_hash(saved),brohn_hash(b[setdiff(names(b),"result_object")])),"Index publication document changed.")
  if(!is.null(r$result_object)){
    source<-.brohn_vexplorer_source(store,c$report_id,c$report_revision,c$report_hash,c$project_id,FALSE)
    retained<-brohn_read_json_file(brohn_object_path(store,r$result_object$hash,verify=FALSE));body<-source$report$body
    brohn_require(identical(retained$schema,"brohn-analysis-output/1.0")&&identical(brohn_hash(retained$report),brohn_hash(body[setdiff(names(body),"result_object")])),"Saved video differs from its retained original result.")
  }
  authority<-list2env(as.list(opened$authority),parent=emptyenv());authority$verified<-TRUE;lockEnvironment(authority,bindings=TRUE);opened$authority<-authority
  catalog<-brohn_vision_index_read(store,opened,"catalog");brohn_require(identical(brohn_hash(catalog$manifest),brohn_hash(b$manifest)),"Opened video index changed its manifest.")
  state<-pending$state;state$owns_guards<-FALSE;success<-TRUE;opened
}
# Synchronous convenience for command-line/storage tests only. Shiny uses begin,
# non-blocking poll and cancel, retaining all native handles across verification.
brohn_open_vision_index <- function(store,index_id,index_hash,report_id,report_revision,report_hash,project_id) {
  pending<-brohn_begin_vision_index_open(store,index_id,index_hash,report_id,report_revision,report_hash,project_id)
  success<-FALSE;on.exit(if(!success)brohn_cancel_vision_index_open(pending),add=TRUE)
  pending$process$wait(20*60*1000);result<-brohn_poll_vision_index_open(store,pending)
  brohn_require(!is.null(result),"Video source verification exceeded its wait limit.");success<-TRUE;result
}
brohn_check_vision_index_context <- function(store,opened,report_id,report_revision,report_hash,project_id,.pending=FALSE) {
  a<-opened$authority;c<-opened$context
  brohn_require(is.environment(a)&&environmentIsLocked(a)&&(isTRUE(a$verified)||isTRUE(.pending))&&identical(brohn_hash(a$context),brohn_hash(c))&&identical(brohn_hash(a$record),brohn_hash(opened$record))&&
    identical(c$workspace_id,store$workspace_id)&&identical(c$root,store$root)&&identical(c$project_id,project_id)&&identical(c$report_id,report_id)&&
    identical(as.numeric(c$report_revision),as.numeric(report_revision))&&identical(c$report_hash,report_hash),"Reopen this video view in its exact original source context.")
  brohn_project(store,project_id)
  brohn_require(identical(.brohn_qexplorer_catalog(store,"report",c$report_id,c$report_revision,project_id),c$report_catalog)&&
    identical(.brohn_qexplorer_catalog(store,"dataset",c$dataset_id,c$dataset_revision,project_id),c$dataset_catalog)&&
    identical(.brohn_qexplorer_catalog(store,"vision_index",c$index_id,c$index_revision,project_id),c$index_catalog),"Saved video authority is no longer current in this project.")
  for(g in a$guards){brohn_require(is.environment(g)&&!is.null(g$pointer),"Reopen the closed immutable video view.");.Call(g$native$check,g$pointer)}
  invisible(TRUE)
}
brohn_vision_index_read <- function(store,opened,operation=c("catalog","page","detail","plot"),selection=list()) {
  operation<-match.arg(operation);a<-opened$authority;c<-opened$context
  brohn_check_vision_index_context(store,opened,c$report_id,c$report_revision,c$report_hash,c$project_id)
  allowed<-switch(operation,catalog=character(),page=c("metric","range","limit","cursor"),detail="frame_index",plot=c("metric","range","channel","max_points"))
  brohn_require(is.list(selection)&&all(names(selection)%in%allowed)&&!anyDuplicated(names(selection)),"Unsupported video view selection.")
  b<-a$record$body;index<-c(list(sha256=b$index$hash,bytes=b$index$size),b$index[c("schema","manifest_sha256")])
  request<-c(list(schema="brohn-vision-explorer-request/1.0",operation=operation,index_path=a$path,index=index,binding_sha256=b$request$binding_sha256,guarded_verified=TRUE),selection)
  if(operation=="detail")request$artifact_path<-a$artifact_path
  directory<-tempfile("brohn-video-read-",tmpdir=file.path(store$root,"work"));brohn_require(dir.create(directory,recursive=TRUE),"Cannot prepare owned video read work.")
  directory<-.brohn_store_contained(store,directory)
  parent<-normalizePath(file.path(store$root,"work"),winslash="/",mustWork=TRUE)
  brohn_require(identical(tolower(dirname(directory)),tolower(parent))&&startsWith(basename(directory),"brohn-video-read-"),"Owned video read directory escaped its workspace.")
  # Only this freshly-created private directory is removed; the immutable index
  # and original source paths are never cleanup targets.
  on.exit(unlink(directory,recursive=TRUE,force=TRUE),add=TRUE)
  result<-.brohn_vexplorer_run(request,directory)
  brohn_check_vision_index_context(store,opened,c$report_id,c$report_revision,c$report_hash,c$project_id)
  result
}
