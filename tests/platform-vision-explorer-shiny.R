# Actual Shiny handlers + saved source, bounded asynchronous reads; no new workers.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE);source("R/platform-vision-explorer-views.R",encoding="UTF-8")
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L,!dir.exists(args[[2L]]))
local({
  proof<-brohn_read_json_file(file.path(args[[1L]],"acceptance.json"));folder<-normalizePath(args[[2L]],winslash="/",mustWork=FALSE);dir.create(folder,recursive=TRUE)
  processx::run(.brohn_publication_python(),c("-B","-c","import shutil,sys;shutil.copytree(sys.argv[1],sys.argv[2])",proof$workspace,file.path(folder,"workspace")),windows_hide_window=TRUE)
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store));checks<-character();report_id<-proof$cases$face$report_id
  check<-function(ok,label){stopifnot(isTRUE(ok));checks<<-c(checks,label);cat("PASS",label,"\n");flush.console()}
  server<-function(input,output,session){state<-shiny::reactiveValues(page="report",report_id=report_id,error=NULL)
    attempt<-function(fn,...){state$error<-NULL;tryCatch(fn(),error=function(e){state$error<-conditionMessage(e);NULL})}
    ui<-brohn_install_vision_explorer(input,output,session,store,state,attempt,function(...)NULL,function(fn)fn(),register_resource=function(name,data,filter)paste0("/test/",name,"?token=1"))}
  shiny::testServer(server,{
    serial<-0L;fields<-list(channel="face",metric="face.blendshape._neutral",start="",end="",limit="25",frame="0")
    command<-function(action,changes=list(),source=NULL,epoch=NULL,extra=list()){
      h<-output$vision_explorer$html;attribute<-function(name)sub(paste0('.*data-',name,'="([^"]*)".*'),'\\1',h)
      serial<<-serial+1L;f<-fields;for(n in names(changes))f[[n]]<-changes[[n]]
      session$setInputs(vision_action=c(list(action=action,fields=f,source=brohn_default(source,attribute("source")),epoch=brohn_default(epoch,attribute("epoch")),serial=serial),extra));session$flushReact()}
    session$flushReact();command("open")
    for(i in seq_len(100L)){session$elapse(650);session$flushReact();if(!is.null(ui$active()))break;Sys.sleep(.1)}
    check(!is.null(ui$active())&&is.null(state$error),"Actual UI opens the existing complete index through asynchronous verification")
    session$setInputs(vision_channel="face",vision_metric="face.blendshape._neutral",vision_start="",vision_end="",vision_limit="25",vision_frame_index="0",vision_landmarks=TRUE,vision_width=300)
    check(grepl("Frame states only",output$vision_controls$html,fixed=TRUE)&&grepl("Source PTS origin: 2.000000",output$vision_controls$html,fixed=TRUE),"Controls expose frame-state-only view and original source clock")
    check(grepl("No recorded frame shown",output$vision_geometry$html,fixed=TRUE),"Initial frame uses explicitly labelled coordinate-only geometry")
    command("apply",list(start="0.2000000000000000001",end="0.6"))
    check(identical(ui$selection()$range,list("0.2000000000000000001","0.6"))&&ui$detail()$frame$frame_index==2L,"Visible exact decimal range excludes the lower boundary without binary64 rounding")
    check(grepl("2 rows on this page from 2",output$vision_page$html,fixed=TRUE),"Page shows the complete selected frame count")
    before<-length(brohn_list_jobs(store));command("extract",list(frame="2"))
    check(grepl("Apply the visible",state$error)&&length(brohn_list_jobs(store))==before,"Unapplied visible selection changes cannot queue another frame")
    fields$start<-"0.2000000000000000001";fields$end<-"0.6";fields$frame<-"2"
    command("extract",list(frame="3"))
    check(grepl("Show the exact visible",state$error)&&length(brohn_list_jobs(store))==before,"Unshown visible frame number cannot queue a different recorded image")
    command("frame",list(frame="3"));check(ui$detail()$frame$frame_index==3L,"Explicit frame action opens the original selected native record")
    command("frame",list(frame="2"),source="different-report")
    check(grepl("earlier video view",state$error)&&ui$detail()$frame$frame_index==3L,"Foreign source command cannot replace selected frame")
    command("frame",list(frame="2"),epoch="stale-open")
    check(grepl("earlier video view",state$error)&&ui$detail()$frame$frame_index==3L,"Earlier view epoch cannot mutate current frame")
    command("apply",list(metric=""));check(is.null(ui$selection()$metric)&&grepl("Frame states only",output$vision_plot$html,fixed=TRUE),"State-only observation view remains available without inventing numeric values")
    state$page<-"home";session$flushReact();check(is.null(ui$active())&&is.null(ui$detail())&&is.null(ui$image()),"Leaving report clears verified source and recorded-image authority")
  })
  brohn_write_json_file(list(checks=checks,workspace=store$root),file.path(folder,"results.json"));cat("PASS",length(checks),"vision Shiny checks\n")
})
