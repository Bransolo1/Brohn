# Original synthetic durable-journal recovery fixture; no scoring workers.
args<-commandArgs(trailingOnly=TRUE)
argument<-function(name){i<-match(name,args);stopifnot(!is.na(i));args[[i+1L]]}
mode<-args[[1L]];folder<-normalizePath(argument("--folder"),winslash="/",mustWork=TRUE)
stopifnot(grepl("^brohn-preferred-delivery-",basename(folder)))
if(mode=="serve"){
  check_stop<-function(){if(file.exists(file.path(folder,"stop.request")))httpuv::interrupt()else later::later(check_stop,.2)}
  later::later(check_stop,.2);source("scripts/run-participant.R",encoding="UTF-8")
}else{
  source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
  store<-brohn_open_store(argument("--root"))
  local({
    on.exit(brohn_close_store(store),add=TRUE)
    if(mode=="prepare"){
      baseline<-normalizePath(argument("--baseline"),winslash="/",mustWork=TRUE)
      receipt<-brohn_read_json_file(file.path(baseline,"results.json"));stopifnot(isTRUE(receipt$passed))
      original<-jsonlite::fromJSON(brohn_read_json_file(file.path(baseline,"start-transport.json"))$body,simplifyVector=FALSE)
      design<-original$protocol$design;brohn_put_entity(store,"study",design$id,design)
      releases<-setNames(lapply(c("preferred","persisted"),function(x)brohn_publish(store,design$id,origin="sample",quota=1L)),c("preferred","persisted"))
      source_path<-file.path(baseline,"large-journal.json");events<-brohn_read_json_file(source_path)
      stopifnot(length(events)==394L,identical(brohn_hash(events),receipt$events_hash))
      brohn_write_json_file(list(releases=releases,source_path=source_path,source_sha256=digest::digest(file=source_path,algo="sha256"),
        events_hash=brohn_hash(events),timeline_hash=brohn_hash(original$protocol$timeline),
        original_batch_path=file.path(baseline,"batch-01.json"),design_hash=brohn_hash(design)),file.path(folder,"fixture.json"))
    }else if(mode %in% c("inspect","cancel")){
      config<-brohn_read_json_file(file.path(folder,"fixture.json"));expected<-brohn_read_json_file(config$source_path)
      stopifnot(identical(digest::digest(file=config$source_path,algo="sha256"),config$source_sha256))
      if(mode=="cancel")for(job in brohn_list_jobs(store,limit=100L))if(job$status=="queued")brohn_cancel_job(store,job$id)
      rows<-lapply(brohn_runs(store),function(run){
        events<-brohn_run_events(store,run$id)
        list(id=run$id,completion=run$completion_status,transfer=run$transfer_status,acked_sequence=run$acked_sequence,
          events=events,events_hash=brohn_hash(events),source_equal=identical(brohn_hash(events),config$events_hash),
          timeline_equal=identical(brohn_hash(run$protocol$timeline),config$timeline_hash),
          design_equal=identical(brohn_hash(run$protocol$design),config$design_hash),
          jobs=lapply(brohn_list_jobs(store,100L,list(run_id=run$id)),function(j)list(id=j$id,status=j$status,attempt=j$attempt,operation=j$operation)),
          receipt_count=DBI::dbGetQuery(store$con,"SELECT count(*) AS n FROM delivery_receipts WHERE scope=?",params=list(run$id))$n[[1L]])
      })
      brohn_write_json_file(list(runs=rows,source_unchanged=TRUE),file.path(folder,"inspection.json"))
    }else stop("Unknown preferred-delivery fixture mode.")
  })
}
