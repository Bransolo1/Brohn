source("R/platform-store.R")
args<-commandArgs(TRUE);request<-readRDS(args[[1]])
store<-brohn_open_store(request$workspace)
writeLines("ready",request$ready)
deadline<-as.numeric(Sys.time())+15
while(!file.exists(request$start)){if(as.numeric(Sys.time())>deadline)stop("Prepared job race barrier expired.");Sys.sleep(.01)}
result<-tryCatch(brohn_store_batch(store,function(){
  job<-brohn_enqueue_job(store,"original-prepared-fixture",list(original=TRUE),request$key,prepared_id=request$id)
  if(!identical(job$id,request$id))stop("Prepared export and actual idempotent job differ.")
  brohn_put_entity(store,"prepared_fixture",request$entity,list(job_id=job$id))
  job$id
}),error=function(e)list(error=conditionMessage(e)))
saveRDS(result,request$output);brohn_close_store(store)
