# Unwired exact recorded-frame jobs. The saved observation index supplies identity.
.brohn_vframe_files<-c("R/platform-vision-frame.R","R/platform-vision-explorer.R","scripts/workers/vision_frame.py","scripts/workers/vision.py","scripts/workers/vision_explorer.py")
.brohn_vframe_loaded<-setNames(lapply(.brohn_vframe_files,function(p)digest::digest(file=p,algo="sha256")),.brohn_vframe_files)
.brohn_vframe_recipe<-"saved-video-recorded-frame/1.0"
.brohn_vframe_index<-function(store,r) {
  record<-brohn_get_entity(store,"vision_index",r$index_id)
  brohn_require(!is.null(record)&&identical(record$project_id,r$project_id)&&identical(brohn_hash(record$body),r$index_hash),"The recorded frame belongs to another saved video view.")
  b<-record$body;q<-b$request
  brohn_require(identical(q$report_id,r$report_id)&&identical(as.numeric(q$report_revision),as.numeric(r$report_revision))&&identical(q$report_hash,r$report_hash),"The frame's exact original report changed.")
  source<-.brohn_vexplorer_source(store,r$report_id,r$report_revision,r$report_hash,r$project_id,FALSE)
  brohn_require(identical(brohn_hash(source$binding),brohn_hash(b$binding))&&identical(brohn_hash(q),b$request_hash),"The frame's original source authority changed.")
  job<-brohn_get_job(store,b$processing$job_id)
  brohn_require(identical(job$status,"succeeded")&&identical(job$operation,"vision_index")&&identical(job$result$vision_index_id,r$index_id)&&
    identical(job$result$index_hash,r$index_hash)&&identical(job$result$artifact_hash,b$index$hash)&&identical(job$result$output_hash,b$result_object$hash),"This video index has no matching completed publication.")
  list(record=record,source=source)
}
brohn_queue_vision_frame<-function(store,opened,frame_index,rebuild=FALSE) {
  c<-opened$context;brohn_check_vision_index_context(store,opened,c$report_id,c$report_revision,c$report_hash,c$project_id)
  brohn_require(brohn_number(frame_index,0,35999,TRUE)&&is.logical(rebuild)&&length(rebuild)==1L&&!is.na(rebuild),"Choose an exact saved frame.")
  detail<-brohn_vision_index_read(store,opened,"detail",list(frame_index=frame_index))
  r<-list(schema="brohn-vision-frame-job/1.0",recipe=.brohn_vframe_recipe,index_id=c$index_id,index_hash=c$index_hash,
    report_id=c$report_id,report_revision=c$report_revision,report_hash=c$report_hash,project_id=c$project_id,frame=detail$frame,implementation=.brohn_vframe_loaded)
  .brohn_vframe_index(store,r)
  brohn_store_batch(store,function(){.brohn_vframe_index(store,r);key<-paste0("vision-frame:",brohn_hash(r))
    if(!rebuild){old<-DBI::dbGetQuery(store$con,"SELECT * FROM jobs WHERE operation='vision_frame' AND request_hash=? ORDER BY created_at DESC,rowid DESC LIMIT 1",params=list(.brohn_store_hash(charToRaw(.brohn_store_json(r)))))
      if(nrow(old))return(.brohn_store_job(old))}
    brohn_enqueue_job(store,"vision_frame",r,if(rebuild)paste0(key,":",brohn_id("rebuild"))else key)})
}
.brohn_vframe_guards<-function(store,request) {
  x<-.brohn_vframe_index(store,request);b<-x$record$body
  guards<-.brohn_vexplorer_guards(store,b$request);success<-FALSE;on.exit(if(!success)for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  refs<-list(b$result_object,b$index,b$binding$original_source)
  for(ref in refs)guards[[length(guards)+1L]]<-.brohn_qexplorer_hold(brohn_object_path(store,ref$hash,verify=FALSE),ref$size)
  success<-TRUE;guards
}
brohn_vision_frame_input<-function(store,job) {
  r<-job$request
  brohn_fields(r,c("schema","recipe","index_id","index_hash","report_id","report_revision","report_hash","project_id","frame","implementation"),label="Recorded frame request")
  brohn_require(identical(job$operation,"vision_frame")&&identical(r$schema,"brohn-vision-frame-job/1.0")&&identical(r$recipe,.brohn_vframe_recipe)&&
    identical(brohn_hash(r$implementation),brohn_hash(.brohn_vframe_loaded))&&all(vapply(names(r$implementation),function(p)identical(digest::digest(file=p,algo="sha256"),r$implementation[[p]]),logical(1))),"Prepare a recorded frame with the current exact extraction implementation.")
  x<-.brohn_vframe_index(store,r);b<-x$record$body
  opened<-brohn_open_vision_index(store,r$index_id,r$index_hash,r$report_id,r$report_revision,r$report_hash,r$project_id);on.exit(brohn_close_vision_index(opened),add=TRUE)
  detail<-brohn_vision_index_read(store,opened,"detail",list(frame_index=r$frame$frame_index))
  brohn_require(identical(brohn_hash(detail$frame),brohn_hash(r$frame)),"The selected original frame/PTS changed.")
  source<-b$binding$original_source
  list(schema="brohn-analysis-input/1.0",operation="vision_frame",project_id=r$project_id,
    vision_frame_input=list(schema="brohn-vision-frame-request/1.0",source_path=brohn_object_path(store,source$hash),source=list(sha256=source$hash,bytes=source$size),
      index_path=opened$authority$path,index=list(sha256=b$index$hash,bytes=b$index$size,manifest_sha256=b$index$manifest_sha256),binding_sha256=b$request$binding_sha256,
      artifact_path=opened$authority$artifact_path,frame_index=r$frame$frame_index))
}
brohn_analyse_vision_frame<-function(input,scratch) {
  brohn_require(identical(input$operation,"vision_frame"),"Unsupported frame operation.")
  directory<-file.path(scratch,"artifacts");brohn_require(!dir.exists(directory)&&dir.create(directory),"Choose a fresh owned frame output directory.")
  request<-input$vision_frame_input;request$output_directory<-normalizePath(directory,winslash="/",mustWork=TRUE)
  in_path<-file.path(scratch,"frame-request.json");out_path<-file.path(scratch,"frame-result.json");brohn_write_json_file(request,in_path)
  p<-processx::run(.brohn_publication_python(),c("-B","scripts/workers/vision_frame.py","--request",in_path,"--output",out_path),timeout=1200,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(file.exists(out_path),paste("Recorded frame returned no response.",substr(p$stderr,1,1000)))
  result<-brohn_read_json_file(out_path,2*1024^2)
  brohn_require(p$status==0L&&identical(result$status,"complete")&&identical(result$schema,"brohn-vision-recorded-frame/1.0"),paste("Recorded frame needs attention:",brohn_default(result$error$message,substr(p$stderr,1,1000))))
  list(vision_frame=result)
}
brohn_publish_vision_frame<-function(store,output,scratch,job,input,output_path) {
  brohn_require(.Platform$OS.type=="windows"&&!RSQLite::sqliteIsTransacting(store$con),"Recorded-frame publication needs the native guard outside a writer transaction.")
  .brohn_publication_output_identity(output,.brohn_vframe_loaded);.brohn_publication_job(store,job)
  output_path<-.brohn_store_contained(store,output_path)
  brohn_require(file.exists(output_path)&&identical(tolower(dirname(output_path)),tolower(normalizePath(scratch,winslash="/",mustWork=TRUE))),"Frame output leaves its owned attempt.")
  guards<-.brohn_vframe_guards(store,job$request);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  brohn_require(identical(brohn_hash(input),brohn_hash(brohn_vision_frame_input(store,job)))&&identical(brohn_hash(output),brohn_hash(brohn_read_json_file(output_path))),"Frame publication changed its frozen input or output.")
  x<-.brohn_vframe_index(store,job$request);b<-x$record$body;value<-output$report$vision_frame;ref<-value$image
  brohn_require(identical(value$schema,"brohn-vision-recorded-frame/1.0")&&identical(value$status,"complete")&&identical(value$binding_sha256,b$request$binding_sha256)&&
    identical(value$index_sha256,b$index$hash)&&identical(brohn_hash(value$source),brohn_hash(input$vision_frame_input$source))&&
    identical(brohn_hash(value$artifact),brohn_hash(b$manifest$artifact))&&identical(brohn_hash(value$frame),brohn_hash(job$request$frame))&&
    identical(value$extraction$policy,"sequential_original_rgb24_no_seek_no_autorotation")&&identical(value$extraction$orientation,b$manifest$parameters$orientation)&&
    identical(value$extraction$ffmpeg,b$manifest$engine$ffmpeg)&&identical(value$extraction$ffprobe,b$manifest$engine$ffprobe)&&
    identical(brohn_hash(value$extraction$transform),brohn_hash(list(scale_x=1,scale_y=1,offset_x=0,offset_y=0,mirror=FALSE,rotation_degrees=0)))&&
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
  id<-paste0("vision-frame-",sub("^job_","",job$id))
  body<-list(schema="brohn-saved-vision-frame/1.0",id=id,recipe=.brohn_vframe_recipe,request=job$request,request_hash=brohn_hash(job$request),frame=value,created_at=brohn_now(),
    processing=list(job_id=job$id,attempt=job$attempt,worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity,publication=.brohn_publication_processing(context)))
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-vision-frame.json"))
  result<-brohn_store_batch(store,function(){.brohn_vframe_index(store,job$request);for(g in guards).Call(g$native$check,g$pointer)
    .brohn_publication_register(store,context);body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"vision_frame",id,body,0L,project_id=job$request$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(vision_frame_id=id,frame_hash=brohn_hash(body),image_hash=value$image$hash,output_hash=body$result_object$hash))})
  committed<-TRUE;result
}
brohn_close_vision_frame<-function(view) {
  if(is.environment(view$authority)&&environmentIsLocked(view$authority))for(g in view$authority$guards).brohn_qexplorer_release(g)
  invisible(NULL)
}
.brohn_vframe_open_context<-function(store,record,opened,frame_index) {
  c<-opened$context;brohn_check_vision_index_context(store,opened,c$report_id,c$report_revision,c$report_hash,c$project_id)
  b<-record$body;r<-b$request
  brohn_require(identical(record$project_id,c$project_id)&&identical(r$index_id,c$index_id)&&identical(r$index_hash,c$index_hash)&&
    identical(as.numeric(b$frame$frame$frame_index),as.numeric(frame_index)),"Open the recorded image for this exact selected frame and video view.")
  .brohn_vframe_index(store,r)
  brohn_require(identical(brohn_hash(brohn_get_entity(store,"vision_frame",record$id)$body),brohn_hash(b)),"The saved recorded frame changed.")
  job<-brohn_get_job(store,b$processing$job_id)
  brohn_require(identical(job$status,"succeeded")&&identical(job$operation,"vision_frame")&&identical(job$result$vision_frame_id,record$id)&&
    identical(job$result$frame_hash,brohn_hash(b))&&identical(job$result$image_hash,b$frame$image$hash)&&identical(job$result$output_hash,b$result_object$hash)&&
    identical(brohn_hash(job$request),b$request_hash),"Recorded image has no matching completed publication receipt.")
  invisible(TRUE)
}
brohn_begin_vision_frame_open<-function(store,opened,frame_id,frame_hash,frame_index) {
  record<-brohn_get_entity(store,"vision_frame",frame_id)
  brohn_require(!is.null(record)&&identical(brohn_hash(record$body),frame_hash),"Choose the exact saved recorded frame.")
  .brohn_vframe_open_context(store,record,opened,frame_index)
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
brohn_cancel_vision_frame_open<-function(pending) {
  if(is.environment(pending)&&environmentIsLocked(pending)&&isTRUE(pending$state$owns_guards)) {
    if(pending$process$is_alive())pending$process$kill_tree()
    for(g in pending$guards).brohn_qexplorer_release(g)
    state<-pending$state;state$owns_guards<-FALSE
  };invisible(NULL)
}
brohn_poll_vision_frame_open<-function(store,pending) {
  brohn_require(is.environment(pending)&&environmentIsLocked(pending)&&isTRUE(pending$state$owns_guards),"Choose a pending recorded image that has not been adopted or cancelled.")
  success<-FALSE;on.exit(if(!success)brohn_cancel_vision_frame_open(pending),add=TRUE)
  .brohn_vframe_open_context(store,pending$record,pending$opened,pending$frame_index)
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
brohn_check_vision_frame_context<-function(store,view,opened,frame_index) {
  a<-view$authority
  brohn_require(is.environment(a)&&environmentIsLocked(a)&&identical(a$index_authority,opened$authority)&&identical(brohn_hash(a$record),brohn_hash(view$record)),"Reopen this exact recorded frame.")
  .brohn_vframe_open_context(store,view$record,opened,frame_index)
  for(g in a$guards){brohn_require(!is.null(g$pointer),"Reopen the closed recorded image.");.Call(g$native$check,g$pointer)}
  invisible(TRUE)
}
