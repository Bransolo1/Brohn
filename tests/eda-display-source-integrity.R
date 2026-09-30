# Runs only on an owned fresh copy of an explicit closed prepared fixture.
args<-commandArgs(TRUE);stopifnot(length(args)==3L)
repo<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
prepared<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
out<-args[[3L]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
stopifnot(dir.exists(file.path(prepared,"workspace")),file.copy(file.path(prepared,"workspace"),out,recursive=TRUE))
for(name in c("continuous-report.json","event-report.json"))if(file.exists(file.path(prepared,name)))stopifnot(file.copy(file.path(prepared,name),out,overwrite=FALSE))
stopifnot(file.copy(file.path(prepared,"results.json"),file.path(out,"original-results.json"),overwrite=FALSE))
config<-list(checkout=repo,out=out)
setwd(repo);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({store<-brohn_open_store(file.path(config$out,"workspace"));checks<-list();passed<-FALSE;failure<-NULL
 on.exit({brohn_write_json_file(list(passed=passed,checks=checks,failure=failure),file.path(config$out,"results.json"));brohn_close_store(store)},add=TRUE)
 check<-function(x,label){if(!isTRUE(x))stop(label);checks[[length(checks)+1L]]<<-label;cat("PASS",label,"\n")}
 rows<-function(t)DBI::dbGetQuery(store$con,paste("SELECT * FROM",t,"ORDER BY rowid"))
 tables<-c("jobs","entities","entity_versions","objects");before<-lapply(tables,rows)
 tryCatch({
  source<-brohn_eda_read_json_file(file.path(config$out,"continuous-report.json"),16*1024^2);ref<-.brohn_rpk_ref(source)
  prepared<-brohn_read_json_file(file.path(config$out,"original-results.json"))$prepared$continuous$display_ref
  metadata<-.brohn_rpk_source_metadata(store,list(ref),source_admission=.brohn_edd_admission,eda_refs=list(prepared))
  binding<-metadata$reports[[1L]]$eda_source_closure
  display<-.brohn_edd_metadata(store,prepared)
  hashes<-list(original_csv=binding$dataset$source$hash,processed_stream=source$body$analysis$artifacts[[1L]]$hash,
    original_worker_envelope=source$body$result_object$hash,original_ingestion_envelope=binding$ingestion$object$hash,
    prepared_artifact=display$object$hash,prepared_publication_document=display$document$hash)
  env<-environment(brohn_eda_read_json_file);reader<-get("brohn_eda_read_json_file",env);reads<-0L
  for(name in names(hashes)){
   path<-brohn_object_path(store,hashes[[name]],TRUE);bytes<-readBin(path,"raw",n=file.info(path)$size);bad<-bytes;bad[[1L]]<-as.raw(bitwXor(as.integer(bad[[1L]]),1L));reads<-0L
   original_mode<-file.info(path)$mode
   refused<-tryCatch({Sys.chmod(path,"0666");writeBin(bad,path);assign("brohn_eda_read_json_file",function(...){reads<<-reads+1L;stop("Unexpected decode before original byte identity")},env)
     inherits(try(brohn_open_eda_display_resources(store,prepared,ref$project_id),silent=TRUE),"try-error")
   },finally={assign("brohn_eda_read_json_file",reader,env);writeBin(bytes,path);Sys.chmod(path,original_mode)})
   check(refused&&reads==0L&&identical(digest::digest(file=path,algo="sha256"),hashes[[name]]),paste(name,"same-length corruption refuses before decode and exact original bytes restore"))
  }
  for(id in c(source$body$processing$job_id,brohn_get_entity(store,"ingestion",binding$ingestion$ref$id,binding$ingestion$ref$revision)$body$processing$job_id)){
   DBI::dbBegin(store$con);denied<-tryCatch({stopifnot(DBI::dbExecute(store$con,"UPDATE jobs SET result_json=json_set(result_json,'$.output_hash',?) WHERE id=?",params=list(paste(rep("0",64),collapse=""),id))==1L);inherits(try(.brohn_edd_context(store,ref),silent=TRUE),"try-error")},finally=DBI::dbRollback(store$con))
   check(denied,"wrong original successful producer output hash refuses at metadata source proof")
  }
  opened<-brohn_open_eda_display_resources(store,prepared,ref$project_id);brohn_eda_display_resources_current(store,opened$handle);brohn_release_eda_display_resources(opened$handle)
  check(TRUE,"exact original source reopens after negative fixtures restore")
  check(identical(before,lapply(tables,rows)),"all original tables unchanged; no job or artifact publication")
  for(hash in before[[4L]]$hash)brohn_object_path(store,hash,TRUE)
  check(TRUE,"all original objects byte-exact after every restored corruption fixture")
  passed<-TRUE
 },error=function(e){failure<<-conditionMessage(e);stop(e)})
})
