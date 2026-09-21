# Real pinned-model saved reports, direct frame child + native publication.
# Shared supervisor dispatch is qualified separately after integration.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE);source("R/platform-vision-frame.R",encoding="UTF-8")
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L,!dir.exists(args[[2L]]))
local({
  baseline<-brohn_read_json_file(file.path(args[[1]],"acceptance.json"));folder<-normalizePath(args[[2]],winslash="/",mustWork=FALSE);dir.create(folder,recursive=TRUE)
  processx::run(.brohn_publication_python(),c("-B","-c","import shutil,sys;shutil.copytree(sys.argv[1],sys.argv[2])",baseline$workspace,file.path(folder,"workspace")),windows_hide_window=TRUE)
  store<-brohn_open_store(file.path(folder,"workspace"));views<-list();images<-list();checks<-character();cases<-list()
  on.exit({for(x in images)try(brohn_close_vision_frame(x),silent=TRUE);for(x in views)try(brohn_close_vision_index(x),silent=TRUE);brohn_close_store(store)})
  check<-function(ok,label){stopifnot(isTRUE(ok));checks<<-c(checks,label);cat("PASS",label,"\n");flush.console()}
  rejected<-function(x)inherits(tryCatch({force(x);NULL},error=identity),"error")
  probe<-function(path)processx::run(.brohn_publication_python(),c("-B","-c","import sys;f=open(sys.argv[1],'r+b');f.close()",path),error_on_status=FALSE,windows_hide_window=TRUE)$status
  for(family in names(baseline$cases)) {
    original<-baseline$cases[[family]];view<-brohn_open_vision_index(store,original$index_id,original$index_hash,original$report_id,original$report_revision,original$report_hash,"default");views[[length(views)+1L]]<-view
    queue<-function(rebuild=FALSE)brohn_queue_vision_frame(store,view,2L,rebuild)
    prepare<-function(rebuild=FALSE){q<-queue(rebuild);job<-brohn_claim_job(store,"frame-storage-test",600);stopifnot(identical(job$id,q$id))
      guards<-.brohn_vframe_guards(store,job$request);on.exit(for(g in guards).brohn_qexplorer_release(g))
      input<-brohn_vision_frame_input(store,job);scratch<-file.path(store$root,"scratch",paste0(job$id,"-attempt-",job$attempt));dir.create(scratch,recursive=TRUE)
      value<-brohn_analyse_vision_frame(input,scratch);paths<-unique(c("R/platform-publication.R",names(.brohn_vframe_loaded),"scripts/workers/publication.py","src/publication_guard.c"))
      output<-list(schema="brohn-analysis-output/1.0",code_identity=setNames(lapply(paths,function(p)digest::digest(file=p,algo="sha256")),paths),report=value)
      path<-file.path(scratch,"output.json");brohn_write_json_file(output,path);list(job=job,input=input,scratch=scratch,output=output,path=path)}
    publish<-function(p)brohn_publish_vision_frame(store,p$output,p$scratch,p$job,p$input,p$path)
    prepared<-prepare();result<-publish(prepared);saved<-brohn_get_entity(store,"vision_frame",result$result$vision_frame_id)
    check(result$status=="succeeded"&&saved$body$frame$frame$source_pts_s=="2.400000"&&saved$body$frame$frame$frame_index==2L,paste(family,"exact original frame and PTS survive actual extraction and native publication"))
    check(identical(saved$body$processing$publication$mode,"staged-windows-parent-read-seal/1.0")&&saved$body$frame$extraction$transform$mirror==FALSE,paste(family,"native receipt preserves original image geometry"))
    check(identical(queue()$id,prepared$job$id),paste(family,"identical recorded-frame request reuses its completed job"))
    begin<-function()brohn_begin_vision_frame_open(store,view,saved$id,brohn_hash(saved$body),2L)
    pending<-begin();brohn_cancel_vision_frame_open(pending)
    check(rejected(brohn_poll_vision_frame_open(store,pending)),paste(family,"cancelled image verification cannot become displayable"))
    pending<-begin();pending$process$wait(120000);image<-brohn_poll_vision_frame_open(store,pending);images[[length(images)+1L]]<-image
    check(isTRUE(brohn_check_vision_frame_context(store,image,view,2L))&&rejected(brohn_check_vision_frame_context(store,image,view,1L)),paste(family,"recorded image is bound to the exact selected frame"))
    paths<-vapply(image$authority$guards,`[[`,character(1),"path");brohn_close_vision_frame(image);for(path in paths)Sys.chmod(path,"0666")
    check(all(vapply(paths,probe,integer(1))==0L),paste(family,"image and publication document are writable before read seals"))
    pending<-begin();pending$process$wait(120000);image<-brohn_poll_vision_frame_open(store,pending);images[[length(images)+1L]]<-image
    brohn_cancel_vision_frame_open(pending)
    check(all(vapply(paths,probe,integer(1))!=0L)&&rejected(brohn_poll_vision_frame_open(store,pending)),paste(family,"adopted image seals survive duplicate poll and cancellation"))
    altered<-image;altered$record$body$frame$frame$frame_index<-1L
    check(rejected(brohn_check_vision_frame_context(store,altered,view,2L)),paste(family,"public image metadata cannot substitute another frame"))
    brohn_close_vision_frame(image)
    check(all(vapply(paths,probe,integer(1))==0L)&&rejected(brohn_check_vision_frame_context(store,image,view,2L)),paste(family,"close releases image seals and rejects future display"))
    if(family=="face"){
      cancelled<-prepare(TRUE);brohn_cancel_job(store,cancelled$job$id)
      check(rejected(publish(cancelled))&&brohn_get_job(store,cancelled$job$id)$status=="cancelled","Cancelled frame extraction cannot publish its prepared PNG")
    }
    check(identical(brohn_hash(brohn_get_entity(store,"report",original$report_id)$body),original$report_hash)&&
      identical(digest::digest(file=brohn_object_path(store,original$artifact$hash),algo="sha256"),original$artifact$hash),paste(family,"original report and complete observations remain unchanged"))
    cases[[family]]<-c(original,list(frame_id=saved$id,frame_hash=brohn_hash(saved$body),image_hash=saved$body$frame$image$hash))
    brohn_close_vision_index(view)
  }
  brohn_write_json_file(list(checks=checks,cases=cases,workspace=store$root,qualification="actual public reference outputs plus direct frame child/native publication; not supervised frame dispatch or accuracy validation"),file.path(folder,"acceptance.json"))
  cat("PASS",length(checks),"recorded frame storage checks\n")
})
