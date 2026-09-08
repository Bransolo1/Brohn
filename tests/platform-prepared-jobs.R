source("R/platform-store.R")
local({
  root<-tempfile("brohn-prepared-jobs-");dir.create(root);root<-normalizePath(root,winslash="/")
  store<-brohn_open_store(file.path(root,"workspace"));children<-list();checks<-0L
  on.exit({
    for(child in children)if(child$is_alive())child$kill_tree()
    brohn_close_store(store)
    stopifnot(identical(dirname(root),normalizePath(tempdir(),winslash="/")),startsWith(basename(root),"brohn-prepared-jobs-"))
    unlink(root,recursive=TRUE,force=TRUE)
  },add=TRUE)
  check<-function(name,value){if(!isTRUE(value))stop("Prepared job QA: ",name);checks<<-checks+1L}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  id<-.brohn_store_id(store$con,"job");a<-brohn_enqueue_job(store,"fixture",list(value=0),"one",prepared_id=id)
  check("prepared internal identity is preserved",identical(a$id,id))
  check("normal caller remains backward compatible",identical(brohn_enqueue_job(store,"fixture",list(value=0),"one")$id,id))
  other<-.brohn_store_id(store$con,"job")
  check("exact idempotency returns existing job despite proposed new identity",identical(brohn_enqueue_job(store,"fixture",list(value=0),"one",prepared_id=other)$id,id))
  check("same key with changed request remains conflict",rejects(brohn_enqueue_job(store,"fixture",list(value=1),"one",prepared_id=other)))
  check("prepared identity collision cannot create another operation",rejects(brohn_enqueue_job(store,"fixture",list(value=0),"different-key",prepared_id=id))&&length(brohn_list_jobs(store))==1L)
  check("arbitrary or malformed prepared IDs are rejected",rejects(brohn_enqueue_job(store,"fixture",list(value=0),"bad",prepared_id="../../job")))
  barrier<-file.path(root,"race-start")
  for(i in 1:2) {
    request<-list(workspace=store$root,ready=file.path(root,paste0("ready-",i)),start=barrier,key="original-race-key",
      id=.brohn_store_id(store$con,"job"),entity=paste0("race-",i),output=file.path(root,paste0("result-",i)))
    path<-file.path(root,paste0("request-",i,".rds"));saveRDS(request,path)
    children[[i]]<-processx::process$new(file.path(R.home("bin"),"Rscript.exe"),c("--vanilla","tests/fixtures/platform-prepared-job-child.R",path),
      env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
  }
  deadline<-as.numeric(Sys.time())+15
  while(!all(file.exists(file.path(root,paste0("ready-",1:2))))){if(as.numeric(Sys.time())>deadline)stop("Original child readiness timed out.");Sys.sleep(.01)}
  writeLines("start",barrier)
  for(child in children){child$wait(10000);if(!identical(child$get_exit_status(),0L))stop(child$read_all_error())}
  results<-lapply(1:2,function(i)readRDS(file.path(root,paste0("result-",i))))
  check("concurrent prepared IDs choose one actual idempotent job",sum(vapply(results,is.character,logical(1)))==1L&&length(brohn_list_jobs(store))==2L)
  saved<-brohn_list_entities(store,"prepared_fixture")
  check("losing prebuilt export is rolled back atomically",length(saved)==1L&&identical(saved[[1]]$body$job_id,Filter(is.character,results)[[1]]))
  check("failed race leaves no dangling prepared linkage",!is.null(brohn_get_job(store,saved[[1]]$body$job_id))&&identical(DBI::dbGetQuery(store$con,"PRAGMA integrity_check")[[1]],"ok"))
  cat("Prepared dependent job identities:",checks,"checks passed.\n")
})
