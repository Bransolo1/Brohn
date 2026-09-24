# Actual derived index/frame jobs against a COPY of original native saved outputs.
args<-commandArgs(trailingOnly=TRUE);folder<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-facial-review-domain-"))
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
local({cfg<-brohn_read_json_file(file.path(folder,"fixture.json"));store<-brohn_open_store(cfg$workspace);on.exit(brohn_close_store(store),add=TRUE)
 checks<-character();check<-function(label,ok){stopifnot(isTRUE(ok));checks<<-c(checks,label);cat("PASS",label,"\n")};reject<-function(f)inherits(tryCatch(f(),error=identity),"error")
 finish<-function(j){force(j);claim<-brohn_claim_job(store,"facial-review-domain",300);stopifnot(identical(claim$id,j$id));brohn_process_job(store,claim,timeout_seconds=300);got<-brohn_get_job(store,j$id);if(got$status!="succeeded")stop(brohn_json(got));got}
 r<-brohn_get_entity(store,"report",cfg$report_id);hash<-brohn_hash(r$body)
 resume<-"--resume-index"%in%args
 if(resume){previous<-Filter(function(x)x$operation=="facial_review"&&x$status=="succeeded",brohn_list_jobs(store,limit=500L));stopifnot(length(previous)==1L);j<-previous[[1L]]}else j<-brohn_queue_facial_review(store,r$id,r$revision,hash,r$project_id)
 check("Exact original-source request has both complete artifacts and source refs",length(j$request$artifacts)==2L&&length(j$request$source_objects)>=4L)
 if(!resume)check("Repeated opening reuses the same exact queued index job",identical(brohn_queue_facial_review(store,r$id,r$revision,hash,r$project_id)$id,j$id))
 check("Wrong original report hash is refused",reject(function()brohn_prepare_facial_review(store,r$id,r$revision,paste(rep("0",64),collapse=""),r$project_id)))
 if(!resume)j<-finish(j);check(if(resume)"Historical sealed index reused after pixel-helper repair without rebuilding or inference"else"Actual guarded complete index publication succeeded",j$status=="succeeded")
 v<-brohn_open_facial_review(store,j$result$facial_review_id,j$result$index_hash,r$id,r$revision,hash,r$project_id);on.exit(brohn_close_facial_review(v),add=TRUE)
 plot<-brohn_facial_review_read(store,v,"plot",list(metric="AU12",range=NULL));check("Complete mixed-state view preserves6frames and missing scores",length(plot$points)==6L&&is.null(plot$points[[1L]]$value)&&is.null(plot$points[[4L]]$value))
 exact<-brohn_facial_review_read(store,v,"plot",list(metric="AU12",range=list("0.04000000000000000001","0.11")));check("R-to-child boundary preserves exact decimal range",length(exact$points)==1L&&exact$points[[1L]]$frame_index=="2")
 detail<-brohn_facial_review_read(store,v,"detail",list(frame_index=3L));check("Both frame-local faces and exact original JSON retained",length(detail$observation$faces)==2L&&brohn_parse(detail$original_json)$frame_index==3L)
 f<-finish(brohn_queue_facial_frame(store,v,3L));check("Actual original frame extraction publishes source-bound PNG",f$status=="succeeded")
 pending<-brohn_begin_facial_frame_open(store,v,f$result$facial_frame_id,f$result$frame_hash,3L);image<-NULL;for(i in seq_len(100)){image<-brohn_poll_facial_frame_open(store,pending);if(!is.null(image))break;Sys.sleep(.05)}
 stopifnot(!is.null(image));on.exit(brohn_close_facial_frame(image),add=TRUE)
 check("Native saved decodedRGB identity and640x454dimensions match",identical(image$record$body$frame$extraction$rgb24_sha256,detail$observation$decoded_rgb_sha256)&&image$record$body$frame$image$width==640L&&image$record$body$frame$image$height==454L)
 check("Wrong frame context cannot open image",reject(function()brohn_check_facial_frame_context(store,image,v,2L)))
 pending_csv<-brohn_begin_facial_csv(store,v,list(metric="happiness",range=NULL));on.exit(brohn_close_facial_csv(pending_csv),add=TRUE);csv<-NULL
 for(i in seq_len(100)){csv<-brohn_poll_facial_csv(store,pending_csv);if(!is.null(csv))break;Sys.sleep(.05)}
 check("Complete CSV exports7rows6frames with original native tokens",!is.null(csv)&&csv$rows==7L&&csv$frames==6L&&identical(digest::digest(file=csv$path,algo="sha256"),csv$sha256))
 brohn_close_facial_frame(image);check("Closed image is unusable",reject(function()brohn_check_facial_frame_context(store,image,v,3L)))
 brohn_close_facial_csv(pending_csv);brohn_close_facial_review(v);check("Closed original index is unusable",reject(function()brohn_facial_review_read(store,v,"catalog")))
 check("Immutable original saved report remains unchanged",identical(brohn_hash(brohn_get_entity(store,"report",r$id)$body),hash))
 check("Every copied and upstream source remains byte-identical",all(vapply(cfg$source_objects,function(x)identical(digest::digest(file=x$path,algo="sha256"),x$hash)&&identical(digest::digest(file=x$original_path,algo="sha256"),x$hash),logical(1))))
 brohn_write_json_file(list(status="passed",count=length(checks),checks=checks,joined_prior_attempt=resume,new_jobs=if(resume)list(f)else list(j,f),reused_index_job=if(resume)j else NULL,source_hashes=.brohn_freview_loaded,original_hash=hash),file.path(folder,"results.json"))
})
