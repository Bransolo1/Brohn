# External original-fixture history qualification. No real workspace is opened.
args <- commandArgs(TRUE); stopifnot(length(args) == 2L)
mode <- args[[1L]]; folder <- normalizePath(args[[2L]], winslash="/", mustWork=TRUE)
stopifnot(identical(normalizePath(Sys.getenv("BROHN_WORKSPACE"),winslash="/",mustWork=TRUE),paste0(folder,"/workspace")))
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
if(mode=="serve") {
  poll<-function(){if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(poll,.1)}
  later::later(poll,.1);source("scripts/run-brohn.R",encoding="UTF-8")
  s<-getOption("brohn.services");stopifnot(isTRUE(s$stopped),all(vapply(s$owned,function(p)!p$is_alive(),logical(1))))
  cat("linked_history_owned_shutdown: TRUE\n")
} else local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  cfg<-if(file.exists(file.path(folder,"fixture.json")))brohn_read_json_file(file.path(folder,"fixture.json"))else NULL
  snap<-function()list(datasets=brohn_list_entities(store,"dataset"),imports=brohn_list_entities(store,"stream_import"),
    streams=brohn_list_entities(store,"stream"),jobs=brohn_list_jobs(store,limit=200),
    reviews=lapply(brohn_list_entities(store,"linked_review",limit=200),function(r)list(id=r$id,revision=r$revision,hash=brohn_hash(r$body))))
  if(mode=="setup") {
    stopifnot(is.null(cfg));reviews<-brohn_list_entities(store,"linked_review")
    pick<-function(fn){found<-Filter(fn,reviews);stopifnot(length(found)>0L);found[[1L]]}
    first<-pick(function(r)identical(r$body$result$status,"available")&&r$body$result$selected_rows==78)
    wide<-pick(function(r)r$body$result$selected_rows==158&&r$body$request$selection$offset==100)
    empty<-pick(function(r)identical(r$body$result$status,"empty_window"))
    unsupported<-pick(function(r)identical(r$body$result$status,"requires_alignment"))
    dataset<-brohn_get_entity(store,"dataset",first$body$dataset_id)
    cfg<-list(schema="brohn-linked-history-browser/1.0",origin="original_synthetic",dataset=dataset,
      first=first,wide=wide,empty=empty,unsupported=unsupported,original_count=length(reviews))
    brohn_write_json_file(snap(),file.path(folder,"before.json"))
    stamp<-.brohn_store_stamp;on.exit(assign(".brohn_store_stamp",stamp,envir=.GlobalEnv),add=TRUE)
    assign(".brohn_store_stamp",function()"2030-01-01T00:00:00.000000Z",envir=.GlobalEnv)
    for(i in 1:65){body<-first$body;body$id<-sprintf("qa-linked-history-%03d",i);body$created_at<-"2030-01-01T00:00:00.000000Z"
      brohn_put_entity(store,"linked_review",body$id,body,project_id=first$project_id)}
    assign(".brohn_store_stamp",stamp,envir=.GlobalEnv)
    brohn_write_json_file(cfg,file.path(folder,"fixture.json"))
  } else if(mode=="inspect")brohn_write_json_file(snap(),file.path(folder,"snapshot.json"))
  else if(mode=="queue-import") {
    stopifnot(!file.exists(file.path(folder,"second-import-job.json")))
    # Real existing validated importer API; QA triggers arrival from another
    # connection while the browser keeps an unsaved source-bound draft.
    job<-brohn_queue_multistream(store,cfg$dataset$id,force=TRUE)
    brohn_write_json_file(list(id=job$id,operation=job$operation,request=job$request),file.path(folder,"second-import-job.json"))
  } else stop("Unknown history fixture operation")
})
