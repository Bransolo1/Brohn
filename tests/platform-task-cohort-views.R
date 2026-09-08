source("R/platform-load.R");brohn_load(ui=TRUE)
for(n in c("task-cohort","task-cohort-storage","task-cohort-views"))source(paste0("R/platform-",n,".R"))
source("tests/fixtures/original-task-cohort-store.R")
local({
  checks<-0L;check<-function(label,x){if(!isTRUE(x))stop("Cohort views: ",label,call.=FALSE);checks<<-checks+1L}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  store<-brohn_open_store(tempfile("brohn-task-cohort-views-"));brohn_initialise_library(store)
  on.exit({for(j in brohn_list_jobs(store))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id);brohn_close_store(store)},add=TRUE)
  f<-brohn_original_cohort_store_fixture(store);other<-brohn_create_study(store,"Original other destination")
  server<-function(input,output,session) {
    current<-new.env(parent=emptyenv());current$study<-f$study
    state<-shiny::reactiveValues(page="study",study_id=f$study$id,stage="Results",error=NULL,note=NULL,revision=0L)
    attempt<-function(fn){state$error<-NULL;tryCatch(fn(),error=function(e){state$error<-conditionMessage(e);NULL})}
    message<-function(text)state$note<-text
    refresh<-function()state$revision<-state$revision+1L
    api<-brohn_install_task_cohort_ui(input,output,session,store,state,current,attempt,message,refresh)
  }
  shiny::testServer(server,{
    open<-function() {
      state$page<-"study";state$study_id<-f$study$id;state$stage<-"Results";current$study<-f$study
      session$setInputs(study_form_identity=paste(f$study$id,"Results",sep=":"),task_cohort_open=f$study$id)
      ctx<-api$context();args<-list();args[[.brohn_tc_field(ctx$token,"reports")]]<-vapply(f$reports,`[[`,character(1),"id")
      do.call(session$setInputs,args);session$setInputs(task_cohort_review=list(token=ctx$token));api$context()
    }
    fill<-function(ctx,mode="source",confirmed=FALSE,policy="one_selected_attempt_per_person") {
      values<-list(membership_mode="all",identity_mode=mode,identity_confirmed=confirmed,"repeat"=policy,description="Original explicitly reviewed UI cohort",identity_notes="Original participant register reviewed")
      names(values)<-vapply(names(values),function(n).brohn_tc_field(ctx$token,n),character(1));do.call(session$setInputs,values)
    }
    ctx<-open()
    check("source review opens one frozen compatible administration selection",is.null(state$error)&&ctx$phase=="membership"&&length(ctx$catalog$attempts)==3L&&length(ctx$catalog$groups)==1L)
    token<-ctx$token;fill(ctx)
    session$setInputs(task_cohort_save=list(token=token))
    check("source codes cannot become people before explicit review",length(brohn_list_jobs(store))==0L&&grepl("Confirm",state$error,fixed=TRUE)&&identical(api$context()$token,token))
    fill(ctx,confirmed=TRUE);session$setInputs(task_cohort_save=list(token=token))
    check("one administration policy asks for explicit repeat choice even with matching source IDs",length(brohn_list_jobs(store))==0L&&grepl("before considering",state$error,fixed=TRUE))
    # Editing or hiding controls must not cause server-side replacement. Their
    # names are stable within this modal token and source context.
    edit<-list(identity_mode="edit",person_1="Explicit P",person_2="Explicit Q",session_1="Visit A",session_2="Visit B",session_3="Visit C")
    names(edit)<-vapply(names(edit),function(n).brohn_tc_field(token,n),character(1));do.call(session$setInputs,edit)
    session$flushReact()
    check("editing inputs preserves the same stable modal context",identical(api$context()$token,token)&&identical(input[[.brohn_tc_field(token,"person_1")]],"Explicit P"))
    fill(ctx,mode="source",confirmed=TRUE,policy="equal_attempts_within_session_then_equal_sessions_within_person")
    check("switching identity modes does not erase hidden shared-code drafts",identical(input[[.brohn_tc_field(token,"person_1")]],"Explicit P")&&identical(api$context()$token,token))
    title_input<-list();title_input[[.brohn_tc_field(token,"description")]]<-paste(rep("\u00e9",121L),collapse="");do.call(session$setInputs,title_input)
    session$setInputs(task_cohort_save=list(token=token))
    check("oversized UI report name preserves the review without queueing",length(brohn_list_jobs(store))==0L&&grepl("240 UTF-8 bytes",state$error,fixed=TRUE)&&identical(api$context()$token,token))
    title_input[[.brohn_tc_field(token,"description")]]<-"Original explicitly reviewed UI cohort";do.call(session$setInputs,title_input)
    session$setInputs(task_cohort_save=list(token=token));jobs<-brohn_list_jobs(store)
    check("explicit reviewed source identities and repeat policy queue once",is.null(state$error)&&length(jobs)==1L&&jobs[[1L]]$status=="queued"&&jobs[[1L]]$operation=="analyse_task_cohort"&&state$page=="activity"&&is.null(api$context()))
    check("queued input pins the exact three administration hashes and original source names",length(jobs[[1L]]$request$plan$membership)==3L&&length(jobs[[1L]]$request$reports)==3L&&
      jobs[[1L]]$request$identity_map$participants[[1L]]$person_id=="P"&&grepl("explicitly confirmed",jobs[[1L]]$request$identity_map$linkage_statement,fixed=TRUE))
    check("one existing UI name field pins the exact saved report title",jobs[[1L]]$request$report_title=="Original explicitly reviewed UI cohort"&&jobs[[1L]]$request$plan$description==jobs[[1L]]$request$report_title)
    brohn_cancel_job(store,jobs[[1L]]$id)
    session$setInputs(task_cohort_save=list(token=token))
    check("late duplicate save cannot reopen a completed dialog",length(brohn_list_jobs(store))==1L&&!is.null(state$error))
    ctx<-open();fill(ctx,confirmed=TRUE,policy="equal_attempts_within_session_then_equal_sessions_within_person")
    session$setInputs(task_cohort_cancel=list(token=ctx$token));session$setInputs(task_cohort_save=list(token=ctx$token))
    check("Cancel invalidates pending review and prevents any queue write",is.null(api$context())&&length(brohn_list_jobs(store))==1L&&!is.null(state$error))
    ctx<-open();fill(ctx,confirmed=TRUE,policy="equal_attempts_within_session_then_equal_sessions_within_person")
    state$study_id<-other$id;current$study<-other;session$setInputs(study_form_identity=paste(other$id,"Results",sep=":"),task_cohort_save=list(token=ctx$token))
    check("navigation cannot send prior membership into another study",length(brohn_list_jobs(store))==1L&&grepl("context has changed",state$error,fixed=TRUE))
    state$study_id<-f$study$id;current$study<-f$study;session$setInputs(study_form_identity=paste(f$study$id,"History",sep=":"),task_cohort_save=list(token=ctx$token))
    check("stale form stage identity is rejected",length(brohn_list_jobs(store))==1L&&!is.null(state$error))
    saved<-f$publish(brohn_analyse_task_cohort(brohn_task_cohort_input(store,jobs[[1L]]$request))$analysis,title="Original saved cohort evidence")
    path<-tempfile(fileext=".csv");state$page<-"report";state$report_id<-saved$id
    for(level in c("per_person","per_session","attempt_metrics","membership")) {
      api$download(level,path);table<-brohn_read_table(path,"csv",20000L)
      check(paste("guarded",level,"download contains its complete frozen rows"),nrow(table)==length(saved$body$analysis[[level]]))
    }
    state$page<-"study"
    check("late cohort download rejects after leaving report page",rejects(api$download("membership",path))&&grepl("current saved",state$error,fixed=TRUE))
    state$page<-"report";state$report_id<-f$reports[[1L]]$id
    check("ordinary imported report cannot be exported as cohort evidence",rejects(api$download("membership",path))&&grepl("does not contain",state$error,fixed=TRUE))
    state$report_id<-"report-original-absent"
    check("missing selected cohort report fails instead of exporting another source",rejects(api$download("membership",path)))
    unlink(path)
  })
  catalog<-brohn_task_cohort_catalog(store,f$study$id,lapply(f$reports,`[[`,"id"));token<-"original-static-context"
  inputs<-list();put<-function(name,value)inputs[[.brohn_tc_field(token,name)]]<<-value
  put("identity_mode","source");put("identity_confirmed",FALSE)
  check("pure input helper rejects truthy strings as identity confirmation",{put("identity_confirmed","true");rejects(brohn_task_cohort_crosswalk_input(catalog,catalog$attempts,token,inputs))})
  put("identity_mode","unlinked")
  unlinked<-brohn_task_cohort_crosswalk_input(catalog,catalog$attempts,token,inputs)
  check("explicit unlinked choice leaves every destination null",all(vapply(unlinked$participants,function(p)is.null(p$person_id),logical(1))))
  put("identity_mode","edit");put("identity_confirmed",TRUE)
  for(i in seq_along(catalog$identities$participants))put(paste0("person_",i),paste0("person-",i))
  for(i in seq_along(catalog$identities$sessions))put(paste0("session_",i),paste0("visit-",i))
  put("person_1","001")
  edited<-brohn_task_cohort_crosswalk_input(catalog,catalog$attempts,token,inputs)
  check("edited text001 is preserved without numeric conversion",identical(edited$participants[[1L]]$person_id,"001"))
  subset<-catalog$attempts[c(1L,3L)]
  edited_subset<-brohn_task_cohort_crosswalk_input(catalog,subset,token,inputs)
  check("explicit membership subset uses only its exact source identities",length(edited_subset$sessions)==2L&&setequal(vapply(edited_subset$sessions,`[[`,character(1),"session_id"),c("visit-1","visit-3")))
  put("membership_mode","select");put("attempts",vapply(subset,`[[`,character(1),"id"))
  check("individual membership choice preserves exact administration order",identical(.brohn_tc_review_attempts(catalog,token,inputs),subset))
  put("attempts",c(subset[[1L]]$id,subset[[1L]]$id))
  check("duplicate selected IDs cannot inflate membership",rejects(.brohn_tc_review_attempts(catalog,token,inputs)))
  put("attempts","not-an-original-administration")
  check("unknown selected IDs never resolve by row number",rejects(.brohn_tc_review_attempts(catalog,token,inputs)))
  file<-tempfile(fileext=".json");brohn_write_json_file(lapply(subset,`[[`,"id"),file)
  put("membership_mode","file");put("membership_file",data.frame(name="original-membership.json",datapath=file))
  check("complete reviewed membership file uses exact IDs",identical(.brohn_tc_review_attempts(catalog,token,inputs),subset));unlink(file)
  file<-tempfile(fileext=".json");brohn_write_json_file(edited,file)
  put("identity_mode","file");put("identity_file",data.frame(name="original-identities.json",datapath=file))
  check("reviewed identity file retains the full declared mapping",identical(brohn_json(brohn_task_cohort_crosswalk_input(catalog,catalog$attempts,token,inputs)),brohn_json(edited)));unlink(file)
  originally_unlinked<-catalog;originally_unlinked$attempts[[1L]]$participant_linkage<-FALSE;originally_unlinked$attempts[[1L]]$score$participant_linkage<-FALSE
  disclosure<-brohn_task_cohort_identity_review_rows(originally_unlinked)
  check("source review exposes original unlinked counts without silently relabelling them",disclosure[[1L]]$originally_unlinked_administrations==1L&&grepl("independent",disclosure[[1L]]$source_linkage,fixed=TRUE))
  put("identity_mode","source");put("identity_confirmed",TRUE);put("identity_notes","")
  check("linking generated or originally unlinked codes requires an evidence note",rejects(brohn_task_cohort_crosswalk_input(originally_unlinked,originally_unlinked$attempts,token,inputs)))
  put("identity_notes","Original independent participant register establishes these person and visit identities.")
  reviewed<-brohn_task_cohort_crosswalk_input(originally_unlinked,originally_unlinked$attempts,token,inputs)
  check("explicitly justified linkage keeps original false flag visible",!originally_unlinked$attempts[[1L]]$participant_linkage&&reviewed$participants[[1L]]$person_id=="P"&&grepl("independent participant register",reviewed$linkage_statement,fixed=TRUE))
  check("all UI jobs were cancelled before any scientific process",all(vapply(brohn_list_jobs(store),function(j)j$status=="cancelled"&&j$attempt==0L,logical(1))))
  cat("Task cohort views:",checks,"actual Shiny-handler and typed review checks passed; no browser or scientific worker claim.\n")
})
