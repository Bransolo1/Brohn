# Extend the accepted copied-fixture signal authorization test to interval paths.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
fixture<-normalizePath(args[[1]],winslash="/",mustWork=TRUE);folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(fixture),"brohn-signal-audio-lineage-"),startsWith(basename(folder),"brohn-signal-audio-intervals-"),
  isTRUE(brohn_read_json_file(file.path(fixture,"results.json"))$passed),!dir.exists(file.path(folder,"workspace")))
stopifnot(file.copy(file.path(fixture,"workspace"),folder,recursive=TRUE))
checks<-character();check<-function(label,value){if(!isTRUE(value))stop(label,call.=FALSE);checks<<-c(checks,label);cat("PASS",label,"\n")}
rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
tryCatch(local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit({for(j in brohn_list_jobs(store,limit=1000L))if(j$status%in%c("queued","running"))brohn_cancel_job(store,j$id);brohn_close_store(store)},add=TRUE)
  stopifnot(!any(vapply(brohn_list_jobs(store,limit=1000L),function(j)j$status%in%c("queued","running"),logical(1))))
  original<-brohn_list_entities(store,"report",limit=1000L);original_hashes<-lapply(original,function(r)list(id=r$id,hash=brohn_hash(r$body)))
  report<-Filter(function(r)!is.null(r$body$provenance$derived_audio_lineage),original)[[1L]];lineage<-report$body$provenance$derived_audio_lineage
  parent_id<-lineage$binding$parent_dataset$id;parent<-brohn_get_entity(store,"dataset",parent_id)
  catalog<-Filter(function(r)r$body$report_id==report$id&&r$body$operation=="signal_catalog",brohn_list_entities(store,"signal_view",limit=1000L))[[1L]]
  t<-catalog$body$view$tables[[1L]];measure<-t$value_columns[[1L]]$name
  ids<-function(){paths<-c("R/platform-publication.R","scripts/workers/publication.py","src/publication_guard.c","R/platform-signal.R",
    "R/platform-signal-values.R","R/platform-signal-annotations.R","R/platform-signal-annotations-views.R","R/platform-audio-extraction.R")
    setNames(lapply(paths,function(p)digest::digest(file=p,algo="sha256")),paths)}
  run<-function(job){force(job);claim<-brohn_claim_job(store,"audio-interval-auth",180);stopifnot(identical(claim$id,job$id))
    scratch<-file.path(store$root,"scratch",job$id);dir.create(scratch,recursive=TRUE)
    input<-if(job$operation=="signal_catalog")brohn_signal_input(store,claim)else brohn_signal_windows_input(store,claim)
    guards<-brohn_hold_signal_value_sources(store,input);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
    output<-list(report=if(job$operation=="signal_catalog")brohn_analyse_signal(input,scratch)else brohn_analyse_signal_windows(input,scratch),code_identity=ids())
    p<-file.path(scratch,"result.json");brohn_write_json_file(output,p)
    if(job$operation=="signal_catalog")brohn_publish_signal_view(store,output,scratch,claim,input,p)else brohn_publish_signal_windows(store,output,scratch,claim,input,p)
    j<-brohn_get_job(store,job$id);brohn_get_entity(store,if(job$operation=="signal_catalog")"signal_view"else"signal_windows",brohn_default(j$result$signal_view_id,j$result$signal_windows_id))
  }
  a<-brohn_create_signal_annotations(store,catalog$id,t$table_id,"Original derived audio interval")
  a<-brohn_save_signal_interval(store,a$id,a$revision,"First source second","review",0,1,"Original recording-relative interval; no event synchrony claim.")
  job<-brohn_queue_signal_windows(store,a$id,a$revision,brohn_hash(a$body),list(measure));input<-brohn_signal_windows_input(store,job)
  check("Derived interval job retains exact parent lineage and all source refs",.brohn_sv_same(input$derived_audio_lineage,lineage)&&
    all(vapply(lineage$source_refs,`[[`,character(1),"hash")%in%vapply(input$source_objects,`[[`,character(1),"hash")))
  saved<-run(job)
  check("Saved derived interval result preserves its exact annotation/report",saved$body$report_hash==brohn_hash(report$body)&&saved$body$annotation_source$hash==brohn_hash(a$body))
  plain<-brohn_get_entity(store,"report","report-ordinary-signal-auth-fixture")
  plain_catalog<-run(brohn_queue_signal_view(store,plain$id,"physiology-series"));pt<-plain_catalog$body$view$tables[[1L]]
  pa<-brohn_create_signal_annotations(store,plain_catalog$id,pt$table_id,"Ordinary source interval")
  pa<-brohn_save_signal_interval(store,pa$id,pa$revision,"First ordinary second","review",0,1)
  reuse<-function(source,target,table)brohn_preview_signal_interval_reuse(store,source$id,source$revision,brohn_hash(source$body),
    target$id,target$revision,brohn_hash(target$body),table$table_id,"Explicit original anchor mapping",0,0,"Same retained analytic test recording; no independent clock inference.")
  from_derived<-reuse(a,plain_catalog,pt);to_derived<-reuse(pa,catalog,t)
  reused<-brohn_apply_signal_interval_reuse(store,to_derived,brohn_hash(to_derived))
  check("Authorized interval reuse retains target source with declared boundaries",reused$body$report_id==report$id&&reused$body$intervals[[1L]]$start_s==0&&reused$body$intervals[[1L]]$end_s==1)
  move<-function(owner)DBI::dbExecute(store$con,"UPDATE entities SET project_id=? WHERE kind='dataset' AND id=?",params=list(owner,parent_id))
  move("deliberate-interval-foreign")
  check("Revoked parent blocks new annotations and retained annotation reads",rejects(brohn_create_signal_annotations(store,catalog$id,t$table_id,"No access"))&&rejects(brohn_signal_annotations(store,a$id)))
  check("Revoked source or target blocks interval reuse preview and application",rejects(reuse(a,plain_catalog,pt))&&rejects(reuse(pa,catalog,t))&&
    rejects(brohn_apply_signal_interval_reuse(store,from_derived,brohn_hash(from_derived)))&&rejects(brohn_apply_signal_interval_reuse(store,to_derived,brohn_hash(to_derived))))
  check("Revoked parent blocks existing window input and new summary queue",rejects(brohn_signal_windows_input(store,job))&&rejects(brohn_queue_signal_windows(store,a$id,a$revision,brohn_hash(a$body),list(measure))))
  check("Ordinary intervals remain readable while unrelated parent is revoked",identical(brohn_signal_annotations(store,pa$id)$id,pa$id))
  move(parent$project_id)
  # A second interval version supplies a fresh bounded result for commit fencing.
  a2<-brohn_save_signal_interval(store,a$id,a$revision,"Second source second","review",1,2)
  fence<-brohn_queue_signal_windows(store,a2$id,a2$revision,brohn_hash(a2$body),list(measure))
  publisher<-brohn_publish_entity_result;fired<-FALSE;before<-length(brohn_list_entities(store,"signal_windows",limit=1000L))
  assign("brohn_publish_entity_result",function(store,job,input,output,kind,body,publication_path,receipt,before_commit=NULL)
    publisher(store,job,input,output,kind,body,publication_path,receipt,before_commit=function(){fired<<-TRUE;move("deliberate-interval-foreign");if(!is.null(before_commit))before_commit()}),envir=.GlobalEnv)
  blocked<-tryCatch(rejects(run(fence)),finally=assign("brohn_publish_entity_result",publisher,envir=.GlobalEnv))
  check("Interval commit rechecks parent authority and rolls back",blocked&&fired&&length(brohn_list_entities(store,"signal_windows",limit=1000L))==before&&brohn_get_entity(store,"dataset",parent_id)$project_id==parent$project_id)
  brohn_cancel_job(store,fence$id)
  server<-function(input,output,session){
    state<-shiny::reactiveValues(page="report",report_id=report$id,error=NULL,status=NULL)
    attempt<-function(fn)tryCatch(fn(),error=function(e){state$error<-conditionMessage(e);NULL})
    controller<-brohn_install_signal_annotations_ui(input,output,session,store,state,attempt,function(x)state$status<-x,function(fn)fn(),
      shiny::reactive(report),shiny::reactive(catalog),shiny::reactive(t))
  }
  shiny::testServer(server,{
    session$setInputs(signal_table=t$table_id);session$flushReact()
    # Read original accepted interval version even after a later edit exists.
    controller$active(a);session$setInputs(interval_form_identity=.brohn_interval_identity(a),interval_measures=measure,signal_window_plot_measure=measure,summarize_signal_intervals=1L)
    session$flushReact();session$elapse(1200);session$flushReact()
    check("Retained interval comparison opens before revocation",grepl("Saved interval comparison",output$signal_annotation_summary$html,fixed=TRUE)&&identical(controller$summary()$id,saved$id))
    move("deliberate-interval-foreign")
    check("Cached interval JSON CSV and SVG deny revocation before poll",rejects(output$signal_windows_json)&&rejects(output$signal_windows_csv)&&rejects(output$signal_windows_svg))
    session$elapse(1200);session$flushReact()
    check("Interval revocation clears active result without closing session",is.null(controller$active())&&is.null(controller$summary())&&!session$isClosed())
    check("Interval authority issue remains visible",grepl("unavailable|project|source",output$signal_annotation_progress$html))
    move(parent$project_id)
  })
  check("Existing scientific reports and accepted window remain unchanged",all(vapply(original_hashes,function(r)brohn_hash(brohn_get_entity(store,"report",r$id)$body)==r$hash,logical(1)))&&
    brohn_hash(brohn_get_entity(store,"signal_windows",saved$id)$body)==brohn_hash(saved$body))
  check("Original source bytes remain unchanged",digest::digest(file=brohn_object_path(store,parent$body$source$hash),algo="sha256")==parent$body$source$hash)
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),source_hashes=ids(),scope="Copied original accepted fixture; direct native interval worker, guarded publications and Shiny authorization; no scientific rescoring or full browser rerun."),file.path(folder,"results.json"))
  cat(length(checks),"derived interval authorization checks passed\n")
}),error=function(e){brohn_write_json_file(list(passed=FALSE,error=conditionMessage(e),checks=as.list(checks)),file.path(folder,"failure.json"));stop(e)})
