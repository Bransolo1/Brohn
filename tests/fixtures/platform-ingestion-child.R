args<-commandArgs(trailingOnly=TRUE)
source("R/platform-load.R");brohn_load(ui=FALSE);source("R/platform-ingestion.R")
mode<-args[[1]]
if(mode=="analyse") {
  input<-brohn_read_json_file(args[[2]]);scratch<-args[[3]];output<-args[[4]]
  paths<-c("R/platform-ingestion.R","R/platform-publication.R","scripts/workers/ingestion_snapshot.py","scripts/workers/publication.py","src/publication_guard.c")
  identity<-setNames(lapply(paths,function(p)digest::digest(file=p,algo="sha256")),paths)
  report<-brohn_analyse_ingestion(input,scratch)
  stopifnot(identical(identity,setNames(lapply(paths,function(p)digest::digest(file=p,algo="sha256")),paths)))
  brohn_write_json_file(list(schema="brohn-analysis-output/1.0",code_identity=identity,report=report),output)
} else if(mode=="owner") {
  store<-brohn_open_store(args[[2]]);on.exit(brohn_close_store(store))
  upload<-tempfile("original-owner-",fileext=".edf")
  bytes<-as.numeric(args[[4]]);connection<-file(upload,"wb");chunk<-as.raw(rep(0:255,length.out=1024^2))
  for(i in seq_len(bytes/length(chunk)))writeBin(chunk,connection)
  close(connection)
  record<-brohn_queue_ingestion(store,list(path=upload,name="original.edf",size=file.info(upload)$size,reference="original-owner-upload"),
    "Original owner lifetime fixture","eeg","sample",operation_id="original-owner-intake")
  brohn_write_json_file(list(id=record$id,job_id=record$body$job_id),args[[3]])
  repeat Sys.sleep(.05)
} else stop("Unknown fixture mode")
