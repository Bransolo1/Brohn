# Actual supervised frame jobs over the three already-saved model references.
# Independent pixel/variable-PTS arithmetic is in tests/workers/vision_frame.py.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
source("R/platform-load.R",encoding="UTF-8");brohn_load()
local({
  reference<-brohn_read_json_file(file.path(args[[1L]],"acceptance.json"))
  folder<-normalizePath(args[[2L]],winslash="/",mustWork=FALSE)
  stopifnot(!dir.exists(folder),startsWith(basename(folder),"brohn-vision-frames-saved-"));dir.create(folder,recursive=TRUE)
  stopifnot(file.copy(reference$workspace,folder,recursive=TRUE))
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store))
  checks<-character();frames<-list();check<-function(label,value){if(!isTRUE(value))stop(label);checks<<-c(checks,label);cat("PASS ",label,"\n",sep="")}
  open_index<-function(c)brohn_open_vision_index(store,c$index_id,c$index_hash,c$report_id,c$report_revision,c$report_hash,"default")
  open_image<-function(opened,id,hash){p<-brohn_begin_vision_frame_open(store,opened,id,hash,3L);success<-FALSE
    on.exit(if(!success)brohn_cancel_vision_frame_open(p),add=TRUE)
    p$process$wait(30000);v<-brohn_poll_vision_frame_open(store,p);stopifnot(!is.null(v));success<-TRUE;v}
  for(family in names(reference$cases)) {
    c<-reference$cases[[family]];opened<-open_index(c)
    tryCatch({
      q<-brohn_queue_vision_frame(store,opened,3L);claim<-brohn_claim_job(store,"supervised-recorded-frame",300);stopifnot(q$id==claim$id)
      brohn_process_job(store,claim,timeout_seconds=1900);done<-brohn_get_job(store,q$id)
      check(paste(family,"actual recorded-frame child publishes successfully",brohn_json(done$error)),identical(done$status,"succeeded"))
      saved<-brohn_get_entity(store,"vision_frame",done$result$vision_frame_id);v<-saved$body$frame
      check(paste(family,"saved final frame keeps original index, nonzero PTS and exact transform"),v$frame$frame_index==3&&v$frame$source_pts_s=="2.600000"&&
        v$extraction$decoded_frames_to_selection==4&&identical(v$extraction$policy,"sequential_original_rgb24_no_seek_no_autorotation")&&
        identical(brohn_hash(v$extraction$transform),brohn_hash(list(scale_x=1,scale_y=1,offset_x=0,offset_y=0,mirror=FALSE,rotation_degrees=0))))
      image<-open_image(opened,saved$id,done$result$frame_hash)
      tryCatch({
        brohn_check_vision_frame_context(store,image,opened,3L)
        check(paste(family,"guarded asynchronous image matches immutable published bytes"),identical(digest::digest(file=image$authority$path,algo="sha256"),done$result$image_hash)&&
          identical(as.numeric(file.info(image$authority$path)$size),as.numeric(v$image$size)))
      },finally=brohn_close_vision_frame(image))
      check(paste(family,"extracting the original image preserves model report and observations"),identical(brohn_hash(brohn_get_entity(store,"report",c$report_id)$body),c$report_hash)&&
        identical(digest::digest(file=brohn_object_path(store,c$artifact$hash),algo="sha256"),c$artifact$hash))
      frames[[family]]<-list(id=saved$id,hash=done$result$frame_hash,image_hash=done$result$image_hash,index=c,frame_index=3L)
    },finally=brohn_close_vision_index(opened))
  }
  brohn_close_store(store);store<-brohn_open_store(file.path(folder,"workspace"))
  for(family in names(frames)) {
    f<-frames[[family]];opened<-open_index(f$index)
    tryCatch({image<-open_image(opened,f$id,f$hash)
      tryCatch(check(paste(family,"original saved frame reopens after store restart"),identical(image$record$body$frame$image$hash,f$image_hash)),finally=brohn_close_vision_frame(image))
    },finally=brohn_close_vision_index(opened))
  }
  brohn_write_json_file(list(checks=checks,frames=frames,workspace=store$root,jobs=brohn_list_jobs(store,limit=100L),
    scope="Actual supervised recorded-frame extraction and storage; source agreement only, not model or hardware qualification."),file.path(folder,"acceptance.json"))
})
