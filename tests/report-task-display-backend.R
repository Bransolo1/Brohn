args<-commandArgs(TRUE);stopifnot(length(args)==1L)
config<-jsonlite::fromJSON(args[[1L]],simplifyVector=FALSE);setwd(config$checkout)
Sys.setenv(BROHN_PUBLICATION_NATIVE_MANIFEST=config$native_manifest)
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
  out<-config$out;checks<-list();passed<-FALSE;failure<-NULL;fixtures<-list()
  store<-brohn_open_store(file.path(out,"workspace"))
  check<-function(name,x){if(!isTRUE(x))stop(name,call.=FALSE);checks[[length(checks)+1L]]<<-name;cat("PASS",name,"\n")}
  reject<-function(x)inherits(try(force(x),silent=TRUE),"try-error")
  ref<-function(r)list(kind=r$kind,id=r$id,revision=r$revision,body_hash=brohn_hash(r$body),project_id=r$project_id)
  before<-DBI::dbGetQuery(store$con,"SELECT hash,size FROM objects ORDER BY hash")
  jobs_before<-brohn_list_jobs(store,limit=100L)
  on.exit({
    for(j in brohn_list_jobs(store,limit=100L))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id)
    brohn_write_json_file(list(passed=passed,checks=checks,failure=failure,fixtures=fixtures,
      jobs=lapply(brohn_list_jobs(store,limit=100L),function(j)list(id=j$id,operation=j$operation,status=j$status,error=j$error,result=j$result)),
      scope="Real copied-source task display queue, supervised original snapshot and child, native seals and atomic publication. Source scientific jobs were completed in corpus04 before this boundary; no browser/physical/hosted qualification."),file.path(out,"results.json"))
    brohn_close_store(store)
  },add=TRUE)
  tryCatch({
    # Captured source identity stays stable when disk changes; execution refuses.
    implementation<-brohn_task_display_implementation();target<-"R/platform-task-display.R";original<-readBin(target,"raw",n=file.info(target)$size)
    writeBin(c(original,charToRaw("\n# qualification-only disk drift\n")),target)
    check("loaded identity does not claim subsequently changed disk code",.brohn_td_same(implementation,brohn_task_display_implementation()))
    check("supervised execution rejects disk drift",reject(.brohn_td_check_code(implementation)))
    writeBin(original,target);check("restored exact source execution identity passes",isTRUE(.brohn_td_check_code(implementation)))
    records<-unlist(lapply(config$corpora,function(n)list.files(file.path(config$packet,paste0("corpus-",n)),pattern="-report[.]json$",recursive=TRUE,full.names=TRUE)),use.names=FALSE)
    for(file in records){
      source<-brohn_read_json_file(file);r<-ref(source);key<-paste(basename(dirname(file)),sub("[.]json$","",basename(file)),sep="-")
      choice<-brohn_report_package_report_choice(store,r)
      check(paste("exact complete source has task adapter",key),length(choice$adapters)>0L&&!is.null(choice$source_family))
      queued<-brohn_queue_task_display(store,r)
      check(paste("same exact request reuses queued preparation",key),identical(queued$id,brohn_queue_task_display(store,r)$id))
      claim<-brohn_claim_job(store,"task-display-backend",lease_seconds=120L);stopifnot(identical(claim$id,queued$id))
      brohn_process_job(store,claim,timeout_seconds=180)
      done<-brohn_get_job(store,claim$id);if(done$status!="succeeded")stop(key,": ",brohn_json(done$error))
      saved<-brohn_get_entity(store,"task_display",done$result$task_display_id);dref<-ref(saved)
      check(paste("genuine supervised display publishes exact source",key),.brohn_td_same(saved$body$source$report_ref,r))
      open<-brohn_open_task_display_resources(store,dref,r$project_id)
      check(paste("current saved resources retain exact source",key),is.list(brohn_task_display_resources_current(store,open$handle)))
      # Exact full fixture is consumed independently by pure rendering/oracles.
      brohn_write_json_file(list(report=list(ref=r,saved_body=source$body,complete_analysis=brohn_complete_questionnaire_report(store,source$body)$analysis),task_display=list(ref=dref,body=saved$body,evidence=open$evidence)),file.path(out,paste0(key,".json")))
      brohn_release_task_display_resources(open$handle);brohn_release_task_display_resources(open$handle)
      check(paste("closed handle refuses with idempotent release",key),reject(brohn_task_display_resources_current(store,open$handle)))
      check(paste("bounded exact finder returns successful preparation",key),.brohn_td_same(brohn_find_task_display(store,r),dref))
      fixtures[[key]]<-list(report_ref=r,task_display_ref=dref,artifact=saved$body$artifact)
    }
    check("all original corpus objects remain byte identical",all(vapply(before$hash,function(h)identical(digest::digest(file=brohn_object_path(store,h,FALSE),algo="sha256"),h),logical(1))))
    jobs<-brohn_list_jobs(store,limit=100L);new<-Filter(function(j)!j$id %in% vapply(jobs_before,`[[`,character(1),"id"),jobs)
    check("only display jobs were added after original science boundary",length(new)==length(records)&&all(vapply(new,function(j)j$operation=="task_display"&&j$status=="succeeded",logical(1))))
    passed<-TRUE
  },error=function(e){failure<<-conditionMessage(e);stop(e)})
  cat(length(checks),"backend checks passed\n")
})
