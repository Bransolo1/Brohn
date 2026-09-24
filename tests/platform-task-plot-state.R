source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
local({
  args<-commandArgs(TRUE);folder<-if(length(args))args[[1L]]else tempfile("brohn-task-plot-state-")
  stopifnot(!dir.exists(folder));dir.create(folder,recursive=TRUE)
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  source("tests/fixtures/original-task-journal.R",encoding="UTF-8")
  # One small complete synthetic receiver journal. Direct fixture analysis is
  # explicitly separate from a supervised worker or a participant experiment.
  study<-brohn_create_study(store,"Original task preparation test","blank");d<-study$body
  d$blocks<-list(brohn_task_new("rt-deary-liewald-choice/1.0",id="task-preparation-fixture"));study<-brohn_save_study(store,d,study$revision)
  release<-brohn_publish(store,study$id,"sample",alias_required=TRUE)
  start<-.brohn_delivery_start(store,release$token,list(consented=TRUE,participant_alias="001",client_id="task-prepare-client",operation_id="task-prepare-start"))
  protocol<-brohn_run(store,start$run_id)$protocol;events<-original_task_journal(protocol)
  .brohn_delivery_receive(store,start$run_id,start$access_token,list(events=events,operation_id="task-prepare-events"))
  .brohn_delivery_finish(store,start$run_id,start$access_token,list(outcome="completed",final_sequence=length(events),operation_id="task-prepare-finish"))
  for(j in brohn_list_jobs(store))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id)
  run<-brohn_run(store,start$run_id)
  body<-brohn_analyse_runs(list(design=run$protocol$design,runs=list(run),events=stats::setNames(list(events),run$id)))
  body$id<-brohn_id("report");body$schema_version<-"brohn-report/1.0.0";body$status<-"Available";body$created_at<-brohn_now()
  body$result_object<-brohn_store_object(store,bytes=charToRaw(enc2utf8(brohn_json(list(schema="brohn-analysis-output/1.0",report=body)))),media_type="application/json")
  r<-brohn_put_entity(store,"report",body$id,body,project_id=study$project_id)
  inventory<-function()lapply(DBI::dbListTables(store$con),function(t)digest::digest(DBI::dbReadTable(store$con,t),algo="sha256"))
  before<-inventory();checks<-character();reads<-0L;catalogs<-0L
  check<-function(ok,label){if(!isTRUE(ok))stop(label,call.=FALSE);checks<<-c(checks,label);cat("PASS",label,"\n")}
  original_load<-brohn_task_plot_load;original_catalog<-brohn_task_plot_report;original_score<-brohn_task_score
  assign("brohn_task_plot_load",function(...){reads<<-reads+1L;original_load(...)},envir=.GlobalEnv)
  assign("brohn_task_plot_report",function(...){catalogs<<-catalogs+1L;original_catalog(...)},envir=.GlobalEnv)
  assign("brohn_task_score",function(...)stop("Unexpected scoring"),envir=.GlobalEnv)
  on.exit({assign("brohn_task_plot_load",original_load,envir=.GlobalEnv);assign("brohn_task_plot_report",original_catalog,envir=.GlobalEnv);assign("brohn_task_score",original_score,envir=.GlobalEnv)},add=TRUE)
  cmd<-list(report_id=r$id,revision=r$revision,report_hash=brohn_hash(r$body),project_id=r$project_id)
  server<-function(input,output,session){state<-shiny::reactiveValues(page="report",report_id=r$id,error=NULL)
    attempt<-function(fn,...)tryCatch(fn(),error=function(e){state$error<-conditionMessage(e);NULL})
    plots<-brohn_install_task_plots(input,output,session,store,state,attempt,function(fn)fn())}
  shiny::testServer(server,{
    session$setInputs(open_task_plots=cmd)
    ticket<-plots$pending()$token
    check(catalogs==0L&&is.null(plots$opened())&&grepl(ticket,output$task_plot_status$html,fixed=TRUE),"Pending catalog status renders before any complete catalog read")
    check(grepl('role="status"',output$task_plot_status$html,fixed=TRUE)&&grepl('aria-live="polite"',output$task_plot_status$html,fixed=TRUE),"Preparation status is explicitly announced")
    check(grepl('tabindex="-1"',output$task_plot_status$html,fixed=TRUE)&&grepl('data-task-plot-ticket=',output$task_plot_status$html,fixed=TRUE),"Current status carries a programmatically focusable exact ticket")
    session$setInputs(task_plot_prepare_ack="obsolete-ticket")
    check(catalogs==0L&&identical(plots$pending()$token,ticket),"Unrelated or stale client acknowledgement cannot begin catalog work")
    session$setInputs(task_plot_prepare_ack=ticket)
    check(catalogs==1L&&!is.null(plots$opened())&&identical(plots$status()$phase,"ready"),"Matching catalog acknowledgement triggers actual fresh authority and marks choices ready")
    check(identical(plots$status()$token,ticket)&&grepl(paste0('data-task-plot-complete="',ticket,'"'),output$task_plot_catalog$html,fixed=TRUE)&&grepl('tabindex="-1"',output$task_plot_catalog$html,fixed=TRUE),"Catalog success exposes the same ticket on its focusable evidence heading")
    check(!grepl('data-task-plot-prepare=',output$task_plot_status$html,fixed=TRUE),"Ready status cannot acknowledge preparation again")
    source_id<-plots$opened()$catalog[[1L]]$id
    session$setInputs(task_plot_catalog_identity=cmd$report_hash,task_plot_source=source_id,task_plot_load=1L)
    first<-plots$pending()$token
    check(reads==0L&&is.null(plots$model())&&grepl("Reading and checking",output$task_plot_status$html,fixed=TRUE),"Source loading is acknowledged in the output before full original journal work")
    session$setInputs(task_plot_source="different-source",task_plot_prepare_ack=first)
    check(reads==0L&&identical(plots$status()$phase,"failed")&&grepl("selected source changed",state$error,fixed=TRUE),"A source change before acknowledgement refuses the stale selection with a clear failure")
    check(identical(plots$status()$token,first)&&grepl(first,output$task_plot_status$html,fixed=TRUE),"Failed current source retains its own completion token for explanation focus")
    session$setInputs(task_plot_source=source_id,task_plot_load=2L)
    second<-plots$pending()$token
    session$setInputs(task_plot_prepare_ack=first)
    check(reads==0L&&identical(plots$pending()$token,second),"Retry ticket cannot be started by the preceding acknowledgement")
    session$setInputs(task_plot_prepare_ack=second)
    m<-plots$model()
    check(reads==1L&&length(m$rows)==48L&&is.null(plots$pending())&&identical(plots$status()$phase,"ready"),"Current source acknowledgement reads all 48 original fixture rows and reaches ready")
    check(identical(plots$status()$token,second)&&grepl(paste0('data-task-plot-complete="',second,'"'),output$task_plot_controls$html,fixed=TRUE),"Source success exposes its exact ticket on the actual plot-controls heading")
    session$setInputs(task_plot_prepare_ack=second)
    check(reads==1L,"Duplicate acknowledgement does not decode the same source again")
    session$setInputs(task_plot_identity=brohn_hash(list(m$report_hash,m$id,m$source_hash)),task_plot_measure="first_response_ms",task_plot_scope="all",task_plot_page=1L)
    check(length(plots$selected()$rows)==48L&&grepl("Page 1",output$task_plot_view$html,fixed=TRUE),"Acknowledged loading retains full source selection and exact numerical page")
    session$setInputs(task_plot_load=3L);abandoned<-plots$pending()$token
    state$page<-"home";session$flushReact();session$setInputs(task_plot_prepare_ack=abandoned)
    check(reads==1L&&is.null(plots$opened())&&is.null(plots$model())&&is.null(plots$pending())&&is.null(plots$status()),"Leaving the report clears waiting work; late acknowledgement cannot reopen it")
    state$page<-"report";session$setInputs(open_task_plots=cmd);foreign<-plots$pending()$token
    DBI::dbExecute(store$con,"UPDATE entities SET project_id='unrelated-project' WHERE kind='report' AND id=?",params=list(r$id))
    session$setInputs(task_plot_prepare_ack=foreign)
    check(is.null(plots$opened())&&identical(plots$status()$phase,"failed")&&grepl("current project",state$error,fixed=TRUE),"Actual project revocation between pending and acknowledgement is rechecked and refused")
    DBI::dbExecute(store$con,"UPDATE entities SET project_id=? WHERE kind='report' AND id=?",params=list(r$project_id,r$id))
    session$setInputs(open_task_plots=cmd);new_ticket<-plots$pending()$token;session$setInputs(task_plot_prepare_ack=new_ticket)
    check(!is.null(plots$opened())&&identical(plots$status()$phase,"ready"),"Restored fixture authority can explicitly reopen the original saved report")
  })
  check(identical(before,inventory()),"State tests preserve every prepared source table and settled fixture job")
  brohn_write_json_file(list(passed=TRUE,scope="Portable Shiny testServer with a complete synthetic 48-trial receiver fixture and actual source read. Client acknowledgements supplied explicitly; no browser or scientific-worker claim.",checks=as.list(checks),actual_source_reads=reads,new_jobs_after_setup=0L,scoring_calls_during_plot=0L),file.path(folder,"results.json"))
  cat("STATE PASS",length(checks),"checks\n")
})
