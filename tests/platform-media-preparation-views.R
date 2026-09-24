# Deferred UI tickets never queue a closed or subsequently changed selection.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==1L);folder<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-media-review-browser-"))
local({store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  r<-brohn_list_entities(store,"audio_review")[[1L]];c<-Filter(function(x)x$body$request$operation=="media_tracks",brohn_list_entities(store,"media_review"))[[1L]]
  jobs_before<-brohn_hash(brohn_list_jobs(store));checks<-character();check<-function(name,x){stopifnot(isTRUE(x));checks<<-c(checks,name);cat("PASS",name,"\n")}
  shiny::testServer(function(input,output,session){state<-shiny::reactiveValues(page="report",report_id=r$body$report_id)
    api<-brohn_install_media_review(input,output,session,store,state,function(fn)fn(),function(...)NULL,function()NULL,function(fn)fn())
  },{
    session$flushReact();callbacks<-list();unlockBinding("onFlushed",session)
    session$onFlushed<-function(fun,once=FALSE){callbacks[[length(callbacks)+1L]]<<-fun;invisible(function(){})};lockBinding("onFlushed",session)
    e<-environment(api$open)
    setup<-function(){shiny::isolate(api$open(.brohn_mr_ref(r),function()r));shiny::isolate(e$catalog(c));session$setInputs(media_review_track="0",media_review_seconds="1.0125");callbacks<<-list()}
    setup();shiny::isolate(e$begin("media_review"));ticket<-shiny::isolate(e$preparing())
    check("Deferred source preparation exposes a pinned source and exact cursor before work",identical(ticket$reference,.brohn_mr_ref(r))&&ticket$form$cursor_sample==8100&&length(callbacks)==1L)
    session$setInputs(media_review_seconds="1.25");callbacks[[1L]]()
    check("Changed cursor before callback is refused without queueing",grepl("selection changed",shiny::isolate(e$issue()),fixed=TRUE)&&is.null(shiny::isolate(e$pending())))
    setup();shiny::isolate(e$begin("media_review"));shiny::isolate(e$close());callbacks[[1L]]()
    check("Closed review abandons deferred preparation",is.null(shiny::isolate(e$preparing()))&&is.null(shiny::isolate(e$pending())))
    setup();shiny::isolate(e$begin("media_review"));state$page<-"datasets";callbacks[[1L]]()
    check("Leaving the report abandons deferred preparation",is.null(shiny::isolate(e$preparing()))&&is.null(shiny::isolate(e$pending())))
    state$page<-"report";session$flushReact();setup();j<-Filter(function(x)identical(x$operation,"media_review")&&identical(x$status,"cancelled"),brohn_list_jobs(store))[[1L]]
    shiny::isolate(e$pending(list(id=j$id,operation=j$operation)))
    poll_time<-system.time(polled<-shiny::isolate(e$pending_job()))[["elapsed"]]
    check("Progress status resolves the exact pending job through bounded catalog metadata",identical(polled$id,j$id)&&identical(polled$status,"cancelled"))
    DBI::dbBegin(store$con);revoked<-FALSE
    tryCatch({DBI::dbExecute(store$con,"UPDATE entities SET project_id='media-poll-revoked' WHERE kind='audio_review' AND id=?",params=list(r$id))
      revoked<-inherits(try(shiny::isolate(e$pending_job()),silent=TRUE),"try-error")},finally=DBI::dbRollback(store$con))
    check("Pending progress refuses freshly revoked audio-window ownership",revoked)
    cat("Bounded pending lookup seconds:",poll_time,"\n")
  })
  check("Every preparation race preserves all preexisting job identities and states",identical(brohn_hash(brohn_list_jobs(store)),jobs_before))
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),view_sha256=digest::digest(file="R/platform-media-review-views.R",algo="sha256")),file.path(folder,"preparation-view-checks.json"))
})
