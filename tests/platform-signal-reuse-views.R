source("R/platform-load.R",encoding="UTF-8");brohn_load()
local({
  root<-Sys.getenv("BROHN_INTERVAL_REUSE_UI_QA",tempfile("brohn-interval-reuse-views-"));dir.create(root,recursive=TRUE,showWarnings=FALSE)
  root<-normalizePath(root,winslash="/",mustWork=TRUE)
  processx::run(brohn_rscript(),c("tests/fixtures/researcher-interval-reuse.R","setup",root),windows_hide_window=TRUE,timeout=300000)
  config<-brohn_read_json_file(file.path(root,"fixture.json"));store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store))
  source<-brohn_signal_annotations(store,config$records$original$annotations_id);target<-brohn_get_entity(store,"signal_view",config$records$target$catalog_id)
  report<-brohn_get_entity(store,"report",config$records$target$report_id);checks<-0L
  check<-function(label,value){if(!isTRUE(value))stop("Interval reuse views: ",label);checks<<-checks+1L}
  server<-function(input,output,session){state<-shiny::reactiveValues(page="report",report_id=report$id,error=NULL)
    attempt<-function(fn,...){state$error<-NULL;tryCatch(fn(),error=function(e){state$error<-conditionMessage(e);NULL})}
    controller<-brohn_install_signal_annotations_ui(input,output,session,store,state,attempt,function(x)NULL,function(fn)fn(),
      shiny::reactive(report),shiny::reactive(target),shiny::reactive(target$body$view$tables[[1L]]))
  }
  shiny::testServer(server,{
    key<-paste(report$id,target$id,target$revision,brohn_hash(target$body),"segment-1",sep=":")
    session$setInputs(interval_reuse_target_identity="stale",interval_reuse_choice=source$id,choose_interval_reuse=1L)
    check("old target form cannot select original",!is.null(state$error)&&is.null(controller$reuse$chosen()))
    session$setInputs(interval_reuse_target_identity=key,choose_interval_reuse=2L)
    check("exact target permits explicit original selection",is.null(state$error)&&controller$reuse$chosen()$record$id==source$id)
    session$setInputs(interval_reuse_form_identity=.brohn_interval_identity(source),interval_reuse_version=3,interval_reuse_title="Mapped <b>untrusted</b>",
      interval_reuse_source_anchor=0,interval_reuse_target_anchor=10,interval_reuse_reason="",preview_interval_reuse=1L)
    check("blank rationale blocks preview without saving",!is.null(state$error)&&is.null(controller$reuse$preview())&&length(brohn_list_entities(store,"signal_annotations"))==1L)
    session$setInputs(interval_reuse_reason="Matching fixture event",preview_interval_reuse=2L)
    p<-controller$reuse$preview()
    check("preview contains all independently mapped boundaries",is.null(state$error)&&p$intervals[[2]]$end_s==16&&length(p$intervals)==2)
    html<-output$signal_interval_reuse_preview$html
    check("preview escapes text and shows untrimmed range warning",grepl("&lt;b&gt;",html,fixed=TRUE)&&grepl("Boundaries are preserved",html,fixed=TRUE)&&grepl("Original baseline label",html,fixed=TRUE))
    session$setInputs(interval_reuse_target_anchor=11)
    check("edited mapping clears reviewed preview",is.null(controller$reuse$preview()))
    session$setInputs(apply_interval_reuse=list(hash=brohn_hash(p)))
    check("delayed apply after edit cannot save",!is.null(state$error)&&length(brohn_list_entities(store,"signal_annotations"))==1L)
    session$setInputs(interval_reuse_target_anchor=10,preview_interval_reuse=3L)
    p<-controller$reuse$preview();session$setInputs(apply_interval_reuse=list(hash=brohn_hash(p)))
    saved<-controller$active()
    check("apply activates new target set and clears preview",is.null(state$error)&&saved$body$report_id==report$id&&saved$revision==1L&&is.null(controller$reuse$preview()))
    check("new set opens empty summary state with source provenance",is.null(controller$summary())&&is.null(controller$job_id())&&saved$body$reuse$source$annotation$id==source$id)
    exact<-brohn_save_signal_interval(store,saved$id,1L,"Exact fractional boundary","",0.12345678901234566,1.1234567890123457,"")
    controller$active(exact);session$flushReact();i<-exact$body$intervals[[3L]]
    session$setInputs(signal_interval_command=list(identity=.brohn_interval_identity(exact),action="edit",id=i$id))
    check("editor renders round-trip exact boundary digits",grepl('value="0.12345678901234566"',output$signal_annotation_editor$html,fixed=TRUE))
    session$setInputs(interval_form_identity=.brohn_interval_identity(exact),interval_label=i$label,interval_category="",interval_note="",
      interval_start=as.numeric("0.12345678901234566"),interval_end=as.numeric("1.1234567890123457"),save_signal_interval=1L)
    check("unchanged exact-value edit does not move either boundary",identical(controller$active()$body$intervals[[3L]]$start_s,i$start_s)&&identical(controller$active()$body$intervals[[3L]]$end_s,i$end_s))
    session$setInputs(choose_interval_reuse=3L,preview_interval_reuse=4L)
    # Choosing resets the form; then use exact original pinned identity.
    session$setInputs(interval_reuse_form_identity=.brohn_interval_identity(source),interval_reuse_version=2,preview_interval_reuse=5L)
    check("explicit older version previews its one saved interval",controller$reuse$preview()$source$annotation$revision==2L&&length(controller$reuse$preview()$intervals)==1L)
    session$setInputs(interval_reuse_choice="absent",preview_interval_reuse=6L)
    check("unconfirmed source selection cannot reuse previous source",!is.null(state$error)&&is.null(controller$reuse$preview()))
    session$setInputs(interval_reuse_choice=source$id,choose_interval_reuse=4L,interval_reuse_version=3,preview_interval_reuse=7L)
    changed<-brohn_save_signal_interval(store,source$id,3L,"Changed original","baseline",0,2,"",source$body$intervals[[1]]$id)
    session$setInputs(preview_interval_reuse=8L)
    check("external original edit requires fresh selection",!is.null(state$error)&&grepl("original intervals changed",state$error,fixed=TRUE))
    state$page<-"home";session$flushReact()
    check("navigation clears source and preview authority",is.null(controller$reuse$chosen())&&is.null(controller$reuse$preview())&&is.null(controller$active()))
  })
  brohn_write_json_file(list(passed=TRUE,checks=checks),file.path(root,"views-acceptance.json"));cat(checks," interval reuse view checks passed\n")
})
