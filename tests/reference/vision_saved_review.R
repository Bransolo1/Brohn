# Real supervised model reports and source-bound video indexes from permitted
# official reference images. This qualifies software/source agreement only.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
source("R/platform-load.R",encoding="UTF-8");brohn_load()
local({
  reference<-normalizePath(args[[1]],winslash="/",mustWork=TRUE);folder<-normalizePath(args[[2]],winslash="/",mustWork=FALSE)
  stopifnot(!dir.exists(folder),startsWith(basename(folder),"brohn-vision-saved-"));dir.create(folder,recursive=TRUE)
  store<-brohn_open_store(file.path(folder,"workspace"));brohn_initialise_library(store);on.exit(brohn_close_store(store))
  refs<-brohn_read_json_file(file.path(reference,"reference-manifest.json"))
  checks<-character();cases<-list();check<-function(label,ok){if(!isTRUE(ok))stop(label);checks<<-c(checks,label);cat("PASS ",label,"\n",sep="")}
  execute<-function(q){force(q);claim<-brohn_claim_job(store,"saved-video-reference",300);stopifnot(claim$id==q$id)
    brohn_process_job(store,claim,timeout_seconds=1900);done<-brohn_get_job(store,q$id)
    if(done$status!="succeeded")stop(brohn_json(done$error));done}
  for(family in c("face","pose","hands")) {
    source_path<-file.path(reference,family,"official-static-reference.mkv")
    imported<-brohn_ingest_dataset(store,source_path,paste("Official static",family,"software reference"),"video",origin="sample")
    mapping<-list(origin_statement=paste("Official Apache-2.0 MediaPipe test image encoded into four identical frames;",refs$cases[[family]]$source_url,
      "No physical capture or model accuracy qualification."),profile="custom_v1",channels=list(family))
    dataset<-brohn_curate_dataset(store,imported$id,mapping,imported$revision)
    done<-execute(brohn_queue_dataset(store,dataset$id));report<-brohn_get_entity(store,"report",done$result$report_id)
    hash<-brohn_hash(report$body);a<-report$body$analysis
    check(paste(family,"actual saved model report has four valid frames and explicit source PTS"),a$quality$analysed_frames==4&&a$quality$channels[[family]]$valid_frames==4&&
      identical(a$parameters$source_pts_origin_s,"2.000000")&&identical(a$parameters$orientation,"encoded pixels, no autorotation"))
    check(paste(family,"saved source and exact model pins match permitted reference"),identical(a$source$sha256,refs$cases[[family]]$video_sha256)&&
      identical(brohn_hash(a$engine$models),brohn_hash(refs$cases[[family]]$engine$models)))
    artifact<-Filter(function(x)identical(x$kind,"vision-observations"),a$artifacts)[[1L]]
    path<-brohn_object_path(store,artifact$hash);lines<-readLines(path,warn=FALSE,encoding="UTF-8")
    Sys.chmod(path,"0666");probe<-function()processx::run(.brohn_publication_python(),c("-B","-c","import sys;f=open(sys.argv[1],'r+b');f.close()",path),error_on_status=FALSE,windows_hide_window=TRUE)$status==0L
    check(paste(family,"observation artifact is writable before native guard control"),probe())
    stage<-.brohn_publication_stage;denied<-FALSE
    assign(".brohn_publication_stage",function(...){denied<<-!probe();stage(...)},envir=.GlobalEnv)
    done<-tryCatch(execute(brohn_queue_vision_index(store,report$id,report$revision,hash,"default")),finally=assign(".brohn_publication_stage",stage,envir=.GlobalEnv))
    check(paste(family,"supervised index guards original observations through publication and releases after"),denied&&probe())
    index_id<-done$result$vision_index_id;index_hash<-done$result$index_hash
    opened<-brohn_open_vision_index(store,index_id,index_hash,report$id,report$revision,hash,"default")
    tryCatch({
      catalog<-brohn_vision_index_read(store,opened,"catalog")
      check(paste(family,"complete native index catalog retains all four frames"),catalog$manifest$frames==4&&length(catalog$manifest$metrics)>0)
      for(frame in 0:3) {
        detail<-brohn_vision_index_read(store,opened,"detail",list(frame_index=frame))
        original<-Filter(function(line)identical(as.numeric(brohn_parse(line)$frame_index),as.numeric(frame)),lines)
        check(paste(family,"selected frame",frame,"is the exact original native observation line"),length(original)==1L&&identical(sub("[\r\n]+$","",detail$original_json),original[[1L]]))
      }
      metric<-catalog$manifest$metrics[[1L]]$id
      page<-brohn_vision_index_read(store,opened,"page",list(metric=metric,limit=2L))
      next_page<-brohn_vision_index_read(store,opened,"page",list(metric=metric,limit=2L,cursor=page$next_cursor))
      check(paste(family,"native page cursor reaches the final analysed frame"),page$total==4&&next_page$rows[[2L]]$frame_index==3&&is.null(next_page$next_cursor))
      plot<-brohn_vision_index_read(store,opened,"plot",list(channel=family,metric=metric))
      check(paste(family,"plot support and saved units remain explicit"),plot$support$frames==4&&plot$support$metric_valid_frames==4&&brohn_text(plot$metric$unit,100)&&
        plot$support$displayed_points==4)
    },finally=brohn_close_vision_index(opened))
    Sys.chmod(path,"0444")
    check(paste(family,"original report and observation bytes remain unchanged"),identical(brohn_hash(brohn_get_entity(store,"report",report$id)$body),hash)&&
      identical(digest::digest(file=path,algo="sha256"),artifact$hash))
    cases[[family]]<-list(report_id=report$id,report_hash=hash,report_revision=report$revision,dataset_id=dataset$id,index_id=index_id,index_hash=index_hash,
      artifact=artifact,source_url=refs$cases[[family]]$source_url,model_pins=a$engine$models)
  }
  brohn_close_store(store);store<-brohn_open_store(file.path(folder,"workspace"))
  for(family in names(cases)) {
    c<-cases[[family]];opened<-brohn_open_vision_index(store,c$index_id,c$index_hash,c$report_id,c$report_revision,c$report_hash,"default")
    check(paste(family,"original saved index reopens with its publication receipt"),brohn_vision_index_read(store,opened,"catalog")$manifest$frames==4)
    brohn_close_vision_index(opened)
  }
  brohn_write_json_file(list(checks=checks,cases=cases,workspace=store$root,jobs=brohn_list_jobs(store,limit=100L),reference_manifest=refs,
    qualification="Official static reference imagery through actual models, immutable reports, supervised native indexes and exact original row reads; no population accuracy or hardware qualification."),file.path(folder,"acceptance.json"))
})
