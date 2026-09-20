# Real domain/store + Shiny, using a fresh copy of qualified input-waveform fixtures.
# This suite does not launch scientific workers; requested jobs are inspected/cancelled.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
source("R/platform-cardiac-review.R",encoding="UTF-8");source("R/platform-cardiac-review-views.R",encoding="UTF-8")
local({
  original<-normalizePath(args[[1]],winslash="/",mustWork=TRUE);folder<-normalizePath(args[[2]],winslash="/",mustWork=FALSE)
  stopifnot(startsWith(basename(folder),"brohn-cardiac-review-ui-model-"),!dir.exists(folder));dir.create(folder,recursive=TRUE)
  proof<-brohn_read_json_file(file.path(original,"acceptance.json"));stopifnot(length(proof$checks)>=22L,file.copy(proof$workspace,folder,recursive=TRUE))
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store));checks<-character()
  check<-function(ok,name){if(!isTRUE(ok))stop(name);checks<<-c(checks,name);cat("PASS",name,"\n")}
  report<-brohn_get_entity(store,"report",proof$reports$ecg$report_id);cat_record<-brohn_get_entity(store,"signal_view",proof$reports$ecg$catalog_id);tab<-cat_record$body$view$tables[[1]]
  server<-function(input,output,session){
    state<-shiny::reactiveValues(page="report",report_id=report$id,error=NULL)
    attempt<-function(fn,...){state$error<-NULL;tryCatch(fn(),error=function(e){state$error<-conditionMessage(e);NULL})}
    ui<-brohn_install_cardiac_review_ui(input,output,session,store,state,attempt,function(...)NULL,function(fn)fn(),function()report,function()cat_record,function()tab)
  }
  shiny::testServer(server,{
    serial<-0L
    command<-function(action,fields=NULL,payload=list(),source=NULL,form=NULL,...) {
      serial<<-serial+1L;active<-ui$active();f<-if(is.null(active))list()else ui$baseline()
      if(!is.null(fields))for(name in names(fields))f[[name]]<-fields[[name]]
      cmd<-c(list(action=action,source=if(is.null(source))ui$source_key()else source,form=if(is.null(form)){if(is.null(active))NULL else ui$form_key()}else form,
        fields=f,payload=payload,title="Original cardiac UI decisions",choice="",history="",nonce=as.character(serial)),list(...))
      # Extra named fields override the defaults without creating duplicate names.
      cmd<-cmd[!duplicated(names(cmd),fromLast=TRUE)];session$setInputs(cardiac_ui_action=cmd);invisible(cmd)
    }
    command("create");r<-ui$active();check(!is.null(r)&&r$revision==1L&&!length(r$body$spans),"Actual UI action creates one source-bound empty review")
    check(grepl("Recording-relative seconds",output$cardiac_review_editor$html,fixed=TRUE)&&grepl("Curated acquisition sequence",output$cardiac_review_editor$html,fixed=TRUE),"Editor exposes recording-relative seconds and explicit advanced source-index semantics")
    command("resolve",list(start_time="10.0000000000001",end_time="12.0000000000002",reason="researcher_exclusion",note="Original precise visible bounds"))
    pending<-ui$pending();q<-brohn_get_job(store,pending$id)
    check(q$request$candidate$start_time_s_text=="10.0000000000001"&&q$request$candidate$end_time_s_text=="12.0000000000002"&&q$request$candidate$note=="Original precise visible bounds","Time preview queues exact visible decimal strings and rationale")
    brohn_cancel_job(store,q$id)
    command("resolve",list(start_time="10.0000000000001",end_time="12.0000000000002",reason="researcher_exclusion",note="Original precise visible bounds"))
    retried<-brohn_get_job(store,ui$pending()$id);check(retried$id!=q$id&&identical(brohn_hash(retried$request),brohn_hash(q$request)),"Cancelled time resolution retries its original frozen request and candidate identity")
    brohn_cancel_job(store,retried$id)
    old_form<-ui$form_key();command("save_samples",list(mode="samples",start_sample="3600",end_sample="4320",reason="researcher_exclusion",note="Exact source interval"))
    r<-ui$active();check(r$revision==2L&&r$body$spans[[1]]$start_sample==3600&&r$body$spans[[1]]$end_sample==4320,"Source-row save uses the same action snapshot and exact half-open bounds")
    command("save_samples",list(mode="samples",start_sample="5000",end_sample="6000"),form=old_form)
    check(!is.null(state$error)&&brohn_cardiac_review(store,r$id)$revision==2L,"Old form identity cannot overwrite the new review version")
    before<-length(brohn_list_jobs(store));command("preview",list(note="Unsaved visible note"))
    check(grepl("Save or cancel",state$error)&&length(brohn_list_jobs(store))==before,"Unsaved visible edits cannot queue a preview of different saved decisions")
    command("preview");q<-brohn_get_job(store,ui$pending()$id)
    check(q$request$review_revision==r$revision&&q$request$review_hash==brohn_hash(r$body),"Global support preview freezes exact current saved review identity")
    brohn_cancel_job(store,q$id)
    command("recalculate",payload=list(id="cardiac-preview-not-observed"))
    check(grepl("Preview",state$error)&&is.null(ui$result()),"A missing preview cannot authorize recalculation")
    span<-r$body$spans[[1]];command("edit",payload=list(id=span$id))
    check(ui$baseline()$mode=="samples"&&ui$baseline()$start_sample=="3600"&&identical(ui$editing(),span$id),"Editing reopens exact source bounds rather than reconstructing rounded times")
    command("save_samples",list(mode="samples",start_sample="3600",end_sample="4321",reason="researcher_exclusion",note="One additional source sample"))
    r<-ui$active();check(r$revision==3L&&r$body$spans[[1]]$end_sample==4321,"One-sample edit creates a new immutable saved version")
    command("history",history="2");h<-ui$history();check(h$revision==2L&&h$body$spans[[1]]$end_sample==4320,"History opens exact earlier exclusions")
    command("restore",payload=list(revision=h$revision,hash=brohn_hash(h$body)));r<-ui$active()
    check(r$revision==4L&&r$body$spans[[1]]$end_sample==4320&&brohn_cardiac_review(store,r$id,3L)$body$spans[[1]]$end_sample==4321,"Restore adds a current revision and preserves the intervening decision")
    command("remove",payload=list(id=r$body$spans[[1]]$id));r<-ui$active();check(r$revision==5L&&!length(r$body$spans),"Removal is a versioned decision, preserving earlier masks")
    brohn_save_cardiac_span(store,r$id,r$revision,7200,7560,"signal_loss","Concurrent saved decision")
    command("preview");check(grepl("changed in another action",state$error)&&ui$active()$revision==5L,"External revision change rejects stale UI preview/queue authority")
    command("open",choice=r$id);check(ui$active()$revision==6L&&length(ui$active()$body$spans)==1L,"Explicit reopen loads the newly current review")
    command("preview",source="another-report-and-table");check(grepl("exact cardiac recording",state$error),"Foreign source identity rejects before queueing")
    state$page<-"home";session$flushReact();check(is.null(ui$active())&&is.null(ui$preview())&&is.null(ui$resolution()),"Leaving the report clears active decisions and preview authority")
  })
  fragments<-list(list(status="parent_retained",source_start_sample=0,source_end_sample=2,points=list(list(time_s=0,value=1,source_sample_index=0),list(time_s=1,value=2,source_sample_index=1))),
    list(status="researcher_excluded",source_start_sample=2,source_end_sample=3,points=list(list(time_s=2,value=10,source_sample_index=2))),
    list(status="parent_filter_edge",source_start_sample=3,source_end_sample=4,points=list(list(time_s=3,value=0,source_sample_index=3))))
  svg<-as.character(brohn_cardiac_input_svg(list(fragments=fragments,unit="mV"),340))
  check(length(regmatches(svg,gregexpr("<polyline",svg,fixed=TRUE))[[1]])==3L&&all(vapply(c("#a7e9d3","#fa9a91","#e8c87a"),function(x)grepl(x,svg,fixed=TRUE),logical(1))),"Input chart keeps all three observed-status fragments separate, including excluded/edge input")
  brohn_write_json_file(list(checks=checks,origin="actual_source_bound_shiny_no_scientific_workers",source=original),file.path(folder,"results.json"));cat("PASS",length(checks),"cardiac review Shiny/chart checks\n")
})
