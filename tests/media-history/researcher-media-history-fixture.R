# Prepared externally. Do not execute populate/researcher during another freeze.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L);mode<-args[[1L]]
folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-media-history-browser-"),file.exists(file.path(folder,"copy-receipt.json")))
runtime<-jsonlite::fromJSON(file.path(folder,"runtime.json"),simplifyVector=FALSE)
setwd(normalizePath(runtime$app_root,winslash="/",mustWork=TRUE))
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
baseline<-brohn_read_json_file(file.path(folder,"copy-receipt.json"))$baseline_receipt
cp<-file.path(folder,"fixture.json")
if(mode=="researcher"){
  stopifnot(exists("brohn_media_history_page",mode="function"),file.exists(cp))
  config<-brohn_read_json_file(cp);Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform",BROHN_PARTICIPANT_PORT=config$participant_port)
  stop_owned<-function()if(file.exists(file.path(folder,"stop.researcher")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$researcher_port,launch.browser=FALSE)
}else local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  jobs<-function(){x<-brohn_list_jobs(store,limit=1000L);x[order(vapply(x,`[[`,character(1),"id"))]}
  versions<-function()DBI::dbGetQuery(store$con,"SELECT kind,id,revision,body_hash FROM entity_versions ORDER BY kind,id,revision")
  refs<-function(){regular<-brohn_get_entity(store,"media_review",baseline$regular$media);gap<-brohn_get_entity(store,"media_review",baseline$gap$media)
    describe<-function(media){audio<-brohn_get_entity(store,"audio_review",media$body$audio_review_id);report<-brohn_get_entity(store,"report",media$body$report_id)
      list(media=media,audio=audio,report=report,dataset_id=report$body$dataset_id)}
    list(regular=describe(regular),gap=describe(gap))}
  if(mode=="setup"){
    stopifnot(!file.exists(cp),exists("brohn_media_history_page",mode="function"))
    original<-refs();old_jobs<-jobs();stopifnot(all(vapply(old_jobs,function(j)j$status%in%c("succeeded","cancelled"),logical(1))))
    for(kind in c("regular","gap"))stopifnot(identical(original[[kind]]$audio$id,baseline[[kind]]$audio),identical(original[[kind]]$report$id,baseline[[kind]]$report),identical(original[[kind]]$media$body$request$dataset$id,baseline[[kind]]$parent))
    brohn_write_json_file(list(workspace=store$root,researcher_port=runtime$researcher_port,participant_port=runtime$participant_port,original=original,
      inherited_jobs=old_jobs,original_versions=lapply(seq_len(nrow(versions())),function(i)as.list(versions()[i,,drop=FALSE])),planned_source_samples=as.list(seq.int(10010L,10420L,by=10L))),cp)
  }else if(mode=="populate"){
    stopifnot(exists("brohn_media_history_page",mode="function"));config<-brohn_read_json_file(cp);r<-config$original$regular$audio
    inventory<-brohn_media_history_inventory(store,.brohn_mr_ref(r),r$body$request$report,r$project_id)
    stopifnot(!is.null(inventory))
    added<-list()
    for(sample in unlist(config$planned_source_samples)){
      queued<-brohn_queue_media_review(store,r$id,r$revision,.brohn_sv_hash(r$body),r$project_id,"media_review",inventory,0L,as.integer(sample))
      if(identical(queued$status,"queued")){
        child<-brohn_claim_job(store,"media-history-preparation",120);stopifnot(identical(child$id,queued$id));brohn_process_job(store,child,timeout_seconds=300)
      }
      done<-brohn_get_job(store,queued$id);cat(brohn_json(done[c("id","operation","status","attempt","error")]),"\n")
      cat(brohn_json(done[c("id","operation","status","attempt","error")]),"\n",file=file.path(folder,"population-jobs.jsonl"),append=TRUE)
      stopifnot(identical(done$status,"succeeded"));saved<-brohn_media_review_record(store,done$result$media_review_id,r$id,r$project_id,FALSE)
      stopifnot(saved$body$result$mapping$selected_sample==sample);added[[length(added)+1L]]<-done
    }
    all<-jobs();by_id<-setNames(all,vapply(all,`[[`,character(1),"id"))
    for(old in config$inherited_jobs)stopifnot(.brohn_mr_same(by_id[[old$id]],old))
    current<-versions();key<-function(row)paste(row$kind,row$id,row$revision,sep="/");index<-setNames(current$body_hash,apply(current,1L,function(x)paste(x[["kind"]],x[["id"]],x[["revision"]],sep="/")))
    for(v in config$original_versions)stopifnot(identical(unname(index[[key(v)]]),v$body_hash))
    page<-brohn_media_history_page(store,.brohn_mr_ref(r),r$body$request$report,r$project_id)
    stopifnot(page$total>40L,length(added)==42L,all(vapply(added,function(j)j$operation=="media_review",logical(1))))
    brohn_write_json_file(list(passed=TRUE,inherited_jobs=length(config$inherited_jobs),new_media_jobs=added,new_scientific_jobs=0L,saved_review_count=page$total,
      scope="Genuine supervised exact media cursor preparations on copied original sources; acoustic reports and all inherited records preserved."),file.path(folder,"population-results.json"))
  }else if(mode=="inspect"){
    r<-refs();reviews<-brohn_list_entities(store,"media_review",limit=1000L)
    reports<-brohn_list_entities(store,"report",limit=1000L);reports<-reports[order(vapply(reports,`[[`,character(1),"id"))]
    brohn_write_json_file(c(r,list(media_reviews=reviews,reports=reports,jobs=jobs())),file.path(folder,"snapshot.json"))
  }else stop("Unknown media-history fixture mode")
})
