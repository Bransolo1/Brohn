source("R/platform-load.R",encoding="UTF-8");brohn_load()
local({
  folder<-Sys.getenv("BROHN_INTERVAL_FIXTURE")
  if(!nzchar(folder)){
    parent<-Sys.getenv("BROHN_TEST_EVIDENCE","../../work/test-runs");dir.create(parent,recursive=TRUE,showWarnings=FALSE)
    folder<-tempfile("brohn-intervals-component-",tmpdir=parent);dir.create(folder);folder<-normalizePath(folder,winslash="/")
    processx::run(brohn_rscript(),c("tests/fixtures/researcher-intervals.R","setup",folder),windows_hide_window=TRUE)
  }
  config<-brohn_read_json_file(file.path(folder,"fixture.json"))
  store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store));checks<-0L
  check<-function(ok,label){if(!isTRUE(ok))stop(label);checks<<-checks+1L;cat("PASS",label,"\n")}
  run<-function(job){force(job);claimed<-brohn_claim_job(store,"interval-component",90);stopifnot(identical(claimed$id,job$id));brohn_process_job(store,claimed,timeout_seconds=90)
    j<-brohn_get_job(store,job$id);stopifnot(j$status=="succeeded");brohn_get_entity(store,"signal_view",j$result$signal_view_id)}
  c<-run(brohn_queue_signal_view(store,config$report_id,"physiology-series"));r<-brohn_get_entity(store,"report",config$report_id)
  server<-function(input,output,session){state<-shiny::reactiveValues(page="report",report_id=r$id,error=NULL)
    attempt<-function(fn,...){state$error<-NULL;tryCatch(fn(),error=function(e){state$error<-conditionMessage(e);NULL})}
    controller<-brohn_install_signal_annotations_ui(input,output,session,store,state,attempt,function(x)NULL,function(fn)fn(),
      shiny::reactive(r),shiny::reactive(c),shiny::reactive(c$body$view$tables[[1L]]))
  }
  shiny::testServer(server,{
    identity<-paste(r$id,c$id,c$body$view$tables[[1]]$table_id,sep=":")
    session$setInputs(interval_source_identity="stale",interval_set_title="Original intervals",create_interval_set=1L)
    check(!is.null(state$error)&&is.null(controller$active()),"Wrong source form cannot create annotations")
    session$setInputs(interval_source_identity=identity,create_interval_set=2L)
    check(is.null(state$error)&&controller$active()$revision==1L,"Exact source creates versioned annotations")
    a<-controller$active();session$setInputs(interval_form_identity=.brohn_interval_identity(a),interval_label="Before <b>source</b>",interval_category="baseline",interval_start=3,interval_end=1,interval_note="",save_signal_interval=1L)
    check(!is.null(state$error)&&controller$active()$revision==1L,"Invalid bounds leave saved intervals unchanged")
    session$setInputs(interval_start=0,interval_end=3,save_signal_interval=2L)
    check(is.null(state$error)&&controller$active()$revision==2L&&grepl("&lt;b&gt;",output$signal_annotation_editor$html,fixed=TRUE),"Valid intervals save and escape researcher text")
    a<-controller$active();old<-.brohn_interval_identity(a);id<-a$body$intervals[[1]]$id
    session$setInputs(interval_form_identity=old,interval_label="During",interval_start=3,interval_end=6,save_signal_interval=3L)
    check(controller$active()$revision==3L,"A second interval produces another revision")
    session$setInputs(signal_interval_command=list(identity=old,action="remove",id=id))
    check(!is.null(state$error)&&length(controller$active()$body$intervals)==2,"Delayed remove cannot act on a later version")
    a<-controller$active();session$setInputs(signal_interval_command=list(identity=.brohn_interval_identity(a),action="remove",id=id))
    check(length(controller$active()$body$intervals)==1&&controller$active()$revision==4L,"Current removal preserves historical version")
    a<-controller$active();session$setInputs(interval_form_identity=.brohn_interval_identity(a),interval_restore_revision=3,preview_interval_revision=1L)
    check(controller$history()$revision==3&&length(controller$history()$body$intervals)==2,"Earlier interval version can be reviewed without changes")
    session$setInputs(restore_signal_intervals=list(identity=.brohn_interval_identity(a),revision=3L,hash=brohn_hash(controller$history()$body)))
    check(controller$active()$revision==5L&&length(controller$active()$body$intervals)==2,"Restore is a new version retaining both original intervals")
    a<-controller$active();session$setInputs(interval_form_identity=.brohn_interval_identity(a),interval_measures="invented",summarize_signal_intervals=1L)
    check(!is.null(state$error)&&is.null(controller$job_id()),"Unknown measure cannot reach worker queue")
    session$setInputs(interval_measures="measure",summarize_signal_intervals=2L)
    first<-controller$job_id();j<-brohn_get_job(store,first);check(j$status=="queued"&&j$request$annotation_revision==5L,"Summary queues exact current source and annotation version")
    brohn_cancel_job(store,first);session$setInputs(summarize_signal_intervals=3L);retry<-brohn_get_job(store,controller$job_id())
    check(retry$id!=first&&retry$status=="queued"&&identical(retry$request,j$request),"Cancelled calculation retries as a new exact-input job")
    brohn_cancel_job(store,retry$id);state$page<-"home";session$flushReact()
    check(is.null(controller$active())&&is.null(controller$summary())&&is.null(controller$history()),"Leaving report clears source-bound editor and history")
  })
  summary<-list(summaries=list(list(measure="measure",label="Known before",mean=4,standard_deviation_sample=2,unit="uS",eligible_rows=3),
    list(measure="measure",label="Known during",mean=10,standard_deviation_sample=2,unit="uS",eligible_rows=3)))
  svg<-as.character(brohn_signal_windows_svg(summary,"measure"));check(grepl("not confidence intervals",svg,fixed=TRUE)&&grepl("n = 3",svg,fixed=TRUE),"Chart describes sample SD and source denominator")
  summary$summaries[[1]]$mean<-NULL;summary$summaries[[2]]$mean<-NULL
  check(is.null(brohn_signal_windows_svg(summary,"measure")),"Empty means do not create a zero-valued chart")
  cat("Signal interval views:",checks,"checks passed\n")
})
