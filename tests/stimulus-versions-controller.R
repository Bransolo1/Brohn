# Three arguments: source16 checkout, overlay packet, NEW output directory.
# This test requires the reviewed token + current Plan guard correction; it must
# not adapt silently to the original bare actionButton implementation.
local({
  args<-commandArgs(TRUE);stopifnot(length(args)==3L)
  base<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
  packet<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
  output<-args[[3L]];stopifnot(!file.exists(output));dir.create(output,recursive=TRUE)
  output<-normalizePath(output,winslash="/",mustWork=TRUE)
  previous<-getwd();setwd(base);on.exit(setwd(previous),add=TRUE)
  env<-new.env(parent=.GlobalEnv)
  source("R/platform-load.R",local=env,encoding="UTF-8");env$brohn_load(envir=env,ui=TRUE)
  for(name in c("platform-stimulus-versions.R","platform-stimulus-version-views.R","platform-views.R"))
    source(file.path(packet,"R",name),local=env,encoding="UTF-8")
  env$qa_output<-output;env$qa_packet<-packet
  evalq(local({
    started<-proc.time()[["elapsed"]];checks<-character();passed<-FALSE;store<-NULL;closed<-FALSE
    check<-function(label,ok){if(!isTRUE(ok))stop(label,call.=FALSE);checks<<-c(checks,label);cat("PASS",label,"\n")}
    equal<-function(a,b)identical(brohn_json(a),brohn_json(b))
    files<-file.path(qa_packet,"R",c("platform-stimulus-versions.R","platform-stimulus-version-views.R","platform-views.R"))
    inputs<-lapply(files,function(p)list(path=p,sha256=digest::digest(file=p,algo="sha256")))
    on.exit({
      error<-NULL;if(!is.null(store))tryCatch({brohn_close_store(store);closed<-TRUE},error=function(e)error<<-conditionMessage(e))
      exact<-all(vapply(inputs,function(x)identical(digest::digest(file=x$path,algo="sha256"),x$sha256),logical(1)))
      writeLines(jsonlite::toJSON(list(passed=passed&&closed&&exact,checks=as.list(checks),elapsed_s=proc.time()[["elapsed"]]-started,
        inputs=inputs,inputs_exact_after=exact,store_closed=closed,close_error=error,
        scope="Actual isolated Shiny observers with real SQLite Save/CAS/rollback; controller fixture capture and rendering only. No connected-app/browser/Axe claim, science, services or participant session."),
        auto_unbox=TRUE,null="null",pretty=TRUE),file.path(qa_output,"RESULTS.json"),useBytes=TRUE)
    },add=TRUE)
    check("installer exposes current navigation state guard","state"%in%names(formals(brohn_install_stimulus_versions)))
    store<-brohn_open_store(file.path(qa_output,"workspace"));brohn_initialise_library(store)
    study<-brohn_create_study(store,"Original controller study")
    d<-study$body;for(i in seq_along(d$stimuli))d$stimuli[[i]]$content<-paste("Original text",i)
    study<-brohn_save_study(store,d,study$revision)
    foreign<-brohn_create_study(store,"Other actual study")
    source_id<-study$body$stimuli[[1L]]$id
    cat_state<-function()list(
      entities=DBI::dbGetQuery(store$con,"SELECT * FROM entities ORDER BY kind,id"),
      versions=DBI::dbGetQuery(store$con,"SELECT kind,id,revision,hex(CAST(body_json AS BLOB)) AS body_bytes,body_hash FROM entity_versions ORDER BY kind,id,revision"),
      operations=DBI::dbGetQuery(store$con,"SELECT * FROM entity_operations ORDER BY operation_id"),
      objects=DBI::dbGetQuery(store$con,"SELECT * FROM objects ORDER BY hash"),
      jobs=DBI::dbGetQuery(store$con,"SELECT * FROM jobs ORDER BY id"),
      audit=DBI::dbGetQuery(store$con,"SELECT * FROM audit_log ORDER BY sequence"))
    server<-function(input,output,session){
      state<-shiny::reactiveValues(page="study",stage="Plan",study_id=study$id,error=NULL)
      current<-new.env(parent=emptyenv());current$study<-study
      hooks<-new.env(parent=emptyenv());hooks$capture<-function()invisible(NULL);hooks$capture_calls<-0L;hooks$updates<-0L;hooks$save_in_batch<-logical();hooks$after_save<-function()invisible(NULL)
      capture<-function(){hooks$capture_calls<-hooks$capture_calls+1L;hooks$capture()}
      update<-function(design){hooks$save_in_batch<-c(hooks$save_in_batch,RSQLite::sqliteIsTransacting(store$con));
        saved<-brohn_save_study(store,design,current$study$revision);current$study<-saved;hooks$after_save();hooks$updates<-hooks$updates+1L;invisible(saved)}
      attempt<-function(fn,...){state$error<-NULL;tryCatch(fn(),error=function(e){state$error<-conditionMessage(e);NULL})}
      context<-brohn_install_stimulus_versions(input,output,session,store,current,state,capture,update,attempt)
    }
    shiny::testServer(server,{
      session$flushReact()
      command<-list(study_id=study$id,stimulus_id=source_id)
      open<-function(cmd=command){
        session$setInputs(study_form_identity=paste(current$study$id,"Plan",sep=":"))
        session$setInputs(duplicate_stimulus=cmd)
        pin<-context();stopifnot(!is.null(pin),brohn_text(pin$token,128))
        session$setInputs(stimulus_version_dialog_identity=pin$token)
        pin
      }
      send<-function(pin,title="New version",condition="__new__",role="test"){
        session$setInputs(stimulus_version_title=title,stimulus_version_condition=condition,stimulus_version_role=role)
        session$setInputs(confirm_stimulus_version=list(token=pin$token))
      }
      pin<-open();before<-cat_state();n<-length(current$study$body$stimuli);nc<-length(current$study$body$conditions)
      dialog<-do.call(brohn_stimulus_version_dialog,list(design=current$study$body,stimulus=current$study$body$stimuli[[1L]],token=pin$token))
      html<-htmltools::renderTags(dialog)$html;writeLines(html,file.path(qa_output,"dialog.html"),useBytes=TRUE)
      check("dialog states within-participant exposure and condition pooling",grepl("every stimulus once",html,fixed=TRUE)&&grepl("pool stimuli",html,fixed=TRUE)&&grepl("separate condition",html,fixed=TRUE))
      check("dialog starts at explicit separate-condition choice",grepl('value="__new__" selected',html,fixed=TRUE))
      check("dialog binds a hidden identity and token-bearing confirmation",grepl("stimulus_version_dialog_identity",html,fixed=TRUE)&&grepl("confirm_stimulus_version",html,fixed=TRUE)&&grepl(pin$token,html,fixed=TRUE))
      unsafe<-current$study$body$stimuli[[1L]];unsafe$title<-"<script>alert(1)</script>"
      escaped<-htmltools::renderTags(brohn_stimulus_version_dialog(current$study$body,unsafe,pin$token))$html
      check("literal source title is escaped rather than rendered as script",!grepl("<script>alert(1)</script>",escaped,fixed=TRUE)&&grepl("&lt;script&gt;",escaped,fixed=TRUE))
      plan<-htmltools::renderTags(brohn_plan_ui(store,current$study$body))$html
      check("real Plan exposes each command with a stable return-focus target",all(vapply(current$study$body$stimuli,
        function(s)grepl(paste0('id="stimulus_version_',s$id,'"'),plan,fixed=TRUE),logical(1))))
      captures<-hooks$capture_calls;send(list(token="wrong-token"))
      check("wrong token is refused before capture or any catalog write",!is.null(state$error)&&identical(before,cat_state())&&hooks$updates==0L&&hooks$capture_calls==captures)
      send(pin,title="")
      check("invalid title cannot append a condition or version",!is.null(state$error)&&identical(before,cat_state())&&length(current$study$body$stimuli)==n&&length(current$study$body$conditions)==nc)
      send(pin,condition="missing")
      check("foreign condition cannot append partial state",!is.null(state$error)&&identical(before,cat_state()))
      DBI::dbExecute(store$con,"CREATE TRIGGER qa_version_abort BEFORE INSERT ON entity_versions WHEN NEW.kind='study' AND instr(NEW.body_json,'Fault injected version')>0 BEGIN SELECT RAISE(ABORT,'injected version save fault'); END")
      send(pin,title="Fault injected version")
      check("actual SQLite insertion failure rolls back head revision audit and both collections",!is.null(state$error)&&identical(before,cat_state())&&current$study$revision==study$revision&&hooks$updates==0L)
      DBI::dbExecute(store$con,"DROP TRIGGER qa_version_abort")
      original_current<-current$study;hooks$after_save<-function()stop("Injected after real save assigned current",call.=FALSE)
      send(pin,title="Real save then callback error")
      check("error after real save restores both catalog and current study to original revision",!is.null(state$error)&&
        identical(before,cat_state())&&equal(current$study,original_current)&&identical(context()$token,pin$token)&&!RSQLite::sqliteIsTransacting(store$con))
      check("post-save failure is actionable in the retained dialog",grepl("Injected after real save",output$stimulus_version_error$html,fixed=TRUE))
      hooks$after_save<-function()invisible(NULL)
      send(pin,title="Retained control version",role="control")
      saved<-current$study;after<-cat_state()
      check("successful observer persists one complete version in one revision",is.null(state$error)&&saved$revision==study$revision+1L&&
        length(saved$body$stimuli)==n+1L&&length(saved$body$conditions)==nc+1L&&identical(tail(saved$body$conditions,1L)[[1L]]$role,"control")&&is.null(context()))
      check("confirmation Save and both injected rollbacks occur inside the existing shared batch",length(hooks$save_in_batch)==3L&&all(hooks$save_in_batch)&&!RSQLite::sqliteIsTransacting(store$con))
      send(pin,title="Repeated delayed confirmation")
      check("repeated successful confirmation cannot create a second copy",!is.null(state$error)&&identical(after,cat_state())&&hooks$updates==1L)
      old<-open();fresh<-open();before<-cat_state()
      check("reopened dialog receives a fresh token",!identical(old$token,fresh$token))
      send(old,title="Old dialog must not save")
      check("old delayed confirmation cannot apply to a new modal context",!is.null(state$error)&&identical(before,cat_state())&&identical(context()$token,fresh$token))
      send(fresh,title="Explicit pooled version",condition=current$study$body$conditions[[1L]]$id)
      check("explicit existing-condition save creates no additional condition",is.null(state$error)&&length(current$study$body$conditions)==nc+1L&&
        identical(tail(current$study$body$stimuli,1L)[[1L]]$condition_id,current$study$body$conditions[[1L]]$id))
      pin<-open();before<-cat_state();before_record<-current$study;captures<-hooks$capture_calls
      changed<-current$study$body;changed$stimuli[[1L]]$duration_ms<-changed$stimuli[[1L]]$duration_ms+100L;current$study$body<-changed
      hooks$capture<-function()stop("Confirm must not recapture Plan",call.=FALSE)
      send(pin,title="Stale source")
      check("changed current source refuses before Save and confirm never recaptures Plan",!is.null(state$error)&&identical(before,cat_state())&&hooks$capture_calls==captures)
      hooks$capture<-function()invisible(NULL);current$study<-before_record
      pin<-open();changed<-current$study$body;changed$description<-"Concurrent retained revision"
      newer<-brohn_save_study(store,changed,current$study$revision);before<-cat_state()
      send(pin,title="Stale saved head")
      check("concurrent saved revision cannot be overwritten or partially appended",!is.null(state$error)&&identical(before,cat_state())&&equal(brohn_study(store,study$id)$body,newer$body))
      current$study<-newer
      pin<-open();project<-brohn_project(store,current$study$project_id);body<-project$body;body$archived<-TRUE
      archived<-brohn_put_entity(store,"project",project$id,body,expected_revision=project$revision);before<-cat_state()
      send(pin,title="After project access loss")
      check("fresh project archive refuses save without appended entities or objects",!is.null(state$error)&&identical(before,cat_state()))
      brohn_put_entity(store,"project",project$id,project$body,expected_revision=archived$revision)
      pin<-open();before<-cat_state();current$study<-foreign;state$study_id<-foreign$id;session$flushReact()
      send(pin,title="Wrong current study")
      check("changing current study clears or refuses the prior context",!is.null(state$error)&&identical(before,cat_state())&&is.null(context()))
      current$study<-brohn_study(store,study$id);state$study_id<-study$id;state$page<-"study";state$stage<-"Plan";session$flushReact()
      pin<-open();before<-cat_state();state$stage<-"Tasks";session$flushReact()
      send(pin,title="Hidden Plan confirmation")
      check("leaving Plan revokes an open modal action",!is.null(state$error)&&is.null(context())&&identical(before,cat_state()))
      session$setInputs(duplicate_stimulus=command)
      check("delayed Plan open command is refused on Tasks",!is.null(state$error)&&is.null(context())&&identical(before,cat_state()))
      state$stage<-"Plan";session$flushReact();pin<-open();before<-cat_state()
      session$setInputs(cancel_stimulus_version=list(token=pin$token))
      send(pin,title="Cancelled modal action")
      check("explicit cancellation revokes confirm token without catalog mutation",!is.null(state$error)&&is.null(context())&&identical(before,cat_state()))
      session$setInputs(study_form_identity=paste(foreign$id,"Plan",sep=":"));session$setInputs(duplicate_stimulus=command)
      check("stale study form cannot open a version dialog",!is.null(state$error)&&is.null(context())&&identical(before,cat_state()))
      pin<-open();before<-cat_state();state$page<-"home";session$flushReact();send(pin,title="Hidden study confirmation")
      check("leaving study page revokes the pending version",!is.null(state$error)&&is.null(context())&&identical(before,cat_state()))
    })
    check("controller actions allocate no scientific jobs or participants",DBI::dbGetQuery(store$con,"SELECT count(*) AS n FROM jobs")$n==0L&&!DBI::dbExistsTable(store$con,"delivery_runs"))
    passed<-TRUE
  }),envir=env)
})
