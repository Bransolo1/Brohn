# A real child job must read sources that remain sealed until it terminates.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
  args<-commandArgs(trailingOnly=TRUE)
  folder<-if(length(args))args[[1L]]else tempfile("brohn-processing-guards-")
  stopifnot(.Platform$OS.type=="windows",startsWith(basename(folder),"brohn-processing-guards-"),!dir.exists(folder))
  dir.create(folder,recursive=TRUE);folder<-normalizePath(folder,winslash="/",mustWork=TRUE)
  source_path<-file.path(folder,"original-no-audio.mkv")
  ffmpeg<-Sys.which("ffmpeg");brohn_require(nzchar(ffmpeg),"The isolated FFmpeg fixture generator is unavailable.")
  processx::run(ffmpeg,c("-hide_banner","-loglevel","error","-nostdin","-n","-f","lavfi","-i","color=c=black:s=64x64:r=5:d=1","-c:v","ffv1",source_path),
    timeout=30,windows_hide_window=TRUE,cleanup_tree=TRUE)
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  d<-brohn_ingest_dataset(store,source_path,"Original source-guard test pattern","video",origin="sample")
  object_path<-brohn_object_path(store,d$body$source$hash)
  # Isolated fixture only: remove the ordinary read-only attribute so this
  # exercises the native sharing guard, not a permanent file attribute.
  stopifnot(Sys.chmod(object_path,"0666"))
  on.exit(Sys.chmod(object_path,"0444"),add=TRUE)
  baseline<-file(object_path,"r+b");close(baseline)
  job<-brohn_queue_audio_extraction(store,d$id,d$revision,.brohn_sv_hash(d$body),d$project_id)
  claim<-brohn_claim_job(store,"original-source-read-guard-test",lease_seconds=120);stopifnot(identical(claim$id,job$id))
  checks<-character();check<-function(label,ok){stopifnot(isTRUE(ok));checks<<-c(checks,label);cat("PASS",label,"\n")}
  check("The isolated source permits a write handle before native guarding",TRUE)
  original_write<-brohn_write_json_file;attempted<-FALSE;denied<-FALSE
  on.exit(assign("brohn_write_json_file",original_write,envir=.GlobalEnv),add=TRUE)
  # Instrument only this test process immediately before child launch. Opening
  # a write handle tests Windows sharing rights; no source bytes are altered.
  assign("brohn_write_json_file",function(value,path,maximum=16*1024^2){
    if(identical(basename(path),"request.json")&&identical(value$operation,"audio_tracks")){
      attempted<<-TRUE
      con<-tryCatch(suppressWarnings(file(value$source_path,"r+b")),error=function(e)NULL)
      denied<<-is.null(con);if(!is.null(con))close(con)
    }
    original_write(value,path,maximum)
  },envir=.GlobalEnv)
  brohn_process_job(store,claim,timeout_seconds=120)
  assign("brohn_write_json_file",original_write,envir=.GlobalEnv)
  done<-brohn_get_job(store,job$id)
  check("Actual decoder source rejects a concurrent write handle before child launch",attempted&&denied)
  check("The real bounded inspection and guarded publication still succeed",identical(done$status,"succeeded"))
  result<-brohn_audio_extraction_record(store,done$result$audio_extraction_id,"default",verify=TRUE)
  check("No-audio inspection preserves its explicit absence and creates no recording",length(result$body$result$tracks)==0L&&is.null(result$body$derived_dataset_id))
  check("The original source bytes remain unchanged",identical(d$body$source$hash,digest::digest(file=brohn_object_path(store,d$body$source$hash),algo="sha256")))
  con<-file(brohn_object_path(store,d$body$source$hash),"r+b");close(con)
  check("Parent source handles are released after the child job terminates",TRUE)
  brohn_write_json_file(list(status="passed",checks=as.list(checks),job_id=job$id,result_id=result$id,
    source_hash=d$body$source$hash,code_identity=result$body$processing$code_hashes),file.path(folder,"results.json"))
})
