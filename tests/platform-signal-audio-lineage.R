# Focused authorization regression on an external copy of the accepted original
# video/audio fixture. No source fixture or retained scientific report is edited.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
fixture<-normalizePath(args[[1]],winslash="/",mustWork=TRUE)
folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(fixture),"brohn-audio-extract-browser-"),startsWith(basename(folder),"brohn-signal-audio-lineage-"),
  !dir.exists(file.path(folder,"workspace")))
stopifnot(file.copy(file.path(fixture,"workspace"),folder,recursive=TRUE))
checks<-character();check<-function(label,value){if(!isTRUE(value))stop(label,call.=FALSE);checks<<-c(checks,label);cat("PASS",label,"\n")}
rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
tryCatch(local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit({
    for(j in brohn_list_jobs(store,limit=1000L))if(j$status%in%c("queued","running"))brohn_cancel_job(store,j$id)
    brohn_close_store(store)
  },add=TRUE)
  stopifnot(!any(vapply(brohn_list_jobs(store,limit=1000L),function(j)j$status%in%c("queued","running"),logical(1))))
  reports<-brohn_list_entities(store,"report",limit=1000L)
  candidates<-Filter(function(r)!is.null(r$body$provenance$derived_audio_lineage),reports);stopifnot(length(candidates)==1L)
  report<-candidates[[1L]];original_reports<-lapply(reports,function(r)list(id=r$id,hash=brohn_hash(r$body)))
  lineage<-report$body$provenance$derived_audio_lineage;parent_id<-lineage$binding$parent_dataset$id
  parent<-brohn_get_entity(store,"dataset",parent_id)
  original_hash<-digest::digest(file=brohn_object_path(store,parent$body$source$hash),algo="sha256")
  check("Valid derived report resolves its complete original lineage",.brohn_sv_same(brohn_signal_audio_lineage(store,report,TRUE),lineage))
  plain<-brohn_put_entity(store,"report","report-ordinary-signal-auth-fixture",list(id="report-ordinary-signal-auth-fixture",
    title="Original processed artifact authorization fixture",origin="sample",status="Available",analysis=report$body$analysis),project_id=report$project_id)
  check("Ordinary report needs no audio parent contract",is.null(brohn_signal_audio_lineage(store,plain,TRUE)))
  identities<-function(){paths<-c("R/platform-publication.R","scripts/workers/publication.py","src/publication_guard.c",
    "R/platform-signal.R","R/platform-signal-values.R","R/platform-audio-extraction.R")
    setNames(lapply(paths,function(p)digest::digest(file=p,algo="sha256")),paths)}
  run_direct<-function(job){
    force(job)
    claim<-brohn_claim_job(store,"audio-signal-auth",180);stopifnot(identical(claim$id,job$id))
    scratch<-file.path(store$root,"scratch",job$id);dir.create(scratch,recursive=TRUE)
    data<-if(job$operation%in%c("signal_catalog","signal_preview"))brohn_signal_input(store,claim)else brohn_signal_values_input(store,claim)
    guards<-brohn_hold_signal_value_sources(store,data);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
    out<-list(report=if(job$operation%in%c("signal_catalog","signal_preview"))brohn_analyse_signal(data,scratch)else brohn_analyse_signal_values(data,scratch),code_identity=identities())
    path<-file.path(scratch,"result.json");brohn_write_json_file(out,path)
    if(job$operation%in%c("signal_catalog","signal_preview"))brohn_publish_signal_view(store,out,scratch,claim,data,path)else brohn_publish_signal_values(store,out,scratch,claim,data,path)
    final<-brohn_get_job(store,job$id);brohn_get_entity(store,if(job$operation%in%c("signal_catalog","signal_preview"))"signal_view"else"signal_values",
      brohn_default(final$result$signal_view_id,final$result$signal_values_id))
  }
  catalog_job<-brohn_queue_signal_view(store,report$id,"physiology-series");ci<-brohn_signal_input(store,catalog_job)
  check("Catalog input pins parent references and conditional worker lineage",.brohn_sv_same(ci$derived_audio_lineage,lineage)&&
    all(vapply(lineage$source_refs,`[[`,character(1),"hash")%in%vapply(ci$source_objects,`[[`,character(1),"hash")))
  catalog<-run_direct(catalog_job);t<-catalog$body$view$tables[[1L]];measure<-t$value_columns[[1L]]$name
  choice<-list(table_ids=list(t$table_id),recording_id=t$identity$recording_id,channel=t$identity$channel,value_column=measure,range=NULL)
  preview_job<-brohn_queue_signal_view(store,report$id,"physiology-series",choice);preview<-run_direct(preview_job)
  check("Valid derived catalog and preview reopen exact saved report",identical(brohn_signal_view_source(store,catalog)$id,report$id)&&
    identical(brohn_signal_view_source(store,preview)$id,report$id))
  selected<-list(table_id=t$table_id,recording_id=t$identity$recording_id,channel=t$identity$channel,value_column=measure,range=NULL,row_policy="all_source_rows")
  page_job<-brohn_queue_signal_values(store,catalog$id,selected);vi<-brohn_signal_values_input(store,page_job)
  check("Exact-value input pins every parent source reference",.brohn_sv_same(vi$derived_audio_lineage,lineage)&&
    all(vapply(lineage$source_refs,`[[`,character(1),"hash")%in%vapply(vi$source_objects,`[[`,character(1),"hash")))
  page<-run_direct(page_job);export<-run_direct(brohn_queue_signal_values(store,catalog$id,selected,"export"))
  check("Valid derived exact page and complete CSV remain available",identical(brohn_signal_values_record(store,page$id,verify=TRUE)$id,page$id)&&
    identical(brohn_signal_values_record(store,export$id,verify=TRUE)$id,export$id)&&export$body$result$csv$rows==t$rows)
  bad<-report;bad$body$provenance$derived_audio_lineage$binding$parent_source_hash<-paste(rep("0",64),collapse="")
  check("Substituted saved parent lineage is rejected",rejects(brohn_signal_audio_lineage(store,bad)))
  bad<-report;bad$body$provenance$derived_audio_lineage<-NULL
  check("Derived report cannot drop its lineage",rejects(brohn_signal_audio_lineage(store,bad)))
  bad$body$provenance<-NULL
  check("Derived report cannot erase provenance while retaining derived identity",rejects(brohn_signal_audio_lineage(store,bad)))
  move<-function(owner)DBI::dbExecute(store$con,"UPDATE entities SET project_id=? WHERE kind='dataset' AND id=?",params=list(owner,parent_id))
  move("deliberate-auth-foreign")
  check("Revoked parent prevents catalog/preview queue and existing job input",rejects(brohn_queue_signal_view(store,report$id,"physiology-series"))&&
    rejects(brohn_signal_input(store,catalog_job))&&rejects(brohn_signal_input(store,preview_job)))
  check("Revoked parent prevents retained catalog/preview reads",rejects(brohn_signal_view_source(store,catalog))&&rejects(brohn_signal_view_source(store,preview)))
  check("Revoked parent prevents exact-value queue input and saved page/export reads",rejects(brohn_queue_signal_values(store,catalog$id,selected))&&
    rejects(brohn_signal_values_input(store,page_job))&&rejects(brohn_signal_values_record(store,page$id))&&rejects(brohn_signal_values_record(store,export$id)))
  check("Unrelated ordinary report remains authorized",is.null(brohn_signal_audio_lineage(store,plain)))
  move(parent$project_id)
  # A parent move after initial validation must also fail inside publication's
  # transaction; the fault is a temporary in-process callback, never a file edit.
  publisher<-brohn_publish_entity_result;fired<-FALSE;before_views<-length(brohn_list_entities(store,"signal_view",limit=1000L))
  assign("brohn_publish_entity_result",function(store,job,input,output,kind,body,publication_path,receipt,before_commit=NULL){
    publisher(store,job,input,output,kind,body,publication_path,receipt,before_commit=function(){
      fired<<-TRUE;move("deliberate-auth-foreign");if(!is.null(before_commit))before_commit()
    })
  },envir=.GlobalEnv)
  fence_job<-brohn_queue_signal_view(store,report$id,"physiology-series",choice,max_bins=799L)
  rejected<-tryCatch(rejects(run_direct(fence_job)),finally=assign("brohn_publish_entity_result",publisher,envir=.GlobalEnv))
  check("Parent revocation at preview commit rejects publication and rolls back",rejected&&fired&&
    length(brohn_list_entities(store,"signal_view",limit=1000L))==before_views&&identical(brohn_get_entity(store,"dataset",parent_id)$project_id,parent$project_id))
  brohn_cancel_job(store,fence_job$id)
  server<-function(input,output,session){
    state<-shiny::reactiveValues(page="report",report_id=report$id,error=NULL,status=NULL)
    attempt<-function(fn)tryCatch(fn(),error=function(e){state$error<-conditionMessage(e);NULL})
    brohn_install_signal_server(input,output,session,store,state,attempt,function(x)state$status<-x,function(fn)fn())
  }
  shiny::testServer(server,{
    session$setInputs(open_signal_catalog=list(report_id=report$id,report_hash=brohn_hash(report$body),kind="physiology-series"));session$flushReact()
    session$setInputs(signal_form_identity=paste(report$id,catalog$id,sep=":"),signal_table=t$table_id);session$flushReact()
    session$setInputs(signal_measure_identity=paste(catalog$id,t$table_id,sep=":"),signal_measure=measure,signal_full_range=TRUE,create_signal_preview=1L)
    session$flushReact();session$elapse(1200);session$flushReact()
    check("Live derived plot is readable before authority changes",grepl("Processed signal chart",output$signal_plot$html,fixed=TRUE))
    move("deliberate-auth-foreign")
    check("SVG and JSON downloads reject revocation before the next UI poll",rejects(output$signal_svg_download)&&rejects(output$signal_json_download))
    session$elapse(1200);session$flushReact()
    check("Live derived catalog and plot clear after parent authority loss",rejects(output$signal_plot)&&rejects(output$signal_catalog))
    check("Live authority error explains how to recover",grepl("unavailable|project|source",output$signal_progress$html))
    move(parent$project_id);session$elapse(1200);session$flushReact()
    check("Restored authority can reopen unchanged saved plot",grepl("Processed signal chart",output$signal_plot$html,fixed=TRUE))
  })
  check("Every original scientific report remains unchanged",all(vapply(original_reports,function(r)identical(brohn_hash(brohn_get_entity(store,"report",r$id)$body),r$hash),logical(1))))
  check("Original video remains byte-identical",identical(digest::digest(file=brohn_object_path(store,parent$body$source$hash),algo="sha256"),original_hash))
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),source_hashes=identities(),report_id=report$id,
    scope="Focused copied-fixture domain/native adapter publication and Shiny authorization checks; no scientific rescoring or browser journey."),file.path(folder,"results.json"))
  cat(length(checks),"derived signal authority checks passed\n")
}),error=function(e){brohn_write_json_file(list(passed=FALSE,error=conditionMessage(e),checks=as.list(checks)),file.path(folder,"failure.json"));stop(e)})
