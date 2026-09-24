# Actual optional facial inference must hold the original recording unwritable through publication.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
  args<-commandArgs(trailingOnly=TRUE)
  folder<-if(length(args))args[[1L]]else tempfile("brohn-facial-source-guards-")
  stopifnot(.Platform$OS.type=="windows",startsWith(basename(folder),"brohn-facial-source-guards-"),!dir.exists(folder))
  dir.create(folder,recursive=TRUE);folder<-normalizePath(folder,winslash="/",mustWork=TRUE)
  source_path<-file.path(folder,"original-two-blank-frames.mkv")
  ffmpeg<-Sys.which("ffmpeg");brohn_require(nzchar(ffmpeg),"The isolated FFmpeg fixture generator is unavailable.")
  processx::run(ffmpeg,c("-hide_banner","-loglevel","error","-nostdin","-n","-f","lavfi","-i","color=c=black:s=64x64:r=2:d=1","-c:v","ffv1",source_path),
    timeout=30,windows_hide_window=TRUE,cleanup_tree=TRUE)
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  d<-brohn_ingest_dataset(store,source_path,"Original source-guard test pattern","video",origin="sample")
  object_path<-brohn_object_path(store,d$body$source$hash)
  # Isolated fixture only: remove the ordinary read-only attribute so this
  # exercises the native sharing guard, not a permanent file attribute.
  stopifnot(Sys.chmod(object_path,"0666"))
  on.exit(Sys.chmod(object_path,"0444"),add=TRUE)
  baseline<-file(object_path,"r+b");close(baseline)
  metadata<-list(profile=.brohn_facial_profile,origin_statement="Original FFmpeg-generated two blank frames; no participant.",
    consent_statement="Synthetic software test; no person or captured facial data.",start_s="0",frame_stride=1L,max_support_gap_s=1)
  d<-brohn_curate_dataset(store,d$id,metadata,d$revision)
  job<-brohn_queue_dataset(store,d$id,d$revision)
  claim<-brohn_claim_job(store,"facial-source-read-guard-test",lease_seconds=120);stopifnot(identical(claim$id,job$id))
  checks<-character();check<-function(label,ok){stopifnot(isTRUE(ok));checks<<-c(checks,label);cat("PASS",label,"\n")}
  check("The isolated source permits a write handle before native guarding",TRUE)
  original_write<-brohn_write_json_file;attempted<-FALSE;denied<-FALSE
  on.exit(assign("brohn_write_json_file",original_write,envir=.GlobalEnv),add=TRUE)
  # Instrument only this test process immediately before child launch. Opening
  # a write handle tests Windows sharing rights; no source bytes are altered.
  assign("brohn_write_json_file",function(value,path,maximum=16*1024^2){
    if(identical(basename(path),"request.json")&&identical(value$operation,"analyse_dataset")){
      attempted<<-TRUE
      con<-tryCatch(suppressWarnings(file(value$source_path,"r+b")),error=function(e)NULL)
      denied<<-is.null(con);if(!is.null(con))close(con)
    }
    original_write(value,path,maximum)
  },envir=.GlobalEnv)
  brohn_process_job(store,claim,timeout_seconds=240)
  assign("brohn_write_json_file",original_write,envir=.GlobalEnv)
  done<-brohn_get_job(store,job$id)
  check("Actual decoder source rejects a concurrent write handle before child launch",attempted&&denied)
  check("The real bounded inspection and guarded publication still succeed",identical(done$status,"succeeded"))
  result<-brohn_get_entity(store,"report",done$result$report_id)
  check("Actual model retains no-face support and null native summaries",brohn_facial_supported(result$body$analysis)&&
    result$body$analysis$quality$eligible_single_face_frames==0L&&all(vapply(result$body$analysis$features,function(x)is.null(x$value),logical(1))))
  check("Complete facial CSV keeps its media identity",any(vapply(result$body$analysis$artifacts,function(x)identical(x$kind,"facial-values")&&identical(x$media_type,"text/csv"),logical(1))))
  check("The original source bytes remain unchanged",identical(d$body$source$hash,digest::digest(file=brohn_object_path(store,d$body$source$hash),algo="sha256")))
  con<-file(brohn_object_path(store,d$body$source$hash),"r+b");close(con)
  check("Parent source handles are released after the child job terminates",TRUE)
  brohn_write_json_file(list(status="passed",checks=as.list(checks),job_id=job$id,result_id=result$id,
    source_hash=d$body$source$hash,code_identity=result$body$processing$code_hashes),file.path(folder,"results.json"))
})
